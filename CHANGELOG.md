# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `wheel_every_notch` (default `true`): sets Hyprland's `binds:scroll_event_delay` to 0 while a wheel chord is bound. With the default 300 ms delay, wheel notches arriving within the delay skip the binds and reach the focused window with `Ctrl` still held, so a quick `Ctrl + Alt + scroll` also zoomed a browser page (#7). Side effect: Omarchy's `Super + scroll` binds now fire on every notch.
- `omarchy-magnifier doctor [DIR]`: saves `hyprctl configerrors`, the tail of Hyprland's log, the plugin's runtime files, the mouse lock rule file and the magnifier lines of the shell journal into one folder and prints a summary, before a reboot wipes the log (#4).
- `OmarchyMagnifier.batch(fn)`: runs `fn` with the screen shader rebuilt once at the end, for modules that chain `leave_monitor` and `enter_monitor`.

### Changed

- Mouse lock `sync()` no longer starts a process: Omarchy's reload guard is read from its state directory (`/run/omarchy/hyprland-reload-guard`) instead of through `io.popen`, and the toggles directory is created only when missing instead of with `mkdir -p` on every write. The syncs run inside 50 ms timer callbacks, where two forks could trip Hyprland's Lua watchdog (#2).
- A monitor jump rebuilds the screen shader once instead of twice (freeze of the monitor left, unfreeze of the target), halving the file writes and `hl.config` calls inside the 100 ms keybind budget (#2).
- `install.sh` inserts the settings block above an existing `require("hypr.desktops")` line instead of appending it after, and warns when an existing block sits below that line, since that module needs the plugin loaded first (#5).
- The command line tool says that a failed `hyprctl eval` stays in `hyprctl configerrors` until the next reload (#4).

### Fixed

- No more red "Screen shader: Screen shader uses uniform 'time', which requires debug:damage_tracking to be switched off" banner while a monitor is frozen. The generated shader referenced `time` to keep Hyprland redrawing, which Hyprland (0.50 through 0.56.2 at least) answers with that banner on every shader install and after every reload, and which never forced redraws in the first place (only damage does). The shader no longer references `time`; instead `debug:damage_tracking` is set to 0 while any view is frozen, which is what the banner asks for and what keeps the frozen view updating, and put back to the value it had when the last view goes. A value the user already set to 0 is left alone. Found on 2026-11-03.

### Documented

- README troubleshooting: the yellow "Runtime error in lua" banner is never in `hyprctl configerrors`, where its text actually is, and the stale eval errors (#4). New known limit for `wheel_every_notch`.
- README known limit "GPU and battery while frozen" now names the `debug:damage_tracking` switch.

## [1.1.0] - 2026-10-11

### Added

- Keyboard-only zoom steps: `Ctrl + Alt + =` zooms in and `Ctrl + Alt + -` zooms out by one step, the same as the scroll wheel. New settings `keys.zoom_in_key` and `keys.zoom_out_key`; set either to `false` to leave it unbound.

### Documented

- Known limit: while the mouse is locked, Hyprland's directional monitor dispatchers (`l`/`r`/`u`/`d`) find no neighbour across the gap, so Omarchy's `Super + Shift + Alt + arrows` do nothing. Found with two monitors on 2026-10-11.

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

[Unreleased]: https://github.com/JPDoesDev/omarchy-magnifier/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/JPDoesDev/omarchy-magnifier/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/JPDoesDev/omarchy-magnifier/releases/tag/v1.0.0
