# 001: Hyprland banners near the top of the screen, cleared by a reboot

GitHub issue: https://github.com/JPDoesDev/omarchy-magnifier/issues/1

Closed 2026-11-20: cause found and fixed (see "Cause" below), issue closed. The fix is on `main` and goes out with the next release. Open a new report if a banner shows up with the fix in place.

Filed 2026-10-23 on the laptop (wy02-yoga, Hyprland 0.56.2, Omarchy). Status: fixed 2026-11-20 (commit 8f51a94), unreleased.

## Symptom

A few times recently Hyprland showed a banner near the top of the screen. Each
time a reboot made it go away. The user believes they are tied to the
magnifier setup (plugin, mouse lock, desktops module, display-mode.sh). The
banner text was not recorded.

## Cause

Hyprland's red "Screen shader: Screen shader uses uniform 'time', which
requires debug:damage_tracking to be switched off." banner. From 1.0.0
(2026-10-10) the frozen-zoom shader declared `uniform float time` whenever a
monitor was frozen, that is, after every jump away from a magnified monitor on
a two-monitor desk. It was seen with its text on 2026-11-03.

The banner text of the first sightings was never recorded. This is the one
banner that fits every observation in this report:

- **Not in `hyprctl configerrors`, not in the log.** Hyprland raises it from
  the shader compile, outside the config error list and outside Lua. The
  doctor folder of 2026-11-03 was saved with a frozen view and the `time`
  shader installed: `configerrors.txt` is empty and the log has no Lua error.
- **A reload does not cure it, a reboot does.** The frozen views are in
  `$XDG_RUNTIME_DIR/omarchy-magnifier-frozen`; every reload re-installs the
  shader from that file and the banner with it. A reboot wipes the file. This
  is candidate 2 below, with the shader itself as the bad value.
- **Tied to the magnifier on two monitors.** One monitor never freezes a view.

Checked again on 2026-11-20 on the laptop (Hyprland 0.56.2), reading the
banner from the space it reserves at the top of the monitor (`reserved` in
`hyprctl -j monitors`):

| Shader installed | `reserved` top | `hyprctl configerrors` |
|---|---|---|
| none | 0 | empty |
| a shader that only declares and reads `time` | 60 | empty |
| after `hyprctl reload` with that shader gone | 0 | empty |
| the plugin's current shader with a frozen view (no `time`, `debug:damage_tracking` 0) | 0 | empty |
| the same after a second reload | 0 | empty |

The fix (8f51a94, 2026-11-20, unreleased) takes `time` out of the generated
shader and switches `debug:damage_tracking` off while a view is frozen.
Candidate 1 below (watchdog timeouts, reports 002 and 003) was fixed on
2026-10-23 as well; no such banner was ever captured.

## What was checked on 2026-10-23

- `hyprctl configerrors` is empty now and the plugin loads clean.
- Hyprland's log for every earlier boot is gone: it lives under
  `$XDG_RUNTIME_DIR/hypr/` (tmpfs) and only the first ~16 lines reach the
  journal (`debug.enable_stdout_logs = 0`). Boots -5 to 0 (2026-10-19 to
  2026-10-23) show nothing Hyprland-related beyond xkbcomp noise.
- No Hyprland or omarchy-shell core dumps (`coredumpctl`): the only dumps are
  sunshine, cava and bash from 2026-10-07.
- omarchy-shell's journal has no QML errors from `jpdoesdev.magnifier`; only
  Omarchy's own duplicate-IpcHandler warnings.
- Omarchy's notification history holds ten entries. The only magnifier-related
  one is "Desktop buckets: the Magnifier plugin is not loaded" at 2026-10-11
  18:18:43 (see 005). Nothing from `mag.notify` or display-mode.sh is in it.
- No package upgrade of hyprland since install (0.56.2-2, 2026-10-04); only
  aquamarine 0.15.1 on 2026-10-07.
- Monitor and workspace fields the plugin reads (`refresh_rate`, `is_mirror`,
  `description`, `active_workspace`, `scale`, `transform`, `windows`,
  `monitor.name`) all exist with the expected types on 0.56.2.
- Hyprland does not auto-reload when a toggles file or a plugin `.lua` is
  touched here, so the "double reload" theory (flag write plus explicit
  `hyprctl reload`) does not hold on this install.

## What Hyprland 0.56.2 can show at the top (from `src/config/lua/ConfigManager.cpp`)

| Banner | When | How long |
|---|---|---|
| "Your config has errors: ..." (red) | any `addError` while the config is being parsed, including a Lua error in a module loaded by `dofile`/`require` | until the next reload with no errors; `hyprctl reload` clears it if the cause is gone |
| "⚠ Emergency mode tripped ..." | same, when the error stopped every bind from registering | same |
| "Runtime error in lua: ..." (warning icon) | an error or watchdog timeout inside a keybind, `hl.on` callback or `hl.timer` callback | 5 seconds, but a timer that fails every tick makes it look permanent |
| Omarchy desktop notification (top right) | `omarchy-notification-send` from `mag.notify`, desktops.lua, display-mode.sh | shell timeout |

A banner that survives `hyprctl reload` but not a reboot points at state in
`$XDG_RUNTIME_DIR` that is read on every reload and wiped by the reboot:
`omarchy-magnifier-state`, `omarchy-magnifier-frozen`, `omarchy-magnifier.frag`,
`omarchy-magnifier-inverted`, `omarchy-magnifier-unlocked`,
`omarchy-magnifier-lock-retries`, `display-mode-unlocked`, `desktops-state`.
The README's `rm "$XDG_RUNTIME_DIR"/omarchy-magnifier-*; hyprctl reload` is
the same cure as a reboot for those; if it works next time, the culprit is one
of these files and its content should be saved first.

## Candidates, most likely first

1. Watchdog timeouts or errors inside plugin callbacks (report 002) and the
   desktops module (report 003). These are the only code paths that run on
   hotplug, reload and jump, which is when the banners were noticed.
2. A frozen-view or state file in the runtime dir carrying a value that the
   generated shader or `load_state()` cannot take. Nothing found in the code
   that writes such a value, but the files were not inspected while a banner
   was up.
3. A Lua error in a user module (`autorotate.lua`, `visualizer.lua`,
   `desktops.lua`) at config time. These show as "Your config has errors" and
   would be in `hyprctl configerrors`; nobody ran it while a banner was up.

## Next step

Follow "Catching the next banner" in `README.md` here before rebooting. With
the banner text and the log, this report can be split into real bugs or closed.
