-- Omarchy Magnifier: Hyprland side.
--
-- Load it from ~/.config/hypr/hyprland.lua, after Omarchy's defaults, with an
-- optional settings table in front of it:
--
--   omarchy_magnifier = { preset_zoom = 3, step = 1 }
--   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/jpdoesdev.magnifier/hypr/init.lua")
--
-- `dofile` (not `require`) because the plugin id contains a dot, which Lua's
-- module path would turn into a directory separator. dofile is also never
-- cached, so every `hyprctl reload` re-evaluates the plugin like the rest of
-- the config.
--
-- Every key below can be set in `omarchy_magnifier`; anything missing or of the
-- wrong type falls back to the default, so a typo can never disable zoom.

local source = debug.getinfo(1, "S").source
local dir = source:match("^@(.*)/[^/]*$") or "."

local DEFAULTS = {
  -- Zoom levels are multipliers: 1 = off, 3 = 300%.
  preset_zoom = 3, -- zoom reached by the preset key / front side button
  off_zoom = 1, -- zoom reached by the off key / back side button
  step = 1, -- change per scroll notch
  min_zoom = 1,
  max_zoom = 10, -- Hyprland's own ceiling for cursor:zoom_factor

  osd = true, -- show the zoom percentage beside the pointer on every change

  pinch = true, -- SUPER + pinch on the touchpad zooms continuously
  pinch_fingers = 2,
  pinch_zoom_level = 1.0, -- Hyprland's zoom_level for the cursor_zoom gesture (unused in live mode; placeholder)

  side_buttons = false, -- SUPER + mouse side buttons jump to preset / off
  side_button_in = 276, -- front button on most mice; find yours with `wev`
  side_button_out = 275,

  invert = true, -- CTRL + ALT + I inverts the colours of every screen (off after a reboot)

  jump = true, -- SUPER + CTRL + scroll hops between monitors with per-monitor memory
  mouse_lock = true, -- keep the pointer on one monitor until a jump (2+ monitors)
  lock_gap = 20000, -- logical pixels between monitors while locked

  lock_screen_reset = true, -- the lock screen always comes up at 100%, with no frozen view
  restore_after_unlock = true, -- after the unlock, put the zoom and the frozen views back

  -- Deliver every wheel notch to the binds (sets Hyprland's binds:scroll_event_delay
  -- to 0 while a wheel chord is bound). With the default 300 ms delay, a notch that
  -- follows another one quickly skips the binds and reaches the focused window with
  -- CTRL still held, so a fast CTRL + ALT + scroll also zooms a browser page.
  wheel_every_notch = true,

  -- Set any key to false to leave it unbound.
  keys = {
    zoom_in = "CTRL + ALT + mouse_up",
    zoom_out = "CTRL + ALT + mouse_down",
    zoom_in_key = "CTRL + ALT + equal", -- keyboard-only step: Ctrl + Alt + =
    zoom_out_key = "CTRL + ALT + minus", -- keyboard-only step: Ctrl + Alt + -
    preset = "CTRL + ALT + Z",
    off = "CTRL + ALT + X",
    invert = "CTRL + ALT + I",
    jump_next = "SUPER + CTRL + mouse_down",
    jump_prev = "SUPER + CTRL + mouse_up",
    lock_toggle = "SUPER + CTRL + M",
  },

  -- Popup look. Colours default to the active Omarchy theme; set background /
  -- text / border to "#rrggbb" to force them (e.g. a high-contrast set).
  osd_style = {
    font_size = 48,
    duration_ms = 1200,
    border_width = 4,
    padding = 15,
    min_scale = 2, -- smallest on-screen size as a multiple of normal; below 2 looks blurry
    pointer_gap = 104, -- horizontal distance from the pointer, on-screen pixels
    pointer_drop = 28, -- vertical offset from the pointer, on-screen pixels
    background = false,
    text = false,
    border = false,
  },
}

local function is_color(v)
  return type(v) == "string" and v:match("^#%x%x%x%x%x%x$") ~= nil
end

-- Settings whose default is false but which take a string when set.
local OPTIONAL_STRING = { background = true, text = true, border = true }

-- Deep-merge `user` over `defaults`, keeping a value only when its type matches
-- the default (numbers may arrive as numeric strings; colours and keys may be
-- false to disable).
local function merge(defaults, user)
  local out = {}
  for k, d in pairs(defaults) do
    local u = nil
    if type(user) == "table" then u = user[k] end
    if type(d) == "table" then
      out[k] = merge(d, u)
    elseif type(d) == "number" then
      local n = tonumber(u)
      out[k] = n or d
    elseif type(d) == "string" or (d == false and OPTIONAL_STRING[k]) then
      -- keys.* and osd_style colours: a string, or false to disable/unset
      if u == false then out[k] = false
      elseif type(u) == "string" and u ~= "" then out[k] = u
      else out[k] = d end
    elseif type(d) == "boolean" then
      if type(u) == "boolean" then out[k] = u else out[k] = d end
    else
      out[k] = d
    end
  end
  return out
