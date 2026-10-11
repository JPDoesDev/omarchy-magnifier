#!/bin/bash
# hypr/screenfx.lua: the generated frozen-zoom shader, the shader slot
# handling, and the guard for a shader owned by something else.

source "$(dirname "${BASH_SOURCE[0]}")/base.sh"

scratch_env

run_lua_test <<'LUA'
local FROZEN = stub.FROZEN_FILE
local SHADER = stub.SHADER_FILE

local S = stub.new()
local mag = S:load(nil)
local fx = mag.screenfx
stub.check(type(fx) == "table" and type(fx.freeze) == "function", "mag.screenfx is exported")
stub.check(stub.read_file(FROZEN) == nil and stub.read_file(SHADER) == nil, "nothing is written at load with nothing frozen")
stub.check(#S:config_values("decoration.screen_shader") == 1 and S:last_config("decoration.screen_shader") == "",
  "load clears the free shader slot once (reload re-apply with nothing frozen)")

-- Freeze one output, loose (default) origin.
S:reset_calls()
stub.eq(fx.freeze(0, 3, 0.25, 0.5), true, "freeze returns true when the slot is free")
local calls = S:config_values("decoration.screen_shader")
stub.eq(#calls, 2, "apply sets the shader slot twice")
stub.eq(calls[1], "", "apply clears the slot to \"\" first")
stub.eq(calls[2], SHADER, "apply then sets the generated shader path")
stub.contains(stub.read_file(FROZEN), "0 3.0000 0.25000 0.50000\n", "the frozen file records id, zoom and the normalised centre")

local text = stub.read_file(SHADER)
stub.check(text and text:sub(1, #"#version 300 es") == "#version 300 es", "the shader starts with #version 300 es")
stub.contains(text, "uniform int wl_output;", "the shader declares uniform int wl_output")
stub.contains(text, "uniform float time;", "the shader declares uniform float time")
stub.contains(text, "uniform sampler2D tex;", "the shader declares the texture sampler")
stub.eq(stub.count_lines(text, "if %(wl_output == %d+%)"), 1, "one if (wl_output == N) block per frozen entry")
stub.contains(text, "if (wl_output == 0) { float z = 3.0000;", "the block carries the output id and zoom")
stub.contains(text, "vec2(0.25000, 0.50000) * (1.0 - 1.0 / z)", "loose zoom keeps the point under the pointer in place")
stub.lacks(text, "- 0.5 / z", "loose zoom does not use the rigid origin")
stub.contains(text, "clamp(", "the origin is clamped inside the texture")
stub.contains(text, "if (time < -1.0) color = vec4(0.0);", "the time guard line keeps the time uniform alive")
stub.contains(text, "fragColor = color;", "the shader writes fragColor")
stub.check(text:sub(-2) == "}\n", "the shader ends with the closing brace and a newline")

-- Rigid origin when cursor.zoom_rigid is on; a second output adds a second block.
S.values["cursor.zoom_rigid"] = true
S:reset_calls()
stub.eq(fx.freeze(1, 2, 0.5, 0.5), true, "a second output can be frozen")
text = stub.read_file(SHADER)
stub.eq(stub.count_lines(text, "if %(wl_output == %d+%)"), 2, "two frozen entries give two if blocks")
stub.contains(text, "if (wl_output == 0) { float z = 3.0000;", "the first entry is kept")
stub.contains(text, "if (wl_output == 1) { float z = 2.0000;", "the second entry is added")
stub.contains(text, "vec2(0.25000, 0.50000) - 0.5 / z", "rigid zoom centres the view on the pointer")
stub.lacks(text, "* (1.0 - 1.0 / z)", "rigid zoom does not use the loose origin")
local pos0, pos1 = text:find("wl_output == 0", 1, true), text:find("wl_output == 1", 1, true)
stub.check(pos0 < pos1, "blocks are emitted in output id order")
local frozen = stub.read_file(FROZEN)
stub.check(frozen:find("^0 ") and frozen:find("\n1 "), "the frozen file lists both outputs in id order")
S.values["cursor.zoom_rigid"] = false

-- Query and clamping.
local e = fx.frozen(0)
stub.check(e and e.zoom == 3 and e.cx == 0.25 and e.cy == 0.5, "frozen(id) returns the entry")
stub.eq(fx.frozen(7), nil, "frozen(unknown id) is nil")
fx.freeze(2, 4, 1.5, -0.2)
stub.contains(stub.read_file(FROZEN), "2 4.0000 1.00000 0.00000\n", "cx and cy are clamped into 0..1")

-- Unfreeze one, then all.
S:reset_calls()
fx.unfreeze(2)
stub.eq(stub.count_lines(stub.read_file(FROZEN), "^2 "), 0, "unfreeze removes that entry")
stub.eq(S:last_config("decoration.screen_shader"), SHADER, "the shader stays installed while entries remain")
S:reset_calls()
fx.unfreeze(9)
stub.eq(#S.calls.config, 0, "unfreezing an unknown id does nothing")
S:reset_calls()
fx.unfreeze_all()
stub.check(not stub.exists(FROZEN), "unfreeze_all removes the frozen file")
stub.eq(S:last_config("decoration.screen_shader"), "", "unfreeze_all clears the shader slot")
stub.eq(#S:config_values("decoration.screen_shader"), 1, "unfreeze_all touches the slot once")
stub.eq(OmarchyMagnifier.unfreeze_all, fx.unfreeze_all, "unfreeze_all is exported on OmarchyMagnifier")

-- Re-apply on load with entries on file: the frozen view survives a reload.
fx.freeze(0, 3, 0.25, 0.5)
S = stub.new()
mag = S:load(nil)
stub.eq(S:last_config("decoration.screen_shader"), SHADER, "a frozen view on file is re-applied at load")
stub.contains(stub.read_file(SHADER), "if (wl_output == 0)", "the re-applied shader still targets output 0")
mag.screenfx.unfreeze_all()

-- Foreign shader: leave it alone, warn once.
S = stub.new()
S.values["decoration.screen_shader"] = "/x/other.frag"
mag = S:load(nil)
fx = mag.screenfx
stub.eq(#S:config_values("decoration.screen_shader"), 0, "load does not touch a foreign shader slot")
S:reset_calls()
stub.eq(fx.freeze(0, 3, 0.25, 0.5), false, "freeze returns false while a foreign shader is set")
stub.eq(fx.freeze(1, 2, 0.5, 0.5), false, "freeze keeps returning false on repeated calls")
stub.eq(#S:config_values("decoration.screen_shader"), 0, "freeze does not touch the foreign shader slot")
stub.eq(S.values["decoration.screen_shader"], "/x/other.frag", "the foreign shader is still set")
stub.check(not stub.exists(FROZEN), "nothing is recorded as frozen while the slot is foreign")
local notes = S:execs("^omarchy%-notification%-send ")
stub.eq(#notes, 1, "exactly one notification across repeated freeze calls")
stub.contains(notes[1], "another screen shader", "the notification names the cause")
fx.unfreeze_all()
stub.eq(#S:config_values("decoration.screen_shader"), 0, "unfreeze_all leaves a foreign shader alone")
fx.apply()
stub.eq(#S:config_values("decoration.screen_shader"), 0, "apply leaves a foreign shader alone")

-- Once the foreign shader is gone the slot is ours again.
S.values["decoration.screen_shader"] = ""
stub.eq(fx.freeze(0, 3, 0.25, 0.5), true, "freeze works again once the slot is free")
stub.eq(S:last_config("decoration.screen_shader"), SHADER, "the plugin's shader is installed once the slot is free")
S:reset_calls()
stub.eq(fx.freeze(1, 2, 0.5, 0.5), true, "freeze recognises its own shader in the slot")
fx.unfreeze_all()

-- A frozen file left by an old session with junk lines is tolerated.
stub.write_file(FROZEN, "junk line\n0 3.0000 0.25000 0.50000\n")
S = stub.new()
local ok, err = pcall(S.load, S, nil)
stub.check(ok, "a frozen file with a junk line still loads", err)
stub.contains(stub.read_file(SHADER), "if (wl_output == 0)", "valid lines in a damaged frozen file are still applied")
stub.remove(FROZEN)
stub.remove(SHADER)

-- Colour inversion shares the shader with frozen zoom.
local INVERT = stub.INVERT_FILE
stub.remove(INVERT)
S = stub.new()
mag = S:load(nil)
fx = mag.screenfx
stub.eq(fx.inverted(), false, "colours start normal")
stub.eq(S:bind_keys("Magnifier invert colours"), "CTRL + ALT + I", "invert bound to CTRL + ALT + I by default")
stub.eq(OmarchyMagnifier.invert, fx.set_invert, "invert is exported on OmarchyMagnifier")
S:reset_calls()
stub.eq(fx.set_invert("toggle"), "inverted", "toggle from normal reports inverted")
stub.check(stub.exists(INVERT), "the invert flag file is written")
text = stub.read_file(SHADER)
stub.contains(text, "color.rgb = 1.0 - color.rgb;", "the shader inverts the colours")
stub.lacks(text, "uniform float time;", "inversion alone does not reference the time uniform")
stub.lacks(text, "wl_output ==", "inversion alone has no per-output block")
stub.eq(S:last_config("decoration.screen_shader"), SHADER, "the plugin shader is installed for inversion")
local osd = S:execs("^omarchy osd %-m ")
stub.eq(#osd, 1, "one OSD message on toggle")
stub.contains(osd[1], "Colours inverted", "the OSD says the colours are inverted")

-- Frozen view on top of inversion: both in one shader.
S:reset_calls()
stub.eq(fx.freeze(0, 3, 0.25, 0.5), true, "freezing works while inverted")
text = stub.read_file(SHADER)
stub.contains(text, "color.rgb = 1.0 - color.rgb;", "the combined shader still inverts")
stub.contains(text, "if (wl_output == 0)", "the combined shader still freezes output 0")
stub.contains(text, "uniform float time;", "the combined shader references time while a view is frozen")
local inv_pos, frag_pos = text:find("color.rgb = 1.0 - color.rgb;", 1, true), text:find("fragColor = color;", 1, true)
local tex_pos = text:find("texture(tex, uv)", 1, true)
stub.check(tex_pos < inv_pos and inv_pos < frag_pos, "inversion is applied after sampling and before output")
fx.unfreeze_all()
text = stub.read_file(SHADER)
stub.contains(text, "color.rgb = 1.0 - color.rgb;", "unfreezing keeps the inversion")
stub.eq(S:last_config("decoration.screen_shader"), SHADER, "the shader stays installed for inversion alone")

-- Reload keeps it; off removes it; status answers.
S = stub.new()
mag = S:load(nil)
fx = mag.screenfx
stub.eq(fx.inverted(), true, "inversion survives a reload (flag on file)")
stub.eq(S:last_config("decoration.screen_shader"), SHADER, "inversion is re-applied at load")
stub.eq(fx.set_invert("status"), "inverted", "status reports inverted without changing anything")
S:reset_calls()
stub.eq(fx.set_invert("on"), "inverted", "on while inverted is a no-op")
stub.eq(#S.calls.config, 0, "a no-op does not touch the shader slot")
stub.eq(#S:execs("^omarchy osd"), 0, "a no-op shows no OSD")
stub.eq(fx.set_invert("off"), "normal", "off reports normal")
stub.check(not stub.exists(INVERT), "off removes the flag file")
stub.eq(S:last_config("decoration.screen_shader"), "", "off clears the shader slot when nothing is frozen")
stub.contains(S:execs("^omarchy osd %-m ")[1], "Colours normal", "the OSD says the colours are normal")
stub.eq(S:press("CTRL + ALT + I") and fx.inverted(), true, "the chord toggles inversion on")
S:press("CTRL + ALT + I")
stub.eq(fx.inverted(), false, "the chord toggles inversion off again")

-- Foreign shader: inversion steps aside with one notification.
S = stub.new()
S.values["decoration.screen_shader"] = "/x/other.frag"
mag = S:load(nil)
fx = mag.screenfx
S:reset_calls()
stub.eq(fx.set_invert("on"), "normal", "invert is refused while a foreign shader is set")
stub.check(not stub.exists(INVERT), "no flag is written while the slot is foreign")
stub.eq(#S:config_values("decoration.screen_shader"), 0, "invert does not touch the foreign shader")
stub.eq(#S:execs("^omarchy%-notification%-send "), 1, "one notification for the refused inversion")
stub.eq(fx.freeze(0, 3, 0.25, 0.5), false, "freeze is also refused")
stub.eq(#S:execs("^omarchy%-notification%-send "), 1, "still one notification across both effects")
S.values["decoration.screen_shader"] = ""

-- Feature switched off while the flag is set: cleaned up at load.
stub.write_file(INVERT, "")
S = stub.new()
mag = S:load({ invert = false })
stub.check(not stub.exists(INVERT), "invert = false drops a stale inversion at load")
stub.eq(S:bind_keys("Magnifier invert colours"), nil, "invert = false binds no key")
stub.eq(S:last_config("decoration.screen_shader"), "", "invert = false leaves the slot clear")
stub.remove(FROZEN)
stub.remove(SHADER)
stub.remove(INVERT)
LUA
