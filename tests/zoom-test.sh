#!/bin/bash
# hypr/magnifier.lua: stepping, clamping, toggle, the OSD payload, the state
# file, restore after a reload, and the 500 ms catch-up timer.

source "$(dirname "${BASH_SOURCE[0]}")/base.sh"

scratch_env

run_lua_test <<'LUA'
local STATE = stub.STATE_FILE

local S = stub.new()
local mag = S:load(nil)
stub.eq(#S:config_values("cursor.zoom_factor"), 0, "no zoom is applied at load without a state file")
stub.check(not stub.exists(STATE), "no state file is written at load")

-- Steps.
stub.eq(mag.zoom_in(), 2, "zoom_in from 1 with step 1 returns 2")
stub.eq(S:last_config("cursor.zoom_factor"), 2, "zoom_in sets cursor.zoom_factor to 2")
stub.eq(mag.current_zoom(), 2, "current_zoom reads the value back")
for _ = 1, 12 do mag.zoom_in() end
stub.eq(S:last_config("cursor.zoom_factor"), 10, "zoom_in clamps at max_zoom 10")
stub.eq(mag.zoom_in(), 10, "zoom_in at the ceiling stays at 10")
for _ = 1, 12 do mag.zoom_out() end
stub.eq(S:last_config("cursor.zoom_factor"), 1, "zoom_out clamps at min_zoom 1")
stub.eq(mag.zoom_out(), 1, "zoom_out at the floor stays at 1")

-- Toggle between off and preset.
stub.eq(mag.zoom_toggle(), 3, "zoom_toggle from off goes to the preset (3)")
stub.eq(mag.zoom_toggle(), 1, "zoom_toggle from the preset goes back to off (1)")
mag.set_zoom(7)
stub.eq(mag.zoom_toggle(), 1, "zoom_toggle from any magnified level goes to off")
stub.eq(mag.zoom_preset(), 3, "zoom_preset returns the preset")
stub.eq(mag.zoom_off(), 1, "zoom_off returns off_zoom")

-- set_zoom: state file and OSD.
S:reset_calls()
stub.eq(mag.set_zoom(5), 5, "set_zoom(5) returns 5")
stub.eq(S:last_config("cursor.zoom_factor"), 5, "set_zoom(5) applies 5")
stub.contains(stub.read_file(STATE), "zoom 5.0000\n", "set_zoom writes `zoom 5.0000` to the state file")
local shows = S:execs("^omarchy%-shell %-q magnifier show '")
stub.eq(#shows, 1, "set_zoom calls omarchy-shell -q magnifier show once")
local payload = shows[1]:match("show '(.*)'$")
stub.contains(payload, '"zoom":5', "payload carries \"zoom\":5")
for _, pair in ipairs({ '"fontSize":48', '"durationMs":1200', '"borderWidth":4', '"padding":15',
                        '"minScale":2', '"pointerGap":104', '"pointerDrop":28' }) do
  stub.contains(payload, pair, "payload style carries " .. pair)
end
stub.contains(payload, '"style":{', "payload nests the style object")
stub.lacks(payload, '"border"', "unset colours are left out of the payload")
stub.check(payload:sub(1, 1) == "{" and payload:sub(-1) == "}", "payload is one JSON object")
stub.eq(mag.set_zoom(14), 10, "set_zoom above max is clamped")
stub.eq(mag.set_zoom(0.5), 1, "set_zoom below min is clamped")
stub.eq(mag.set_zoom("4"), 4, "set_zoom accepts a numeric string")
stub.eq(mag.set_zoom(nil), 1, "set_zoom(nil) falls back to 1")

S:reset_calls()
mag.set_zoom(2.5)
payload = S:execs("magnifier show")[1]:match("show '(.*)'$")
stub.contains(payload, '"zoom":2.5000', "fractional zoom is sent with four decimals")

-- silent skips the popup; osd = false never shows one.
S:reset_calls()
mag.set_zoom(2, { silent = true })
stub.eq(#S:execs("magnifier show"), 0, "set_zoom with silent does not call the OSD")
stub.eq(S:last_config("cursor.zoom_factor"), 2, "silent set_zoom still applies the zoom")
stub.contains(stub.read_file(STATE), "zoom 2.0000\n", "silent set_zoom still saves the state")

stub.remove(STATE)
S = stub.new()
mag = S:load({ osd = false })
mag.zoom_in()
stub.eq(#S:execs("omarchy%-shell"), 0, "osd = false shows no popup")
stub.eq(S:last_config("cursor.zoom_factor"), 2, "osd = false still zooms")

-- Style overrides travel with every show.
stub.remove(STATE)
S = stub.new()
mag = S:load({ osd_style = { border = "#ffff00", font_size = 72 } })
mag.zoom_in()
payload = S:execs("magnifier show")[1]:match("show '(.*)'$")
stub.contains(payload, '"border":"#ffff00"', "forced border colour is sent to the OSD")
stub.contains(payload, '"fontSize":72', "custom font size is sent to the OSD")

-- Custom limits and step.
stub.remove(STATE)
S = stub.new()
mag = S:load({ step = 2, min_zoom = 2, max_zoom = 6, preset_zoom = 4 })
stub.eq(mag.zoom_in(), 3, "zoom_in from 1 with step 2 gives 3")
stub.eq(mag.zoom_in(), 5, "zoom_in steps by 2")
stub.eq(mag.zoom_in(), 6, "zoom_in clamps at a custom max_zoom")
for _ = 1, 5 do mag.zoom_out() end
stub.eq(S:last_config("cursor.zoom_factor"), 2, "zoom_out clamps at a custom min_zoom")

-- Bound chords drive the same functions.
stub.remove(STATE)
S = stub.new()
mag = S:load(nil)
stub.check(S:press("CTRL + ALT + mouse_up"), "the zoom in chord has a function to press")
stub.eq(S:last_config("cursor.zoom_factor"), 2, "pressing CTRL + ALT + mouse_up zooms in")
S:press("CTRL + ALT + Z")
stub.eq(S:last_config("cursor.zoom_factor"), 3, "pressing CTRL + ALT + Z goes to the preset")
S:press("CTRL + ALT + X")
stub.eq(S:last_config("cursor.zoom_factor"), 1, "pressing CTRL + ALT + X zooms off")

-- Restore after a reload: the state file is read and the zoom re-applied silently.
stub.write_file(STATE, "zoom 4.0000\nmem DP-1 100.00 200.00 3.0000\n")
S = stub.new()
mag = S:load(nil)
stub.eq(S:last_config("cursor.zoom_factor"), 4, "a saved zoom of 4 is re-applied at load")
stub.eq(#S:execs("magnifier show"), 0, "restoring at load shows no popup")
stub.check(mag.state.memory["DP-1"] and mag.state.memory["DP-1"].zoom == 3
  and mag.state.memory["DP-1"].x == 100 and mag.state.memory["DP-1"].y == 200,
  "per-monitor memory is restored from the state file")

stub.write_file(STATE, "zoom 12.0000\n")
S = stub.new()
mag = S:load(nil)
stub.eq(S:last_config("cursor.zoom_factor"), 10, "an out-of-range saved zoom is clamped on restore")

stub.write_file(STATE, "zoom 1.0000\n")
S = stub.new()
mag = S:load(nil)
stub.eq(#S:config_values("cursor.zoom_factor"), 0, "a saved zoom of 1 applies nothing")

stub.write_file(STATE, "garbage\n")
S = stub.new()
local ok, err = pcall(S.load, S, nil)
stub.check(ok, "a corrupt state file does not break loading", err)
stub.remove(STATE)

-- The 500 ms timer: clamps a zoom set behind the plugin's back and keeps the
-- state file current, writing nothing while the value is unchanged.
stub.remove(STATE)
S = stub.new()
mag = S:load(nil)
local timers = S:timers({ type = "repeat" })
stub.eq(#timers, 1, "exactly one repeating timer is registered")
stub.eq(timers[1].timeout, 500, "the repeating timer fires every 500 ms")

S.values["cursor.zoom_factor"] = 12 -- a pinch or another script went past the limit
S:reset_calls()
S:fire_timers({ type = "repeat" })
stub.eq(S:last_config("cursor.zoom_factor"), 10, "the timer clamps 12 back to max_zoom 10")
stub.contains(stub.read_file(STATE), "zoom 10.0000\n", "the timer saves the clamped value")

stub.remove(STATE)
S:reset_calls()
S:fire_timers({ type = "repeat" })
stub.check(not stub.exists(STATE), "the timer writes nothing while the zoom is unchanged")
stub.eq(#S:config_values("cursor.zoom_factor"), 0, "the timer reconfigures nothing while the zoom is unchanged")
stub.eq(#S:execs("magnifier show"), 0, "the timer never shows the popup")

S.values["cursor.zoom_factor"] = 5 -- in range: save only
S:fire_timers({ type = "repeat" })
stub.eq(#S:config_values("cursor.zoom_factor"), 0, "an in-range outside change is not re-applied")
stub.contains(stub.read_file(STATE), "zoom 5.0000\n", "an in-range outside change is saved")

S.values["cursor.zoom_factor"] = 0.5
S:fire_timers({ type = "repeat" })
stub.eq(S:last_config("cursor.zoom_factor"), 1, "the timer clamps below min_zoom back to 1")

-- Memory lines are written alongside the zoom.
mag.state.memory["eDP-1"] = { x = 10.5, y = 20, zoom = 2 }
mag.save_state()
stub.contains(stub.read_file(STATE), "mem eDP-1 10.50 20.00 2.0000\n", "save_state writes a mem line per monitor")

-- Kept last: off_zoom below min_zoom must not wedge zoom_toggle. With
-- off_zoom = 0 (a natural way to write "off"), set_zoom clamps to 1 but
-- zoom_toggle compares against the raw 0, so every toggle goes "off" and the
-- preset is unreachable. init.lua should clamp off_zoom/preset_zoom into
-- [min_zoom, max_zoom] after sanitising the limits.
stub.remove(STATE)
S = stub.new()
mag = S:load({ off_zoom = 0 })
stub.eq(mag.zoom_toggle(), 3, "zoom_toggle reaches the preset when off_zoom is written as 0")
LUA
