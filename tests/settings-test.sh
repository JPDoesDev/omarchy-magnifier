#!/bin/bash
# Settings merge in hypr/init.lua: defaults, coercion, fallbacks, limits, and
# which binds each switch registers.

source "$(dirname "${BASH_SOURCE[0]}")/base.sh"

scratch_env

run_lua_test <<'LUA'
-- Defaults with no settings table at all.
local S = stub.new()
local mag = S:load(nil)
local cfg = mag.settings

stub.eq(cfg.preset_zoom, 3, "default preset_zoom is 3")
stub.eq(cfg.off_zoom, 1, "default off_zoom is 1")
stub.eq(cfg.step, 1, "default step is 1")
stub.eq(cfg.min_zoom, 1, "default min_zoom is 1")
stub.eq(cfg.max_zoom, 10, "default max_zoom is 10")
stub.eq(cfg.osd, true, "default osd is on")
stub.eq(cfg.pinch, true, "default pinch is on")
stub.eq(cfg.side_buttons, false, "default side_buttons is off")
stub.eq(cfg.jump, true, "default jump is on")
stub.eq(cfg.mouse_lock, true, "default mouse_lock is on")
stub.eq(cfg.lock_gap, 20000, "default lock_gap is 20000")
stub.eq(cfg.keys.zoom_in, "CTRL + ALT + mouse_up", "default zoom_in chord")
stub.eq(cfg.keys.lock_toggle, "SUPER + CTRL + M", "default lock_toggle chord")
stub.eq(cfg.osd_style.font_size, 48, "default osd font_size is 48")
stub.eq(cfg.osd_style.duration_ms, 1200, "default osd duration_ms is 1200")
stub.eq(cfg.osd_style.border, false, "default osd border colour is unset (false)")
stub.eq(mag.plugin_id, "jpdoesdev.magnifier", "plugin id is jpdoesdev.magnifier")
stub.eq(mag.ipc_target, "magnifier", "IPC target is magnifier")
stub.eq(mag.dir, os.getenv("ROOT") .. "/hypr", "init.lua finds its own directory")

