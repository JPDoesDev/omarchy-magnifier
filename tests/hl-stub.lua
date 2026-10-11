-- Fake Hyprland `hl` for the Magnifier plugin tests.
--
-- Covers the surface the plugin uses, with the names and shapes
-- /usr/share/hypr/stubs/hl.meta.lua gives them, and records every call. Any
-- other `hl.*` field raises, so a misspelled API name fails a test instead of
-- passing silently. Nothing here touches the compositor or the real config.
--
-- From a test body (base.sh run_lua_test binds this file as `stub`):
--
--   local S = stub.new()                    -- fresh recorder; sets the global `hl`
--   S.monitors = { stub.monitor({ name = "DP-1", width = 2560, height = 1440 }) }
--   S.cursor = { x = 100, y = 200 }
--   local mag = S:load({ step = 2 })        -- dofile(hypr/init.lua) with that settings table
--   S:fire_timers({ type = "repeat" })      -- run recorded timers
--   S:fire_event("monitor.added")           -- run recorded hl.on handlers
--   stub.eq(S:last_config("cursor.zoom_factor"), 2, "description")
--
-- Recorded calls live in S.calls.<name>: config (one entry per leaf key),
-- bind, gesture, timer, on, exec_cmd, dispatch, monitor. Config values the
-- plugin reads back live in S.values["section.key"]; hl.config updates them.

local M = {}

M.ROOT = assert(os.getenv("ROOT"), "ROOT must point at the plugin directory")
M.RUNTIME = assert(os.getenv("XDG_RUNTIME_DIR"), "XDG_RUNTIME_DIR must point at a scratch directory")
M.STATE_HOME = assert(os.getenv("XDG_STATE_HOME"), "XDG_STATE_HOME must point at a scratch directory")

M.STATE_FILE = M.RUNTIME .. "/omarchy-magnifier-state"
M.FROZEN_FILE = M.RUNTIME .. "/omarchy-magnifier-frozen"
M.SHADER_FILE = M.RUNTIME .. "/omarchy-magnifier.frag"
M.UNLOCK_FILE = M.RUNTIME .. "/omarchy-magnifier-unlocked"
M.FLAG_FILE = M.STATE_HOME .. "/omarchy/toggles/hypr/magnifier-mouse-lock.lua"

-- ---- pass / fail protocol -------------------------------------------------

function M.pass(description)
  io.stdout:write("ok - ", description, "\n")
  io.stdout:flush()
end

function M.fail(description, detail)
  if detail ~= nil and detail ~= "" then io.stderr:write(tostring(detail), "\n") end
  io.stderr:write("not ok - ", description, "\n")
  os.exit(1)
end

function M.check(condition, description, detail)
  if not condition then M.fail(description, detail) end
  M.pass(description)
end

local function same(a, b)
  if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-9 end
  return a == b
end

function M.eq(actual, expected, description)
  M.check(same(actual, expected), description,
    string.format("expected: %s\nactual:   %s", tostring(expected), tostring(actual)))
end

-- Plain-text containment with a readable failure.
function M.contains(haystack, needle, description)
  local found = type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil
  M.check(found, description, string.format("expected to contain: %s\nin:\n%s", needle, tostring(haystack)))
end

function M.lacks(haystack, needle, description)
  local found = type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil
  M.check(not found, description, string.format("expected NOT to contain: %s\nin:\n%s", needle, tostring(haystack)))
end

-- ---- files ----------------------------------------------------------------

function M.read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

function M.write_file(path, content)
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:close()
end

function M.exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

function M.remove(path)
  os.remove(path)
end

-- Count of lines in `s` matching Lua pattern `pattern`.
function M.count_lines(s, pattern)
  local n = 0
  for line in (s or ""):gmatch("[^\n]+") do
    if line:find(pattern) then n = n + 1 end
  end
  return n
end

-- ---- monitors -------------------------------------------------------------

-- An HL.Monitor-shaped table with sensible defaults.
function M.monitor(fields)
  local m = {
    id = 0, name = "DP-1", description = "Test monitor", serial = "",
    x = 0, y = 0, width = 1920, height = 1080, scale = 1, transform = 0,
    refresh_rate = 60, is_mirror = false, focused = false, dpms_status = true,
    vrr_active = false,
  }
  for k, v in pairs(fields or {}) do m[k] = v end
  return m
end

local function logical(m)
  local w, h = m.width / m.scale, m.height / m.scale
  if m.transform % 2 == 1 then w, h = h, w end
  return w, h