end

local cfg = merge(DEFAULTS, _G.omarchy_magnifier)
-- Keep the limits sane whatever was typed.
cfg.min_zoom = math.max(1, cfg.min_zoom)
cfg.max_zoom = math.max(cfg.min_zoom, math.min(10, cfg.max_zoom))
cfg.step = math.max(0.1, cfg.step)
cfg.off_zoom = math.max(cfg.min_zoom, math.min(cfg.off_zoom, cfg.max_zoom))
cfg.preset_zoom = math.max(cfg.min_zoom, math.min(cfg.preset_zoom, cfg.max_zoom))
for _, k in ipairs({ "background", "text", "border" }) do
  if cfg.osd_style[k] and not is_color(cfg.osd_style[k]) then cfg.osd_style[k] = false end
end

local mag = {
  dir = dir,
  plugin_id = "jpdoesdev.magnifier",
  ipc_target = "magnifier",
  settings = cfg,
  runtime = os.getenv("XDG_RUNTIME_DIR") or "/tmp",
  state_home = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state"),
  state = { memory = {} }, -- filled by magnifier.lua (zoom) and jump.lua (per-monitor memory)
}

function mag.shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- Minimal JSON for the OSD payload: flat values, nested tables, no arrays needed.
function mag.json(value)
  local t = type(value)
  if t == "table" then
    local parts = {}
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local v = value[k]
      if v ~= nil and v ~= false then
        parts[#parts + 1] = string.format("%q:%s", tostring(k), mag.json(v))
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "number" then
    if value == math.floor(value) then return string.format("%d", value) end
    return string.format("%.4f", value)
  elseif t == "boolean" then
    return value and "true" or "false"
  else
    return string.format("%q", tostring(value))
  end
end

function mag.file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

-- True while the session lock is up and the magnifier stands aside for it
-- (screenlock.lua writes and removes the flag). Defined here because screenfx
-- and magnifier, which load first, both ask.
mag.SCREEN_LOCK_FLAG = mag.runtime .. "/omarchy-magnifier-screen-locked"
function mag.screen_locked()
  return mag.file_exists(mag.SCREEN_LOCK_FLAG)
end

function mag.notify(message)
  hl.exec_cmd("omarchy-notification-send " .. mag.shell_quote(message))
end

-- Bind through Omarchy's helper when it is loaded (so the key shows in the
-- SUPER + K menu with its description), else straight through Hyprland.
-- `options` are Hyprland's bind options; the table is copied because Omarchy's
-- helper writes the description into it.
function mag.bind(keys, description, fn, options)
  if not keys then return end
  local opts = {}
  for k, v in pairs(options or {}) do opts[k] = v end
  if type(o) == "table" and o.bind then
    o.bind(keys, description, fn, opts)
  else
    opts.description = description
    hl.bind(keys, fn, opts)
  end
end

-- Hyprland drops every bind without `locked` while a session lock is up. The
-- keys that take magnification away (zoom out, zoom off) and colour inversion
-- carry it, so a lock screen that came up magnified can be put right without
-- typing the password blind. The keys that zoom in do not: nothing should
-- magnify the lock screen further.
mag.AT_LOCK_SCREEN = { locked = true }

-- Public API for scripts and the CLI: hyprctl eval 'OmarchyMagnifier.zoom_in()'
OmarchyMagnifier = {}
mag.api = OmarchyMagnifier

for _, name in ipairs({ "screenfx", "magnifier", "jump", "lock", "screenlock" }) do
  local chunk, err = loadfile(dir .. "/" .. name .. ".lua")
  local ok = false
  if chunk then
    ok, err = pcall(function() chunk()(mag) end)
  end
  if not ok then
    -- One broken module must not take the rest of hyprland.lua down with it.
    mag.notify("Magnifier plugin: " .. name .. ".lua failed to load: " .. tostring(err))
  end
end

-- Hyprland throttles wheel binds: a notch arriving within binds:scroll_event_delay
-- of the previous one is not matched against any bind and is passed to the
-- focused window with the modifiers still held (CKeybindManager::onAxisEvent,
-- 0.56.2). A browser then sees CTRL + wheel and zooms the page. Delivering every
-- notch to the binds stops that; it also makes Omarchy's own SUPER + scroll
-- binds fire on every notch instead of at most every 300 ms.
local function uses_wheel(chord)
  return type(chord) == "string" and (chord:find("mouse_up", 1, true) or chord:find("mouse_down", 1, true)) ~= nil
end
if cfg.wheel_every_notch and (uses_wheel(cfg.keys.zoom_in) or uses_wheel(cfg.keys.zoom_out)
    or (cfg.jump and (uses_wheel(cfg.keys.jump_next) or uses_wheel(cfg.keys.jump_prev)))) then
  hl.config({ binds = { scroll_event_delay = 0 } })
end

return mag
