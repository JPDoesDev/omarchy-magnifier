-- Mouse lock: keep the pointer on one monitor so the magnifier cannot drift
-- onto the other one unnoticed.
--
-- Hyprland clamps pointer motion to the nearest monitor edge, so placing the
-- monitors far apart in the virtual layout (a gap wider than any mouse delta)
-- pins the pointer to whichever monitor it is on. SUPER + CTRL + scroll
-- (jump.lua) is then the only way across, and SUPER + CTRL + M unlocks for
-- dragging a window over. Unlock lasts until the next plug/unplug or reboot.
--
-- The gapped layout is written as hl.monitor rules into Omarchy's Hyprland
-- toggle directory, which is loaded on every config reload after the user's
-- monitors.lua. Each rule keeps the monitor's current mode, scale and rotation,
-- so the only thing that changes is the position. With one usable monitor, or
-- while unlocked, the rule file is removed and monitors.lua applies as usual.
return function(mag)
  local cfg = mag.settings
  local TOGGLES_DIR = mag.state_home .. "/omarchy/toggles/hypr"
  local FLAG_FILE = TOGGLES_DIR .. "/magnifier-mouse-lock.lua"
  local UNLOCK_FILE = mag.runtime .. "/omarchy-magnifier-unlocked" -- exists -> pointer free to cross
  local RETRIES_FILE = mag.runtime .. "/omarchy-magnifier-lock-retries"
  local LAYOUT_MAX = 30000 -- stays under Xwayland's 32767 coordinate limit
  local MAX_RETRIES = 3 -- reloads allowed before giving up on a layout Hyprland won't take

  local function locked()
    return not mag.file_exists(UNLOCK_FILE)
  end

  local function safe_name(name)
    return type(name) == "string" and name:match("^[%w._-]+$") ~= nil
  end

  -- Usable monitors left to right: name, logical width, y, scale, mode, transform.
  local function usable_monitors()
    local list = {}
    for _, m in ipairs(hl.get_monitors()) do
      if not m.is_mirror and m.width > 0 and m.height > 0 and m.name ~= "FALLBACK" and safe_name(m.name) then
        local lw = m.width / m.scale
        if m.transform % 2 == 1 then lw = m.height / m.scale end
        list[#list + 1] = {
          name = m.name,
          width = math.floor(lw),
          x = m.x,
          y = m.y,
          -- %.4g so a scale Hyprland has rounded (1.5 vs 1.500001) does not
          -- rewrite the rule file on every sync.
          scale = string.format("%.4g", m.scale),
          mode = string.format("%dx%d@%.3f", m.width, m.height, m.refresh_rate),
          transform = m.transform,
        }
      end
    end
    table.sort(list, function(a, b)
      if a.x == b.x then return a.y < b.y end
      return a.x < b.x
    end)
    return list
  end

  -- The rule lines for the locked layout, or nil when no lock applies.
  local function lock_rules(mons)
    if not locked() or #mons < 2 then return nil end
    local sum = 0
    for _, m in ipairs(mons) do sum = sum + m.width end
    local gap = math.floor((LAYOUT_MAX - sum) / (#mons - 1))
    gap = math.min(gap, math.floor(cfg.lock_gap))
    gap = math.max(gap, 2000)

    local lines = { "-- Written by the Omarchy Magnifier plugin (mouse lock). Do not edit." }
    local x = 0
    local positions = {}
    for _, m in ipairs(mons) do
      local extra = ""
      if m.transform ~= 0 then extra = string.format(", transform = %d", m.transform) end
      lines[#lines + 1] = string.format(
        'hl.monitor({ output = "%s", mode = "%s", position = "%dx%d", scale = %s%s })',
        m.name, m.mode, x, m.y, m.scale, extra)
      positions[m.name] = x
      x = x + m.width + gap
    end
    return table.concat(lines, "\n") .. "\n", positions
  end

  local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
  end

  -- Writes `content` unless identical; returns true when it changed.
  local function write_flag(content)
    if read_file(FLAG_FILE) == content then return false end
    os.execute("mkdir -p " .. mag.shell_quote(TOGGLES_DIR))
    local f = io.open(FLAG_FILE, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
  end

  local function drop_flag()
    if not mag.file_exists(FLAG_FILE) then return false end
    os.remove(FLAG_FILE)
    return true
  end

  local function reload_paused()
    -- Don't reload Hyprland into a half-replaced config mid-update. Hyprland
    -- reaps its own children, so os.execute cannot see an exit status here;
    -- the status is read back through a pipe instead.
    local pipe = io.popen("omarchy-hyprland-reload-guard paused >/dev/null 2>&1 && echo OK")
    if not pipe then return false end
    local out = pipe:read("a") or ""
    pipe:close()
    return out:find("OK", 1, true) ~= nil
  end

  local function reload()
    hl.exec_cmd("hyprctl reload")
  end

  -- Every config load re-checks the layout, including the loads this module
  -- triggers. If Hyprland will not honour a rule the loop would never end, so
  -- the reloads a single mismatch may cause are counted; a layout that matches,
  -- a hotplug or a lock keypress starts the count over.
  local function reset_retries()
    os.remove(RETRIES_FILE)
  end

  local function reload_budgeted()
    local n = tonumber(read_file(RETRIES_FILE)) or 0
    if n >= MAX_RETRIES then return end
    local f = io.open(RETRIES_FILE, "w")
    if f then
      f:write(tostring(n + 1))
      f:close()
    end
    reload()
  end

  -- Bring the layout in line with the lock state. Reloads only when the rule
  -- file changed, or when a rule is on file but not in effect (Omarchy's scale
  -- pills apply a live rule with position = "auto", which un-gaps the layout).
  local function sync()
    if reload_paused() then return end
    local mons = usable_monitors()
    local desired, positions = lock_rules(mons)
    if not desired then
      reset_retries()
      if drop_flag() then reload() end
      return
    end
    if write_flag(desired) then
      reload_budgeted()
      return
    end
    for _, m in ipairs(mons) do
      if positions[m.name] ~= m.x then
        reload_budgeted()
        return
      end
    end
    reset_retries()
  end

  -- Hyprland takes a moment to settle after a hotplug, so retry a few times.
  local function sync_after_change()
    for _, delay in ipairs({ 50, 1000, 3000, 7000 }) do
      hl.timer(sync, { timeout = delay, type = "oneshot" })
    end
  end

  local function set_lock(action)
    action = action or "toggle"
    if action == "status" then return locked() and "locked" or "unlocked" end
    if action == "on" then
      os.remove(UNLOCK_FILE)
    elseif action == "off" then
      local f = io.open(UNLOCK_FILE, "w")
      if f then f:close() end
    else -- toggle
      if locked() then
        local f = io.open(UNLOCK_FILE, "w")
        if f then f:close() end
      else
        os.remove(UNLOCK_FILE)
      end
    end

    if #usable_monitors() < 2 then
      mag.notify("Mouse lock needs two or more monitors")
      return locked() and "locked" or "unlocked"
    end
    reset_retries()
    sync()
    if locked() then
      mag.notify("Mouse locked to one monitor (" .. tostring(cfg.keys.jump_next or "jump") .. " hops)")
    else
      mag.notify("Mouse unlocked: free to cross monitors")
    end
    return locked() and "locked" or "unlocked"
  end

  mag.lock = { sync = sync, set = set_lock, locked = locked }
  mag.api.lock = set_lock
  mag.api.lock_sync = sync

  if not cfg.mouse_lock then
    -- Feature switched off: make sure no stale rule file keeps the gap.
    if drop_flag() then reload() end
    return
  end

  mag.bind(cfg.keys.lock_toggle, "Magnifier mouse lock toggle", function() set_lock("toggle") end)

  local function monitors_changed()
    -- Plugging re-locks, and output ids may have changed, so frozen views go.
    os.remove(UNLOCK_FILE)
    reset_retries()
    mag.screenfx.unfreeze_all()
    sync_after_change()
  end
  hl.on("monitor.added", monitors_changed)
  hl.on("monitor.removed", monitors_changed)

  -- After every config load (including the one a sync triggers) check that the
  -- layout matches; a sync that finds nothing to change does not reload.
  sync_after_change()
end
