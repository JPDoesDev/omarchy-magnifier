#!/bin/bash
# hypr/jump.lua: monitor ordering, wrap-around, pointer and zoom memory, the
# frozen view left behind, rotated monitors.

source "$(dirname "${BASH_SOURCE[0]}")/base.sh"

scratch_env

run_lua_test <<'LUA'
local FROZEN = stub.FROZEN_FILE
local STATE = stub.STATE_FILE
local SHADER = stub.SHADER_FILE

-- DP-1 2560x1440 @1 at x 0, eDP-1 1920x1200 @1.5 (logical 1280x800) at x 2560,
-- plus a FALLBACK and a mirror that must be ignored. Listed out of order on
-- purpose. `edp` overrides fields of eDP-1.
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

local S = stub.new()
S.monitors = two_monitors()
S.cursor = { x = 100, y = 200 }
local mag = S:load(nil)

-- Ordering and wrap-around.
local mons = mag.jump.monitors()
stub.eq(#mons, 2, "FALLBACK and the mirror are ignored")
stub.eq(mons[1].name, "DP-1", "monitors are ordered left to right (DP-1 first)")
stub.eq(mons[2].name, "eDP-1", "monitors are ordered left to right (eDP-1 second)")

local target, cur = mag.jump.neighbour(1)
stub.eq(cur and cur.name, "DP-1", "neighbour reports the monitor under the pointer")
stub.eq(target.name, "eDP-1", "next from DP-1 is eDP-1")
stub.eq(mag.jump.neighbour(-1).name, "eDP-1", "previous from DP-1 wraps to eDP-1")
S.cursor = { x = 3000, y = 100 }
stub.eq(mag.jump.neighbour(1).name, "DP-1", "next from eDP-1 wraps to DP-1")
stub.eq(mag.jump.neighbour(-1).name, "DP-1", "previous from eDP-1 is DP-1")
S.cursor = { x = -50, y = -50 } -- on no monitor at all
target, cur = mag.jump.neighbour(1)
stub.check(cur == nil and target.name == "eDP-1", "with the pointer on no monitor, next counts from the first")

-- First jump: DP-1 magnified at 3x, pointer at (100, 200).
S.cursor = { x = 100, y = 200 }
S.values["cursor.zoom_factor"] = 3
S:reset_calls()
stub.eq(mag.api.jump_next(), true, "jump_next reports success with two monitors")

local mem = mag.state.memory["DP-1"]
stub.check(mem and mem.x == 100 and mem.y == 200 and mem.zoom == 3,
  "leaving DP-1 remembers its relative pointer position and zoom", mem and (mem.x .. "," .. mem.y .. "@" .. mem.zoom))
stub.contains(stub.read_file(STATE), "mem DP-1 100.00 200.00 3.0000\n", "the memory is saved to the state file")

local frozen = stub.read_file(FROZEN)
stub.contains(frozen, "0 3.0000 0.03906 0.13889\n", "DP-1 (output 0) is frozen at 3x around the pointer's normalised spot")
stub.contains(stub.read_file(SHADER), "if (wl_output == 0)", "the shader targets output 0")

local focus = S:dispatched("focus")
stub.eq(#focus, 1, "one focus dispatch")
stub.eq(focus[1].args[1].monitor, "eDP-1", "keyboard focus moves to eDP-1")
local move = S:dispatched("cursor.move")
stub.eq(#move, 1, "one cursor move dispatch")
stub.eq(move[1].args[1].x, 2560 + 640, "first visit lands at eDP-1's horizontal centre (logical width 1280)")
stub.eq(move[1].args[1].y, 400, "first visit lands at eDP-1's vertical centre (logical height 800)")
stub.check(S.calls.dispatch[1].dispatcher == "focus" and S.calls.dispatch[2].dispatcher == "cursor.move",
  "focus is dispatched before the cursor move")
stub.eq(S:last_config("cursor.zoom_factor"), 1, "a first visit comes up at off_zoom")
stub.eq(#S:execs("magnifier show"), 1, "the arrival zoom is shown once")
stub.eq(S:last_config("decoration.screen_shader"), SHADER, "the frozen shader is installed for the monitor left behind")

-- Work on eDP-1, zoom to 2, then jump back: DP-1 restores 3x at (100, 200).
S.cursor = { x = 3200, y = 400 }
mag.zoom_in()
S:reset_calls()
stub.eq(mag.api.jump_prev(), true, "jump_prev reports success")
mem = mag.state.memory["eDP-1"]
stub.check(mem and mem.x == 640 and mem.y == 400 and mem.zoom == 2, "leaving eDP-1 remembers its spot and zoom 2")
frozen = stub.read_file(FROZEN)
stub.contains(frozen, "1 2.0000 0.50000 0.50000\n", "eDP-1 (output 1) is frozen at 2x around its centre")
stub.eq(stub.count_lines(frozen, "^0 "), 0, "returning to DP-1 removes its frozen entry")
move = S:dispatched("cursor.move")
stub.check(move[1].args[1].x == 100 and move[1].args[1].y == 200, "the pointer returns to DP-1's remembered spot")
stub.eq(S:dispatched("focus")[1].args[1].monitor, "DP-1", "focus returns to DP-1")
stub.eq(S:last_config("cursor.zoom_factor"), 3, "DP-1's remembered zoom 3 is restored")

-- Leave DP-1 at 1x: nothing frozen there; arrive on eDP-1: its frozen entry
-- goes and the file disappears when it was the last one.
S.cursor = { x = 100, y = 200 }
mag.zoom_off()
S:reset_calls()
mag.jump.jump(1)
stub.check(not stub.exists(FROZEN), "the frozen file is removed when the last entry goes")
stub.eq(S:last_config("decoration.screen_shader"), "", "the shader slot is cleared when nothing is frozen")
stub.eq(S:last_config("cursor.zoom_factor"), 2, "eDP-1's remembered zoom 2 is restored")
stub.eq(mag.state.memory["DP-1"].zoom, 1, "DP-1 is remembered at 1x now")

-- Returning memory is clamped inside the monitor.
mag.state.memory["DP-1"] = { x = 99999, y = -40, zoom = 1 }
S.cursor = { x = 3200, y = 400 }
S:reset_calls()
mag.jump.jump(1)
move = S:dispatched("cursor.move")
stub.check(move[1].args[1].x == 2559 and move[1].args[1].y == 0, "a remembered spot outside the monitor is clamped to its edge")

-- Bound chords.
S.cursor = { x = 100, y = 200 }
S:reset_calls()
stub.check(S:press("SUPER + CTRL + mouse_down"), "SUPER + CTRL + mouse_down is bound")
stub.eq(S:dispatched("focus")[1].args[1].monitor, "eDP-1", "the jump next chord moves focus right")
S:reset_calls()
S:press("SUPER + CTRL + mouse_up")
stub.eq(S:dispatched("focus")[1].args[1].monitor, "DP-1", "the jump prev chord moves focus back")

-- leave_monitor with reset forgets the zoom (desktops.lua hook).
S.cursor = { x = 100, y = 200 }
S.values["cursor.zoom_factor"] = 4
mag.jump.leave_monitor(S.monitors[2], true)
stub.eq(mag.state.memory["DP-1"].zoom, 1, "leave_monitor(reset) remembers the off level")
stub.eq(mag.screenfx.frozen(0), nil, "leave_monitor(reset) leaves that monitor unfrozen")

-- Rotated eDP-1 (transform 1): logical size becomes 800 x 1280.
stub.remove(STATE)
stub.remove(FROZEN)
S = stub.new()
S.monitors = two_monitors({ transform = 1 })
S.cursor = { x = 100, y = 200 }
mag = S:load(nil)
S:reset_calls()
mag.jump.jump(1)
move = S:dispatched("cursor.move")
stub.eq(move[1].args[1].x, 2560 + 400, "a rotated monitor's first visit uses the swapped logical width (800)")
stub.eq(move[1].args[1].y, 640, "a rotated monitor's first visit uses the swapped logical height (1280)")
S.cursor = { x = 2560 + 400, y = 1200 } -- inside the rotated 800x1280 box
stub.eq(mag.jump.neighbour(1).name, "DP-1", "the pointer inside a rotated monitor's logical box is found there")

-- A single usable monitor: no jump, nothing dispatched.
S = stub.new()
S.monitors = { stub.monitor({ id = 0, name = "DP-1", width = 2560, height = 1440 }),
               stub.monitor({ id = 2, name = "FALLBACK", width = 0, height = 0 }) }
S.cursor = { x = 10, y = 10 }
mag = S:load(nil)
S:reset_calls()
stub.eq(mag.api.jump_next(), false, "jump_next returns false with one monitor")
stub.eq(#S.calls.dispatch, 0, "nothing is dispatched with one monitor")
stub.eq(mag.jump.neighbour(1), nil, "neighbour is nil with one monitor")
LUA
