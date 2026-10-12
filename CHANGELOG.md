# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `Super + pinch` now zooms continuously. The gesture was registered without `mode = "live"`, so Hyprland treated it as a toggle to `pinch_zoom_level` (1.0): a finished pinch did nothing at 100% and snapped any magnified screen back to 100%, and whether the fingers spread or squeezed made no difference. Found in the laptop live test on 2026-10-11.

## [1.0.0] - 2026-10-10

### Added

- Colour inversion of every screen on Ctrl+Alt+I (`omarchy-magnifier invert`), generated into the same screen shader as frozen zoom so the two never fight over Hyprland's single shader slot. Off after a reboot.

- Zoom in and out with `Ctrl + Alt + scroll`, in steps of `step`, clamped to `min_zoom..max_zoom`.
- Preset and off keys: `Ctrl + Alt + Z` zooms to `preset_zoom` (300% by default), `Ctrl + Alt + X` zooms to `off_zoom`.
- Continuous zoom with `Super + pinch` on the touchpad, clamped to the same limits.
- Optional `Super + mouse side buttons` for preset and off, behind `side_buttons = true` with configurable button codes.
- Zoom percentage popup beside the pointer, scaled so it stays readable at any zoom level, themed from the active Omarchy theme with optional fixed colours through `osd_style`.
- Zoom level kept across Hyprland config reloads, including changes made by Omarchy's own `Super + Ctrl + Z` and `Super + Ctrl + Alt + Z`.
- Monitor jump with `Super + Ctrl + scroll`: each monitor remembers its own pointer position and zoom level.
- Frozen zoom: the monitor you jump away from keeps its magnified view through a per-output screen shader, skipped when another screen shader is active.
- Mouse lock with `Super + Ctrl + M`: the pointer stays on one monitor until a jump, implemented as a gapped monitor layout with no daemon.
- Settings as one Lua table (`omarchy_magnifier`) in `~/.config/hypr/hyprland.lua`, every key optional, any key chord settable to `false`.
- `omarchy-magnifier` command line tool: `zoom in|out|toggle|preset|off|set <n>|status`, `jump next|prev`, `lock on|off|toggle|status`, `unfreeze`.
- `install.sh` that adds the settings block and the `dofile` line to `hyprland.lua`, links the command line tool into `~/.local/bin` and reloads Hyprland; `install.sh --uninstall` reverses it.

[1.0.0]: https://github.com/JPDoesDev/omarchy-magnifier/releases/tag/v1.0.0
