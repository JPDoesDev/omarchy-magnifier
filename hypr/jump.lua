-- Monitor jump: each monitor keeps its own pointer position and zoom level.
--
-- SUPER + CTRL + scroll moves pointer and keyboard focus to the next or
-- previous monitor (left to right, wrapping). The pointer lands where it last
-- was on that monitor (its centre on a first visit) and that monitor's own zoom
-- level comes back. The monitor you leave keeps its magnified view through
-- screenfx.lua. Memory is saved with the zoom state so it survives a reload.
return function(mag)
  local cfg = mag.settings
  local screenfx = mag.screenfx
  local memory = mag.state.memory

  local function logical_size(m)
    local w, h = m.width / m.scale, m.height / m.scale
    if m.transform % 2 == 1 then w, h = h, w end
    return w, h
  end

  -- Usable monitors, left to right then top to bottom.
  local function candidates()
    local list = {}
    for _, m in ipairs(hl.get_monitors()) do
      if not m.is_mirror and m.width > 0 and m.name ~= "FALLBACK" then list[#list + 1] = m end
    end
    table.sort(list, function(a, b)
      if a.x == b.x then return a.y < b.y end
      return a.x < b.x
    end)
    return list
  end

  -- Remember where the pointer is on the monitor being left and freeze its
  -- view. reset = true forgets it instead, so it comes back at the off level.
  local function leave_monitor(cur, reset)
    local pos = hl.get_cursor_pos()
    if not cur or not pos then return end
    local cw, ch = logical_size(cur)
    local rx, ry = pos.x - cur.x, pos.y - cur.y
    if reset then
      memory[cur.name] = { x = rx, y = ry, zoom = cfg.off_zoom }
      mag.save_state()
      screenfx.unfreeze(cur.id)
      return
    end
    local zoom_here = mag.current_zoom()
    memory[cur.name] = { x = rx, y = ry, zoom = zoom_here }
    mag.save_state()
    if zoom_here > 1.001 then
      screenfx.freeze(cur.id, zoom_here, rx / cw, ry / ch)
    else
      screenfx.unfreeze(cur.id)
    end
  end

  -- Put pointer and keyboard focus on `target` at its remembered spot and
  -- restore its zoom, or use `zoom` when given.
  local function enter_monitor(target, zoom)
    local lw, lh = logical_size(target)
    local mem = memory[target.name] or { x = lw / 2, y = lh / 2, zoom = cfg.off_zoom }
    local x = target.x + math.max(0, math.min(mem.x, lw - 1))
    local y = target.y + math.max(0, math.min(mem.y, lh - 1))

    screenfx.unfreeze(target.id) -- Hyprland's own zoom takes over there
    hl.dispatch(hl.dsp.focus({ monitor = target.name }))
    hl.dispatch(hl.dsp.cursor.move({ x = x, y = y }))
    mag.set_zoom(zoom or mem.zoom)
  end

  -- Monitor `direction` steps away from the one under the pointer (wraps).
  local function neighbour(direction)
    local mons = candidates()
    if #mons < 2 then return nil end
    local cur = hl.get_monitor_at_cursor()
    local idx = 1
    for i, m in ipairs(mons) do
      if cur and m.name == cur.name then idx = i end
    end
    return mons[((idx - 1 + direction) % #mons) + 1], cur
  end

  local function jump(direction)
    local target, cur = neighbour(direction)
    if not target then return false end
    leave_monitor(cur)
    enter_monitor(target)
    return true
  end

  mag.jump = {
    monitors = candidates,
    neighbour = neighbour,
    leave_monitor = leave_monitor,
    enter_monitor = enter_monitor,
    jump = jump,
  }
  mag.api.jump = jump
  mag.api.jump_next = function() return jump(1) end
  mag.api.jump_prev = function() return jump(-1) end
  -- Building blocks for other Lua modules (e.g. a per-monitor desktop mover
  -- that wants to carry pointer, focus and zoom across with it).
  mag.api.monitors = candidates
  mag.api.neighbour = neighbour
  mag.api.leave_monitor = leave_monitor
  mag.api.enter_monitor = enter_monitor

  if cfg.jump then
    mag.bind(cfg.keys.jump_next, "Magnifier jump to next monitor", function() jump(1) end)
    mag.bind(cfg.keys.jump_prev, "Magnifier jump to previous monitor", function() jump(-1) end)
  end
end
