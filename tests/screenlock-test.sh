#!/bin/bash
# hypr/screenlock.lua: the lock screen comes up at 100% with no frozen view,
# and the unlock puts the zoom and the frozen views back (or not, by setting).

source "$(dirname "${BASH_SOURCE[0]}")/base.sh"

scratch_env

run_lua_test <<'LUA'
local FLAG = stub.SCREEN_LOCK_FLAG
local STATE = stub.STATE_FILE
local SHADER = stub.SHADER_FILE

local S = stub.new()
local mag = S:load(nil)
stub.check(type(OmarchyMagnifier.screen_lock) == "function", "OmarchyMagnifier.screen_lock is exported")
stub.eq(mag.screen_locked(), false, "not locked at load")

-- Unlock with no lock before it: nothing happens.
S:reset_calls()
stub.eq(mag.screen_lock(false), "unlocked", "screen_lock(false) with no lock returns unlocked")
stub.eq(#S.calls.config, 0, "an unlock with no lock before it changes nothing")

-- Lock at 500%.
mag.set_zoom(5)
S:reset_calls()
stub.eq(mag.screen_lock(true), "locked", "screen_lock(true) returns locked")
stub.eq(S:last_config("cursor.zoom_factor"), 1, "the lock sets the zoom to 1")
stub.contains(stub.read_file(FLAG), "5.0000", "the flag file holds the zoom from before the lock")
stub.contains(stub.read_file(STATE), "zoom 5.0000\n", "the state file is not rewritten by the lock")
stub.eq(#S:execs("magnifier show"), 0, "the lock shows no popup")

-- A second lock call must not overwrite the saved zoom with 1.
S:reset_calls()
mag.screen_lock(true)
stub.contains(stub.read_file(FLAG), "5.0000", "a repeated lock call keeps the saved zoom")
stub.eq(#S:config_values("cursor.zoom_factor"), 0, "a repeated lock call does not touch the zoom")

-- The catch-up timer stands still while locked (it would save 1, and would
-- push the zoom back up to a min_zoom above 1).
S:reset_calls()
S:fire_timers({ type = "repeat", timeout = 500 })
stub.contains(stub.read_file(STATE), "zoom 5.0000\n", "the 500 ms timer saves nothing while locked")
stub.eq(#S.calls.config, 0, "the 500 ms timer configures nothing while locked")

-- A config reload under the lock screen keeps 100%.
S = stub.new()
mag = S:load(nil)
stub.eq(mag.screen_locked(), true, "the lock flag survives a reload")
stub.eq(#S:config_values("cursor.zoom_factor"), 0, "a reload while locked does not restore the zoom")

-- Unlock: the zoom comes back, silently.
S:reset_calls()
stub.eq(mag.screen_lock(false), "unlocked", "screen_lock(false) returns unlocked")
stub.eq(S:last_config("cursor.zoom_factor"), 5, "the unlock restores the zoom from before the lock")
stub.eq(stub.read_file(FLAG), nil, "the unlock removes the flag file")
stub.eq(#S:execs("magnifier show"), 0, "the unlock shows no popup")
S:reset_calls()
S:fire_timers({ type = "repeat", timeout = 500 })
stub.eq(#S.calls.config, 0, "the timer has nothing to correct after the unlock")

-- Zoom off pressed at the lock screen is a no-op for the restore.
mag.screen_lock(true)
mag.zoom_off()
mag.screen_lock(false)
stub.eq(S:last_config("cursor.zoom_factor"), 5, "zoom off at the lock screen does not cancel the restore")

-- Locked at 100%: the zoom is not touched in either direction.
mag.set_zoom(1)
S:reset_calls()
mag.screen_lock(true)
mag.screen_lock(false)
stub.eq(#S:config_values("cursor.zoom_factor"), 0, "lock and unlock at 100% leave the zoom alone")

-- min_zoom above 1: the lock screen still gets 1, the unlock the old level.
S = stub.new()
mag = S:load({ min_zoom = 2 })
mag.set_zoom(4)
mag.screen_lock(true)
stub.eq(S:last_config("cursor.zoom_factor"), 1, "the lock goes to 1 even when min_zoom is 2")
S:fire_timers({ type = "repeat", timeout = 500 })
stub.eq(S:last_config("cursor.zoom_factor"), 1, "the timer does not clamp the lock screen back up to min_zoom")
mag.screen_lock(false)
stub.eq(S:last_config("cursor.zoom_factor"), 4, "the unlock restores 4")
mag.set_zoom(1)

-- Frozen views leave the shader while locked and come back after.
S = stub.new()
mag = S:load(nil)
local fx = mag.screenfx
fx.freeze(1, 3, 0.5, 0.5)
stub.contains(stub.read_file(SHADER), "wl_output == 1", "a frozen view is in the shader before the lock")
S:reset_calls()
mag.screen_lock(true)
stub.eq(S:last_config("decoration.screen_shader"), "", "the lock clears the shader when only frozen views were in it")
stub.check(fx.frozen(1) ~= nil, "the frozen view stays on file while locked")
S:reset_calls()
mag.screen_lock(false)
stub.eq(S:last_config("decoration.screen_shader"), SHADER, "the unlock installs the shader again")
stub.contains(stub.read_file(SHADER), "wl_output == 1", "the frozen view is back in the shader after the unlock")

-- Inversion stays on the lock screen; the frozen view does not.
fx.set_invert("on")
S:reset_calls()
mag.screen_lock(true)
stub.eq(S:last_config("decoration.screen_shader"), SHADER, "with inversion on, the shader stays installed while locked")
stub.contains(stub.read_file(SHADER), "1.0 - color.rgb", "the lock screen shader still inverts")
stub.lacks(stub.read_file(SHADER), "wl_output ==", "the lock screen shader has no frozen view")
mag.screen_lock(false)
stub.contains(stub.read_file(SHADER), "wl_output == 1", "the frozen view is back beside the inversion")
fx.set_invert("off")
fx.unfreeze_all()

-- restore_after_unlock = false: stay at 100% and drop the frozen views.
S = stub.new()
mag = S:load({ restore_after_unlock = false })
fx = mag.screenfx
mag.set_zoom(5)
fx.freeze(1, 3, 0.5, 0.5)
mag.screen_lock(true)
S:reset_calls()
mag.screen_lock(false)
stub.eq(#S:config_values("cursor.zoom_factor"), 0, "restore_after_unlock = false leaves the zoom at 100%")
stub.contains(stub.read_file(STATE), "zoom 1.0000\n", "restore_after_unlock = false saves 100% as the current zoom")
stub.eq(fx.frozen(1), nil, "restore_after_unlock = false drops the frozen views")
stub.eq(stub.read_file(FLAG), nil, "the flag file is removed")

-- lock_screen_reset = false: the lock changes nothing.
S = stub.new()
mag = S:load({ lock_screen_reset = false })
mag.set_zoom(5)
S:reset_calls()
stub.eq(mag.screen_lock(true), "unlocked", "lock_screen_reset = false ignores the lock")
stub.eq(#S.calls.config, 0, "lock_screen_reset = false leaves the zoom alone")
stub.eq(stub.read_file(FLAG), nil, "lock_screen_reset = false writes no flag")

-- Switched off while a flag from before is still there: the next call clears it.
S = stub.new()
mag = S:load(nil)
mag.set_zoom(5)
mag.screen_lock(true)
S = stub.new()
mag = S:load({ lock_screen_reset = false })
stub.eq(mag.screen_lock(true), "unlocked", "a left-over flag is cleared when the feature is off")
stub.eq(S:last_config("cursor.zoom_factor"), 5, "and the zoom from before the lock comes back")
LUA
