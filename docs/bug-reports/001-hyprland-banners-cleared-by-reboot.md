# 001: Hyprland banners near the top of the screen, cleared by a reboot

Filed 2026-10-23 on the laptop (wy02-yoga, Hyprland 0.56.2, Omarchy). Status: open, root cause not captured.

## Symptom

A few times recently Hyprland showed a banner near the top of the screen. Each
time a reboot made it go away. The user believes they are tied to the
magnifier setup (plugin, mouse lock, desktops module, display-mode.sh). The
banner text was not recorded.

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
