# 005: "Desktop buckets: the Magnifier plugin is not loaded" on 2026-10-11

GitHub issue: https://github.com/JPDoesDev/omarchy-magnifier/issues/5

Filed 2026-10-23. Status: needs confirming closed.

## Evidence

Omarchy's notification history (`~/.local/state/omarchy/notifications/history/`)
on the laptop holds one magnifier-related entry: app `omarchy-action`,
summary "Desktop buckets: the Magnifier plugin is not loaded", at
2026-10-11 18:18:43. It is the only banner text recovered for report 001.

## Cause

`desktops.lua` starts with

```lua
local mag = OmarchyMagnifier
if not (mag and mag.monitors) then
  hl.exec_cmd("omarchy-notification-send 'Desktop buckets: the Magnifier plugin is not loaded'")
  return
end
```

so it fires whenever `require("hypr.desktops")` runs before the plugin's
`dofile(...)` block, or when that block fails. On 2026-10-11 the laptop was
being moved to the plugin (omarchy-config commits of that day); the current
`~/.config/hypr/hyprland.lua` has the plugin block above the require, and a
reload today produced no notification.

## To close

- Confirm the desktop's `hyprland.lua` has the same order (the plugin block
  must sit above `require("hypr.desktops")`; `install.sh` should check for an
  existing `require("hypr.desktops")` line and insert above it, or at least
  warn).
- Make the message say what to do: "load the Magnifier plugin block above
  require(\"hypr.desktops\") in ~/.config/hypr/hyprland.lua".
- Note that a failing module inside the plugin (`init.lua` catches it and
  sends "Magnifier plugin: <name>.lua failed to load: ...") still leaves
  `OmarchyMagnifier` defined, so this notification only means ordering or a
  missing `dofile`.
