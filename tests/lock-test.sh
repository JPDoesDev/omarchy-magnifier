#!/bin/bash
# hypr/lock.lua: the gapped monitor layout written as an Omarchy Hyprland
# toggle, when it reloads, the unlock file, and the reload guard.

source "$(dirname "${BASH_SOURCE[0]}")/base.sh"

require_command "${LUAC:-luac}"

run_lock_tests() {
  run_lua_test <<'LUA'
local FLAG = stub.FLAG_FILE
local UNLOCK = stub.UNLOCK_FILE
local FROZEN = stub.FROZEN_FILE
local TMP = os.getenv("MAG_TEST_TMP")
local GUARD_PAUSED = TMP .. "/guard-paused"

local function two_monitors(edp)
  local list = {
    stub.monitor({ id = 1, name = "eDP-1", x = 2560, y = 0, width = 1920, height = 1200, scale = 1.5 }),
    stub.monitor({ id = 0, name = "DP-1", x = 0, y = 0, width = 2560, height = 1440, scale = 1 }),
    stub.monitor({ id = 2, name = "FALLBACK", x = 0, y = 0, width = 0, height = 0 }),
    stub.monitor({ id = 3, name = "HDMI-A-1", x = 0, y = 0, width = 1920, height = 1080, is_mirror = true }),
  }
  for k, v in pairs(edp or {}) do list[1][k] = v end
  return list
end

local function reloads(S) return #S:execs("^hyprctl reload$") end

local function fresh(settings, monitors)
  stub.remove(FLAG)
  stub.remove(UNLOCK)
  local S = stub.new()
  S.monitors = monitors or two_monitors()
  S.cursor = { x = 100, y = 200 }
  local mag = S:load(settings)
  return S, mag
end

-- Load, locked, two monitors: the flag is written by the first delayed sync.
local S, mag = fresh(nil)
stub.check(not stub.exists(FLAG), "load itself writes no flag (syncs are delayed)")
local oneshots = S:timers({ type = "oneshot" })
stub.eq(#oneshots, 4, "four delayed syncs are scheduled at load")
stub.check(oneshots[1].timeout == 50 and oneshots[4].timeout == 7000, "the syncs run at 50 ms .. 7 s")
stub.eq(mag.lock.locked(), true, "the lock is on by default")
stub.eq(mag.lock.set("status"), "locked", "lock status reports locked")

S:fire_timers({ type = "oneshot", timeout = 50 })
stub.check(stub.exists(FLAG), "the flag file is written under $XDG_STATE_HOME/omarchy/toggles/hypr/magnifier-mouse-lock.lua")
local flag = stub.read_file(FLAG)
stub.eq(stub.count_lines(flag, "^hl%.monitor%("), 2, "one hl.monitor({...}) line per usable monitor")
stub.check(flag:find('hl.monitor({ output = "DP-1", mode = "2560x1440@60.000", position = "0x0", scale = 1 })', 1, true),
  "the first monitor sits at position 0x0 with its mode WxH@RRR.rrr and scale", flag)
stub.check(flag:find('hl.monitor({ output = "eDP-1", mode = "1920x1200@60.000", position = "22560x0", scale = 1.5 })', 1, true),
  "the second monitor sits at x = 2560 + min(20000, floor((30000 - 3840) / 1)) = 22560", flag)
stub.lacks(flag, "transform", "unrotated monitors carry no transform")
stub.lacks(flag, "FALLBACK", "FALLBACK is not written")
stub.lacks(flag, "HDMI-A-1", "the mirror is not written")
stub.check(flag:sub(1, 2) == "--", "the flag starts with a comment naming the plugin")
stub.eq(reloads(S), 1, "writing the flag triggers one hyprctl reload")
stub.write_file(TMP .. "/flag-copy.lua", flag) -- luac -p runs on this from bash

-- The generated Lua runs and produces the expected hl.monitor calls.
local S2 = stub.new()
dofile(FLAG)
stub.eq(#S2.calls.monitor, 2, "executing the flag calls hl.monitor twice")
local a, b = S2.calls.monitor[1], S2.calls.monitor[2]
stub.check(a.output == "DP-1" and a.mode == "2560x1440@60.000" and a.position == "0x0" and a.scale == 1 and a.transform == nil,
  "the first hl.monitor spec is { output, mode, position = \"0x0\", scale }")
stub.check(b.output == "eDP-1" and b.mode == "1920x1200@60.000" and b.position == "22560x0" and b.scale == 1.5,
  "the second hl.monitor spec places eDP-1 at 22560x0 with scale 1.5")
_G.hl = S.hl

-- Re-sync after the reload took effect: nothing happens.
S.monitors[1].x = 22560
S:reset_calls()
S:fire_timers({ type = "oneshot" }) -- the remaining three
stub.eq(reloads(S), 0, "the later syncs do not reload once the layout matches")
stub.eq(stub.read_file(FLAG), flag, "an unchanged re-sync rewrites nothing")
mag.lock.sync()
stub.eq(reloads(S), 0, "a direct sync with a matching layout does not reload")

-- Something un-gapped the layout (Omarchy's scale pill): reload without rewriting.
S.monitors[1].x = 2560
S:reset_calls()
mag.lock.sync()
stub.eq(reloads(S), 1, "a position mismatch triggers a reload")
stub.eq(stub.read_file(FLAG), flag, "a position mismatch leaves the flag content as it was")
S.monitors[1].x = 22560

-- Unlock and lock again.
S:reset_calls()
stub.eq(mag.lock.set("off"), "unlocked", "lock(\"off\") reports unlocked")
stub.check(stub.exists(UNLOCK), "lock(\"off\") creates the unlock file in $XDG_RUNTIME_DIR")
stub.check(not stub.exists(FLAG), "lock(\"off\") removes the flag")
stub.eq(reloads(S), 1, "lock(\"off\") reloads once")
stub.contains(S:execs("^omarchy%-notification%-send ")[1] or "", "unlocked", "lock(\"off\") notifies that the mouse is unlocked")
stub.eq(mag.lock.set("status"), "unlocked", "status reports unlocked")
S:reset_calls()
stub.eq(mag.lock.set("off"), "unlocked", "a second lock(\"off\") is a no-op")
stub.eq(reloads(S), 0, "a second lock(\"off\") does not reload")
S.monitors[1].x = 2560 -- the reload un-gapped the layout
S:reset_calls()
mag.lock.sync()
stub.eq(reloads(S), 0, "while unlocked a sync never reloads")
stub.check(not stub.exists(FLAG), "while unlocked no flag is written")

S:reset_calls()
stub.eq(mag.lock.set("on"), "locked", "lock(\"on\") reports locked")
stub.check(not stub.exists(UNLOCK), "lock(\"on\") removes the unlock file")
stub.eq(stub.read_file(FLAG), flag, "lock(\"on\") rewrites the same flag")
stub.eq(reloads(S), 1, "lock(\"on\") reloads once")
stub.contains(S:execs("^omarchy%-notification%-send ")[1] or "", "SUPER + CTRL + mouse_down", "the locked notification names the jump chord")
S.monitors[1].x = 22560

S:reset_calls()
stub.eq(mag.lock.set("toggle"), "unlocked", "toggle from locked unlocks")
stub.eq(mag.lock.set("toggle"), "locked", "toggle from unlocked locks")
stub.eq(reloads(S), 2, "each toggle reloads once")
S.monitors[1].x = 22560
stub.eq(OmarchyMagnifier.lock("status"), "locked", "OmarchyMagnifier.lock is the same entry point")
S:reset_calls()
S:press("SUPER + CTRL + M")
stub.check(stub.exists(UNLOCK), "the SUPER + CTRL + M chord toggles the lock")
mag.lock.set("on")
S.monitors[1].x = 22560

-- Hotplug: re-lock, drop frozen views, schedule syncs again.
mag.lock.set("off")
stub.write_file(FROZEN, "0 3.0000 0.25000 0.50000\n")
local before = #S:timers({ type = "oneshot" })
S:reset_calls()
stub.eq(S:fire_event("monitor.added"), 1, "one handler is subscribed to monitor.added")
stub.check(not stub.exists(UNLOCK), "a monitor change re-locks")
stub.check(not stub.exists(FROZEN), "a monitor change drops the frozen views")
stub.eq(#S:timers({ type = "oneshot" }) - before, 4, "a monitor change schedules four more syncs")
stub.eq(#S:handlers("monitor.removed"), 1, "one handler is subscribed to monitor.removed")
stub.eq(reloads(S), 0, "a monitor change itself does not reload synchronously")

-- Gap formula below the cap, rotation, and the 2000 floor.
S, mag = fresh({ lock_gap = 30000 })
S:fire_timers({ type = "oneshot", timeout = 50 })
stub.contains(stub.read_file(FLAG), 'output = "eDP-1", mode = "1920x1200@60.000", position = "28720x0"',
  "with a large lock_gap the gap is floor((30000 - 3840) / 1) = 26160")

S, mag = fresh({ lock_gap = 30000 }, two_monitors({ transform = 1 }))
S:fire_timers({ type = "oneshot", timeout = 50 })
flag = stub.read_file(FLAG)
stub.contains(flag, 'output = "eDP-1", mode = "1920x1200@60.000", position = "29200x0", scale = 1.5, transform = 1 })',
  "a rotated monitor keeps its transform and its logical width (800) shortens the gap sum")
stub.write_file(TMP .. "/flag-rotated.lua", flag)

S, mag = fresh({ lock_gap = 1 })
S:fire_timers({ type = "oneshot", timeout = 50 })
stub.contains(stub.read_file(FLAG), 'position = "4560x0"', "the gap never drops below 2000")

S, mag = fresh(nil, two_monitors({ refresh_rate = 59.9994, y = -200 }))
S:fire_timers({ type = "oneshot", timeout = 50 })
stub.contains(stub.read_file(FLAG), 'mode = "1920x1200@59.999", position = "22560x-200"',
  "the mode rounds the refresh rate to three decimals and the y offset is kept")

-- One usable monitor: no flag; a stale one is removed.
S, mag = fresh(nil, { stub.monitor({ id = 0, name = "DP-1", width = 2560, height = 1440 }) })
S:fire_timers({ type = "oneshot" })
stub.check(not stub.exists(FLAG), "one monitor writes no flag")
stub.eq(reloads(S), 0, "one monitor with no flag never reloads")
S:reset_calls()
stub.eq(mag.lock.set("toggle"), "unlocked", "toggle with one monitor still records the state")
stub.contains(S:execs("^omarchy%-notification%-send ")[1] or "", "two or more monitors", "toggle with one monitor explains it needs two")
stub.eq(reloads(S), 0, "toggle with one monitor does not reload")

S, mag = fresh(nil, { stub.monitor({ id = 0, name = "DP-1", width = 2560, height = 1440 }) })
stub.write_file(FLAG, "stale\n") -- left behind by a two-monitor session
S:fire_timers({ type = "oneshot", timeout = 50 })
stub.check(not stub.exists(FLAG), "one monitor removes a stale flag")
stub.eq(reloads(S), 1, "removing a stale flag reloads once")

-- Unsafe names are skipped rather than interpolated into Lua.
S, mag = fresh(nil, two_monitors({ name = 'X"); os.exit(1) --' }))
S:fire_timers({ type = "oneshot", timeout = 50 })
stub.check(not stub.exists(FLAG), "a monitor name with quotes is not written into the flag (only one safe monitor left)")

-- mouse_lock = false: a stale flag goes at load, then nothing else.
stub.write_file(FLAG, "stale\n")
S = stub.new()
S.monitors = two_monitors()
mag = S:load({ mouse_lock = false })
stub.check(not stub.exists(FLAG), "mouse_lock = false removes a stale flag at load")
stub.eq(reloads(S), 1, "mouse_lock = false reloads once to drop the stale flag")
stub.eq(#S:timers({ type = "oneshot" }), 0, "mouse_lock = false schedules no syncs")
S:reset_calls()
S = stub.new()
S.monitors = two_monitors()
mag = S:load({ mouse_lock = false })
stub.eq(reloads(S), 0, "mouse_lock = false with no flag does not reload")
stub.eq(mag.lock.set("status"), "locked", "mouse_lock = false still answers status for the CLI")

-- Reload guard: while Omarchy pauses reloads, sync does nothing.
stub.write_file(GUARD_PAUSED, "")
S, mag = fresh(nil)
S:fire_timers({ type = "oneshot" })
stub.check(not stub.exists(FLAG), "while the reload guard is paused no flag is written")
stub.eq(reloads(S), 0, "while the reload guard is paused nothing reloads")
stub.remove(GUARD_PAUSED)
mag.lock.sync()
stub.check(stub.exists(FLAG), "once the guard resumes the next sync writes the flag")

-- Kept last: the same check as Hyprland runs it. Inside the compositor
-- os.execute() returns nil, "No child processes", 10 for every command
-- (Hyprland reaps its children; see Omarchy's helpers.lua o.shell_succeeds),
-- so `os.execute(...) == true` in lock.lua reload_paused() can never be
-- true and the guard is silently ignored. This fails until reload_paused()
-- reads a marker from io.popen instead.
stub.emulate_child_reaping()
stub.write_file(GUARD_PAUSED, "")
S, mag = fresh(nil)
S:fire_timers({ type = "oneshot" })
stub.eq(reloads(S), 0, "the reload guard is honoured when the compositor reaps children (os.execute has no exit status)")
stub.remove(GUARD_PAUSED)
LUA
}

scratch_env
run_lock_tests
lua_status=$?

# The Lua part copies the generated flag files out for a real syntax check.
for copy in flag-copy flag-rotated; do
  [[ -f $MAG_TEST_TMP/$copy.lua ]] || fail "the Lua part left $copy.lua for the syntax check"
  output=$("${LUAC:-luac}" -p "$MAG_TEST_TMP/$copy.lua" 2>&1) || fail "the generated $copy.lua is valid Lua (luac -p)" "$output"
  pass "the generated $copy.lua is valid Lua (luac -p)"
done

exit "$lua_status"
