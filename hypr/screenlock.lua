-- Lock screen: the session lock comes up at 100% and the magnifier comes back
-- after the unlock.
--
-- cursor:zoom_factor is compositor-wide and the screen shader covers the whole
-- output, so the lock screen is magnified (and shows frozen views) like any
-- other surface. Hyprland 0.56.2 has no Lua event for a session lock and
-- Omarchy has no lock hook, so the signal comes from the shell side of the
-- plugin: ZoomOsd.qml watches Hyprland for the lock and calls
-- OmarchyMagnifier.screen_lock(true | false) through `hyprctl eval`.
--
-- The flag file ($XDG_RUNTIME_DIR/omarchy-magnifier-screen-locked) holds the
-- zoom from before the lock. While it exists the zoom is not restored after a
-- config reload, the 500 ms catch-up timer stands still, and frozen views are
-- left out of the screen shader (see mag.screen_locked in init.lua). Colour
-- inversion stays: it is how the user reads the screen, lock screen included.
return function(mag)
  local cfg = mag.settings
  local FLAG = mag.SCREEN_LOCK_FLAG

  local function read_flag()
    local f = io.open(FLAG, "r")
    if not f then return nil end
    local zoom = tonumber(f:read("*l") or "")
    f:close()
    return zoom or 1
  end

  local function lock()
    if mag.screen_locked() then return end
    local zoom = mag.current_zoom()
    local f = io.open(FLAG, "w")
    if not f then return end
    f:write(string.format("%.4f\n", zoom))
    f:close()
    -- Straight to 1, not to off_zoom or min_zoom: the lock screen is the one
    -- place where the whole screen has to be visible at once.
    if zoom > 1.001 then hl.config({ cursor = { zoom_factor = 1 } }) end
    if mag.screenfx then mag.screenfx.apply() end
  end

  local function unlock()
    local zoom = read_flag()
    if zoom == nil then return end
    os.remove(FLAG)
    if cfg.restore_after_unlock then
      if zoom > 1.001 then mag.set_zoom(zoom, { silent = true }) end
      if mag.screenfx then mag.screenfx.apply() end
    else
      mag.save_state()
      if mag.screenfx then mag.screenfx.unfreeze_all() end
    end
  end

  -- locked: true when the session lock is up, false when it is gone. Safe to
  -- call again with the same value. Returns "locked" or "unlocked".
  function mag.screen_lock(locked)
    if cfg.lock_screen_reset then
      if locked then lock() else unlock() end
    elseif mag.screen_locked() then
      -- Feature switched off while the flag is set: give everything back.
      unlock()
    end
    return mag.screen_locked() and "locked" or "unlocked"
  end

  mag.api.screen_lock = mag.screen_lock
end