end

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- hl.dsp.<name>(...) and hl.dsp.<ns>.<name>(...) return a descriptor
-- { dispatcher = "cursor.move", args = { ... } } that hl.dispatch records.
local function dsp_proxy(path)
  return setmetatable({}, {
    __index = function(self, key)
      local child = dsp_proxy(path and (path .. "." .. key) or key)
      rawset(self, key, child)
      return child
    end,
    __call = function(_, ...)
      return { dispatcher = path, args = { ... } }
    end,
  })
end

-- ---- the stub -------------------------------------------------------------

local Stub = {}
Stub.__index = Stub

function M.new()
  local S = setmetatable({
    calls = { config = {}, bind = {}, gesture = {}, timer = {}, on = {}, exec_cmd = {}, dispatch = {}, monitor = {} },
    values = {
      ["cursor.zoom_factor"] = 1,
      ["cursor.zoom_rigid"] = false,
      ["decoration.screen_shader"] = "",
    },
    monitors = {},
    cursor = { x = 0, y = 0 },
    monitor_at_cursor = nil, -- set to a monitor to override the geometry lookup
  }, Stub)

  local function flatten(prefix, t)
    for k, v in pairs(t) do
      local key = prefix and (prefix .. "." .. k) or k
      if type(v) == "table" then
        flatten(key, v)
      else
        S.values[key] = v
        S.calls.config[#S.calls.config + 1] = { key = key, value = v }
      end
    end
  end

  local api = {
    dsp = dsp_proxy(nil),

    config = function(t)
      assert(type(t) == "table", "hl.config expects a table")
      flatten(nil, t)
    end,

    -- One value for a known key; nil plus a message for an unknown one,
    -- which is what Hyprland 0.56.2 does.
    get_config = function(key)
      local v = S.values[key]
      if v == nil then return nil, "unknown config key '" .. tostring(key) .. "'" end
      return v
    end,

    bind = function(keys, dispatcher, opts)
      assert(type(keys) == "string", "hl.bind expects a key string")
      S.calls.bind[#S.calls.bind + 1] = {
        keys = keys,
        dispatcher = dispatcher,
        opts = opts or {},
        description = opts and (opts.description or opts.desc) or nil,
      }
      return {}
    end,

    unbind = function() end,

    gesture = function(spec)
      assert(type(spec) == "table", "hl.gesture expects a table")
      S.calls.gesture[#S.calls.gesture + 1] = copy(spec)
    end,

    exec_cmd = function(cmd)
      assert(type(cmd) == "string", "hl.exec_cmd expects a string")
      S.calls.exec_cmd[#S.calls.exec_cmd + 1] = cmd
    end,

    -- Records the dispatcher; a cursor.move also moves the fake pointer, as
    -- the compositor would, so a following get_cursor_pos sees it.
    dispatch = function(d)
      S.calls.dispatch[#S.calls.dispatch + 1] = d
      if type(d) == "table" and d.dispatcher == "cursor.move" then
        local a = d.args[1]
        if type(a) == "table" and type(a.x) == "number" and type(a.y) == "number" then
          S.cursor = { x = a.x, y = a.y }
        end
      end
    end,

    monitor = function(spec)
      assert(type(spec) == "table" and type(spec.output) == "string", "hl.monitor expects { output = ... }")
      S.calls.monitor[#S.calls.monitor + 1] = copy(spec)
    end,

    timer = function(fn, opts)
      assert(type(fn) == "function", "hl.timer expects a function")
      assert(type(opts) == "table" and opts.timeout and (opts.type == "repeat" or opts.type == "oneshot"),
        "hl.timer expects { timeout = ms, type = 'repeat'|'oneshot' }")
      local t = { fn = fn, timeout = opts.timeout, type = opts.type, fired = 0, enabled = true }
      S.calls.timer[#S.calls.timer + 1] = t
      return {
        set_enabled = function(_, on) t.enabled = on and true or false end,
        is_enabled = function() return t.enabled end,
        set_timeout = function(_, ms) t.timeout = ms end,
      }
    end,

    on = function(event, cb)
      assert(type(event) == "string" and type(cb) == "function", "hl.on expects (event, function)")
      S.calls.on[#S.calls.on + 1] = { event = event, cb = cb }
      return { unsubscribe = function() end }
    end,

    get_monitors = function()
      local out = {}
      for i, m in ipairs(S.monitors) do out[i] = m end
      return out
    end,

    get_monitor = function(selector)
      for _, m in ipairs(S.monitors) do
        if m == selector or m.name == selector or m.id == selector then return m end
      end
      return nil
    end,

    get_cursor_pos = function()
      return { x = S.cursor.x, y = S.cursor.y }
    end,

    get_monitor_at_cursor = function()
      if S.monitor_at_cursor then return S.monitor_at_cursor end
      return S:monitor_at(S.cursor.x, S.cursor.y)
    end,

    get_monitor_at = function(x, y)
      if type(x) == "table" then x, y = x.x, x.y end
      return S:monitor_at(x, y)
    end,

    version = function() return "0.56.2" end,
  }

  S.hl = setmetatable(api, {
    __index = function(_, key)
      error("hl." .. tostring(key) .. " is not part of the stubbed Hyprland API (check /usr/share/hypr/stubs/hl.meta.lua)", 2)
    end,
  })
  _G.hl = S.hl
  return S
end

function Stub:monitor_at(x, y)
  for _, m in ipairs(self.monitors) do
    if not m.is_mirror and m.width > 0 then
      local w, h = logical(m)
      if x >= m.x and x < m.x + w and y >= m.y and y < m.y + h then return m end
    end
  end
  return nil
end

-- Load the plugin the way hyprland.lua does, with `settings` as omarchy_magnifier.
function Stub:load(settings)
  _G.omarchy_magnifier = settings
  _G.OmarchyMagnifier = nil
  return dofile(M.ROOT .. "/hypr/init.lua")
end

-- Forget recorded actions (config, exec_cmd, dispatch, monitor); keeps the
-- registrations (bind, gesture, timer, on) and all values.
function Stub:reset_calls()
  self.calls.config = {}
  self.calls.exec_cmd = {}
  self.calls.dispatch = {}
  self.calls.monitor = {}
end

function Stub:config_values(key)
  local out = {}
  for _, c in ipairs(self.calls.config) do
    if c.key == key then out[#out + 1] = c.value end
  end
  return out
end

function Stub:last_config(key)
  local vs = self:config_values(key)
  return vs[#vs]
end

function Stub:binds_for(description)
  local out = {}
  for _, b in ipairs(self.calls.bind) do
    if b.description == description then out[#out + 1] = b end
  end
  return out
end

function Stub:bind_keys(description)
  local b = self:binds_for(description)[1]
  return b and b.keys or nil
end

-- Press a bound chord: runs its function dispatcher.
function Stub:press(keys)
  for _, b in ipairs(self.calls.bind) do
    if b.keys == keys and type(b.dispatcher) == "function" then b.dispatcher() return true end
  end
  return false
end

-- exec_cmd calls whose command matches Lua pattern `pattern` (all when nil).
function Stub:execs(pattern)
  local out = {}
  for _, cmd in ipairs(self.calls.exec_cmd) do
    if pattern == nil or cmd:find(pattern) then out[#out + 1] = cmd end
  end
  return out
end

function Stub:dispatched(name)
  local out = {}
  for _, d in ipairs(self.calls.dispatch) do
    if type(d) == "table" and (name == nil or d.dispatcher == name) then out[#out + 1] = d end
  end
  return out
end

-- Timers matching filter { type = ..., timeout = ... } (all when nil).
function Stub:timers(filter)
  local out = {}
  for _, t in ipairs(self.calls.timer) do
    if (not filter) or ((filter.type == nil or t.type == filter.type) and (filter.timeout == nil or t.timeout == filter.timeout)) then
      out[#out + 1] = t
    end
  end
  return out
end

-- Run the matching enabled timers once, in registration order; a oneshot
-- fires only the first time. Timers registered while firing are not run.
function Stub:fire_timers(filter)
  local fired = 0
  for _, t in ipairs(self:timers(filter)) do
    if t.enabled and (t.type == "repeat" or t.fired == 0) then
      t.fired = t.fired + 1
      fired = fired + 1
      t.fn()
    end
  end
  return fired
end

function Stub:handlers(event)
  local out = {}
  for _, h in ipairs(self.calls.on) do
    if h.event == event then out[#out + 1] = h.cb end
  end
  return out
end

function Stub:fire_event(event, ...)
  local hs = self:handlers(event)
  for _, cb in ipairs(hs) do cb(...) end
  return #hs
end

-- Hyprland reaps its own children, so inside the compositor os.execute()
-- cannot read an exit status: it returns nil, "No child processes", 10 for
-- every command (checked on 0.56.2 with hyprctl eval). Install that
-- behaviour so a test sees what the plugin sees in production. The command
-- still runs.
function M.emulate_child_reaping()
  os.execute = function(cmd)
    if cmd == nil then return true end
    local p = io.popen(cmd)
    if p then p:read("a") p:close() end
    return nil, "No child processes", 10
  end
end

return M
