-- Zoom control: steps, presets, clamping, the popup, pinch, and keeping the
-- zoom level across config reloads.
--
-- Hyprland's whole-screen zoom is `cursor:zoom_factor`. A config reload resets
-- it to 1 and wipes this Lua state, and reloads come from many places (theme
-- changes, Omarchy's monitor watcher, toggles), so the current zoom and the
-- per-monitor memory are mirrored to a file in $XDG_RUNTIME_DIR and put back
-- when the config loads. The file is gone after a reboot.
return function(mag)
  local cfg = mag.settings
  local STATE_FILE = mag.runtime .. "/omarchy-magnifier-state"
  local saved_zoom

  function mag.current_zoom()
    return tonumber(hl.get_config("cursor.zoom_factor")) or 1
  end

  function mag.clamp(zoom)
    return math.max(cfg.min_zoom, math.min(tonumber(zoom) or 1, cfg.max_zoom))
  end

  function mag.save_state()
    local zoom = mag.current_zoom()
    local f = io.open(STATE_FILE, "w")
    if not f then return end
    f:write(string.format("zoom %.4f\n", zoom))
    for name, m in pairs(mag.state.memory) do
      f:write(string.format("mem %s %.2f %.2f %.4f\n", name, m.x, m.y, m.zoom))
    end
    f:close()
    saved_zoom = zoom
  end

  local function load_state()
    local f = io.open(STATE_FILE, "r")
    if not f then return end
    for line in f:lines() do
      local z = line:match("^zoom ([%d.]+)$")
      if z then saved_zoom = tonumber(z) end
      local name, x, y, mz = line:match("^mem (%S+) ([%d.-]+) ([%d.-]+) ([%d.]+)$")
      if name then
        mag.state.memory[name] = { x = tonumber(x), y = tonumber(y), zoom = tonumber(mz) }
      end
    end
    f:close()
  end

  -- The popup is a shell plugin; it gets the zoom and the style in one JSON
  -- payload so it never has to read a settings file itself.
  function mag.show_osd(zoom)
    if not cfg.osd then return end
    local s = cfg.osd_style
    local payload = mag.json({
      zoom = zoom,
      style = {
        fontSize = s.font_size,
        durationMs = s.duration_ms,
        borderWidth = s.border_width,
        padding = s.padding,
        minScale = s.min_scale,
        pointerGap = s.pointer_gap,
        pointerDrop = s.pointer_drop,
        background = s.background,
        text = s.text,
        border = s.border,
      },
    })
    hl.exec_cmd("omarchy-shell -q " .. mag.ipc_target .. " show " .. mag.shell_quote(payload))
  end

  -- opts.silent skips the popup (used when restoring after a reload).
  function mag.set_zoom(zoom, opts)
    zoom = mag.clamp(zoom)
    hl.config({ cursor = { zoom_factor = zoom } })
    mag.save_state()
    if not (opts and opts.silent) then mag.show_osd(zoom) end
    return zoom
  end

  function mag.zoom_in() return mag.set_zoom(mag.current_zoom() + cfg.step) end
  function mag.zoom_out() return mag.set_zoom(mag.current_zoom() - cfg.step) end
  function mag.zoom_preset() return mag.set_zoom(cfg.preset_zoom) end
  function mag.zoom_off() return mag.set_zoom(cfg.off_zoom) end
  function mag.zoom_toggle()
    if mag.current_zoom() > cfg.off_zoom + 0.001 then return mag.zoom_off() end
    return mag.zoom_preset()
  end

  mag.api.zoom_in = mag.zoom_in
  mag.api.zoom_out = mag.zoom_out
  mag.api.zoom_preset = mag.zoom_preset
  mag.api.zoom_off = mag.zoom_off
  mag.api.zoom_toggle = mag.zoom_toggle
  mag.api.zoom_set = function(z) return mag.set_zoom(z) end

  mag.bind(cfg.keys.zoom_in, "Magnifier zoom in", mag.zoom_in)
  mag.bind(cfg.keys.zoom_out, "Magnifier zoom out", mag.zoom_out)
  mag.bind(cfg.keys.zoom_in_key, "Magnifier zoom in (key)", mag.zoom_in)
  mag.bind(cfg.keys.zoom_out_key, "Magnifier zoom out (key)", mag.zoom_out)
  mag.bind(cfg.keys.preset, "Magnifier zoom to preset", mag.zoom_preset)
  mag.bind(cfg.keys.off, "Magnifier zoom off", mag.zoom_off)
  if cfg.side_buttons then
    mag.bind("SUPER + mouse:" .. math.floor(cfg.side_button_in), "Magnifier zoom to preset (side button)", mag.zoom_preset)
    mag.bind("SUPER + mouse:" .. math.floor(cfg.side_button_out), "Magnifier zoom off (side button)", mag.zoom_off)
  end

  -- Hold SUPER and pinch on the touchpad. mode = "live" makes Hyprland follow
  -- the pinch continuously, anchored where the pointer was when it began;
  -- without it the gesture is a toggle to zoom_level, so a finished pinch
  -- snapped any magnified screen straight back to 100%. Hyprland's gesture
  -- ignores our limits and shows no popup; the timer below catches up with both.
  if cfg.pinch then
    hl.gesture({
      fingers = math.floor(cfg.pinch_fingers),
      direction = "pinch",
      mods = "SUPER",
      action = "cursor_zoom",
      mode = "live",
      zoom_level = cfg.pinch_zoom_level, -- unused by Hyprland in live mode; kept as the documented placeholder
    })
  end

  -- Restore the zoom from before the reload.
  load_state()
  if saved_zoom and saved_zoom > 1.001 then
    hl.config({ cursor = { zoom_factor = mag.clamp(saved_zoom) } })
  end

  -- Zoom changed behind our back (pinch, Omarchy's own SUPER + CTRL + Z, a
  -- script): keep the saved copy current and the limits honoured. Nothing is
  -- written while the value is unchanged.
  hl.timer(function()
    local zoom = mag.current_zoom()
    if zoom == saved_zoom then return end
    local clamped = mag.clamp(zoom)
    if math.abs(clamped - zoom) > 0.001 then
      hl.config({ cursor = { zoom_factor = clamped } })
    end
    mag.save_state()
  end, { timeout = 500, type = "repeat" })
end