stub.eq(S:bind_keys("Magnifier zoom in"), "CTRL + ALT + mouse_up", "zoom in bound to its default chord")
stub.eq(S:bind_keys("Magnifier zoom out"), "CTRL + ALT + mouse_down", "zoom out bound to its default chord")
stub.eq(S:bind_keys("Magnifier zoom to preset"), "CTRL + ALT + Z", "preset bound to its default chord")
stub.eq(S:bind_keys("Magnifier zoom off"), "CTRL + ALT + X", "off bound to its default chord")
stub.eq(S:bind_keys("Magnifier jump to next monitor"), "SUPER + CTRL + mouse_down", "jump next bound to its default chord")
stub.eq(S:bind_keys("Magnifier jump to previous monitor"), "SUPER + CTRL + mouse_up", "jump prev bound to its default chord")
stub.eq(S:bind_keys("Magnifier mouse lock toggle"), "SUPER + CTRL + M", "lock toggle bound to its default chord")
stub.eq(#S.calls.bind, 8, "eight binds by default (4 zoom, 1 invert, 2 jump, 1 lock)")
for _, b in ipairs(S.calls.bind) do
  if type(b.dispatcher) ~= "function" then stub.fail("every bind carries a Lua function dispatcher", b.keys) end
  if type(b.description) ~= "string" then stub.fail("every bind carries a description", b.keys) end
end
stub.pass("every bind carries a Lua function dispatcher and a description")

stub.eq(#S.calls.gesture, 1, "one gesture registered by default")
local g = S.calls.gesture[1]
stub.eq(g.direction, "pinch", "gesture direction is pinch")
stub.eq(g.fingers, 2, "gesture uses two fingers by default")
stub.eq(g.mods, "SUPER", "gesture needs SUPER")
stub.eq(g.action, "cursor_zoom", "gesture action is cursor_zoom (the snake_case name Hyprland 0.56 ships)")
stub.eq(g.zoom_level, 1.0, "gesture zoom_level is 1.0 by default")
stub.eq(math.type(g.fingers), "integer", "gesture fingers is an integer")

for _, name in ipairs({ "zoom_in", "zoom_out", "zoom_preset", "zoom_off", "zoom_toggle", "zoom_set",
                        "jump", "jump_next", "jump_prev", "lock", "lock_sync", "unfreeze_all" }) do
  if type(OmarchyMagnifier[name]) ~= "function" then stub.fail("OmarchyMagnifier." .. name .. " is exported") end
end
stub.pass("OmarchyMagnifier exports the public API for the CLI")

-- Coercion and fallbacks.
S = stub.new()
mag = S:load({
  preset_zoom = "5", step = "0.5", off_zoom = "abc", osd = "yes", pinch_fingers = 3.7,
  min_zoom = 0, max_zoom = 50, lock_gap = "15000",
  keys = { off = false, preset = "", zoom_in = 42 },
  osd_style = { border = "#ffff00", text = "nope", background = "#12345", font_size = "64", padding = {} },
})
cfg = mag.settings
stub.eq(cfg.preset_zoom, 5, "numeric string preset_zoom coerced to 5")
stub.eq(cfg.step, 0.5, "numeric string step coerced to 0.5")
stub.eq(cfg.off_zoom, 1, "non-numeric off_zoom falls back to the default")
stub.eq(cfg.osd, true, "string osd falls back to the boolean default")
stub.eq(cfg.pinch_fingers, 3.7, "pinch_fingers kept as given (floored at the gesture)")
stub.eq(S.calls.gesture[1].fingers, 3, "gesture fingers floored to an integer")
stub.eq(cfg.lock_gap, 15000, "numeric string lock_gap coerced")
stub.eq(cfg.min_zoom, 1, "min_zoom = 0 sanitised to 1")
stub.eq(cfg.max_zoom, 10, "max_zoom = 50 sanitised to 10")
stub.eq(cfg.keys.off, false, "keys.off = false is kept as false")
stub.eq(cfg.keys.preset, "CTRL + ALT + Z", "keys.preset = '' falls back to the default chord")
stub.eq(cfg.keys.zoom_in, "CTRL + ALT + mouse_up", "non-string key falls back to the default chord")
stub.eq(cfg.osd_style.border, "#ffff00", "osd_style.border = '#ffff00' is kept")
stub.eq(cfg.osd_style.text, false, "osd_style.text = 'nope' is dropped to false")
stub.eq(cfg.osd_style.background, false, "five-digit colour is dropped to false")
stub.eq(cfg.osd_style.font_size, 64, "numeric string font_size coerced")
stub.eq(cfg.osd_style.padding, 15, "table padding falls back to the default")
stub.eq(#S:binds_for("Magnifier zoom off"), 0, "keys.off = false leaves the off chord unbound")
stub.eq(S:bind_keys("Magnifier zoom to preset"), "CTRL + ALT + Z", "preset is still bound beside a disabled key")
stub.eq(#S.calls.bind, 7, "seven binds when one key is disabled")

S = stub.new()
cfg = S:load({ min_zoom = 5, max_zoom = 3 }).settings
stub.eq(cfg.min_zoom, 5, "min_zoom = 5 kept")
stub.eq(cfg.max_zoom, 5, "max_zoom below min_zoom raised to min_zoom")

S = stub.new()
cfg = S:load({ min_zoom = "x", max_zoom = {}, step = 0 }).settings
stub.eq(cfg.min_zoom, 1, "non-numeric min_zoom falls back to 1")
stub.eq(cfg.max_zoom, 10, "table max_zoom falls back to 10")
stub.eq(cfg.step, 0.1, "step = 0 raised to 0.1")

S = stub.new()
cfg = S:load({ keys = "garbage", osd_style = 7 }).settings
stub.eq(cfg.keys.zoom_in, "CTRL + ALT + mouse_up", "non-table keys falls back to all default chords")
stub.eq(cfg.osd_style.font_size, 48, "non-table osd_style falls back to all defaults")

S = stub.new()
cfg = S:load({ preset_zoom = true }).settings
stub.eq(cfg.preset_zoom, 3, "boolean preset_zoom falls back to the default")

-- Switches.
S = stub.new()
S:load(nil)
local mouse = 0
for _, b in ipairs(S.calls.bind) do if b.keys:find("mouse:", 1, true) then mouse = mouse + 1 end end
stub.eq(mouse, 0, "no SUPER + mouse:N bind unless side_buttons is on")

S = stub.new()
S:load({ jump = false })
stub.eq(#S:binds_for("Magnifier jump to next monitor") + #S:binds_for("Magnifier jump to previous monitor"), 0,
  "jump = false registers no jump binds")
stub.eq(S:bind_keys("Magnifier mouse lock toggle"), "SUPER + CTRL + M", "jump = false keeps the lock bind")
stub.check(type(OmarchyMagnifier.jump_next) == "function", "jump = false keeps the jump API for the CLI")

S = stub.new()
S:load({ mouse_lock = false })
stub.eq(#S:binds_for("Magnifier mouse lock toggle"), 0, "mouse_lock = false registers no lock bind")
stub.eq(#S:handlers("monitor.added") + #S:handlers("monitor.removed"), 0, "mouse_lock = false subscribes to no monitor events")
stub.eq(#S:timers({ type = "oneshot" }), 0, "mouse_lock = false schedules no lock syncs")
stub.eq(S:bind_keys("Magnifier zoom in"), "CTRL + ALT + mouse_up", "mouse_lock = false keeps the zoom binds")

S = stub.new()
S:load({ pinch = false })
stub.eq(#S.calls.gesture, 0, "pinch = false registers no gesture")

S = stub.new()
S:load({ pinch_fingers = 3, pinch_zoom_level = "1.5" })
stub.eq(S.calls.gesture[1].fingers, 3, "pinch_fingers = 3 reaches the gesture")
stub.eq(S.calls.gesture[1].zoom_level, 1.5, "pinch_zoom_level string coerced for the gesture")

S = stub.new()
S:load({ keys = { zoom_in = "SUPER + equal", zoom_out = "SUPER + minus", jump_next = false, lock_toggle = false } })
stub.eq(S:bind_keys("Magnifier zoom in"), "SUPER + equal", "custom zoom_in chord is used")
stub.eq(S:bind_keys("Magnifier zoom out"), "SUPER + minus", "custom zoom_out chord is used")
stub.eq(#S:binds_for("Magnifier jump to next monitor"), 0, "keys.jump_next = false leaves jump next unbound")
stub.eq(S:bind_keys("Magnifier jump to previous monitor"), "SUPER + CTRL + mouse_up", "jump prev stays bound beside a disabled jump next")
stub.eq(#S:binds_for("Magnifier mouse lock toggle"), 0, "keys.lock_toggle = false leaves the lock chord unbound")

-- With Omarchy's helper loaded, binds go through o.bind so they show up in
-- the SUPER + K menu; the function dispatcher must pass through untouched.
local via_o = {}
_G.o = {
  bind = function(keys, description, dispatcher, options)
    via_o[#via_o + 1] = { keys = keys, description = description, dispatcher = dispatcher, options = options }
  end,
}
S = stub.new()
S:load(nil)
stub.eq(#S.calls.bind, 0, "with o.bind present, hl.bind is not called directly")
stub.eq(#via_o, 8, "with o.bind present, all eight binds go through it")
stub.check(type(via_o[1].dispatcher) == "function" and type(via_o[1].description) == "string",
  "o.bind receives (keys, description, function)")
_G.o = nil

-- A settings table must never break loading.
S = stub.new()
local ok, err = pcall(function()
  return S:load({ keys = { off = 0 }, osd_style = { border = 0 }, preset_zoom = {}, step = -5, max_zoom = "" })
end)
stub.check(ok, "a table full of wrong types still loads", err)

-- side_buttons = true must add the two SUPER + mouse:N binds. Kept last:
-- init.lua merge() tests `d == false or type(d) == "string"` before the
-- boolean branch, so a default of false can only be overridden by a string
-- and `true` is dropped. These fail until that is fixed.
S = stub.new()
S:load({ side_buttons = true })
stub.check(S:bind_keys("Magnifier zoom to preset (side button)") == "SUPER + mouse:276",
  "side_buttons = true binds SUPER + mouse:276 to preset")
stub.check(S:bind_keys("Magnifier zoom off (side button)") == "SUPER + mouse:275",
  "side_buttons = true binds SUPER + mouse:275 to off")
stub.eq(#S.calls.bind, 10, "side buttons add exactly two binds")

S = stub.new()
S:load({ side_buttons = true, side_button_in = "277", side_button_out = 278.0 })
stub.eq(S:bind_keys("Magnifier zoom to preset (side button)"), "SUPER + mouse:277", "side_button_in accepts a numeric string")
stub.eq(S:bind_keys("Magnifier zoom off (side button)"), "SUPER + mouse:278", "side_button_out float prints without a decimal point")

LUA
