# Bug reports

One file per report, numbered in the order they were filed. Each one is also a GitHub issue; discussion and the fix go there, the file keeps the write-up. A report stays here
until it is fixed or closed; the fix goes into `CHANGELOG.md` as usual and the
report gets a closing line at the top.

| # | Issue | Title | Where | Status |
|---|---|---|---|---|
| [001](001-hyprland-banners-cleared-by-reboot.md) | [#1](https://github.com/JPDoesDev/omarchy-magnifier/issues/1) | Hyprland banners near the top of the screen, cleared by a reboot | both machines | open: cause not captured |
| [002](002-lua-watchdog-budgets.md) | [#2](https://github.com/JPDoesDev/omarchy-magnifier/issues/2) | Plugin callbacks run subprocesses and shader rebuilds inside Hyprland's 50 to 100 ms Lua watchdog | `hypr/lock.lua`, `hypr/jump.lua`, `hypr/screenfx.lua` | open |
| [003](003-desktops-rehome-timer-budget.md) | [#3](https://github.com/JPDoesDev/omarchy-magnifier/issues/3) | `desktops.lua` re-homes workspaces inside a 50 ms timer and indexes a monitor that may be gone | desktops module (omarchy-config) | open |
| [004](004-configerrors-misses-runtime-errors.md) | [#4](https://github.com/JPDoesDev/omarchy-magnifier/issues/4) | `hyprctl configerrors` never shows runtime Lua errors and keeps stale `hyprctl eval` errors | README troubleshooting, `bin/omarchy-magnifier` | open |
| [005](005-desktop-buckets-plugin-not-loaded.md) | [#5](https://github.com/JPDoesDev/omarchy-magnifier/issues/5) | "Desktop buckets: the Magnifier plugin is not loaded" notification on 2026-10-11 | `~/.config/hypr/hyprland.lua` ordering | needs confirming closed |
| [006](006-lock-screen-keeps-zoom.md) | [#6](https://github.com/JPDoesDev/omarchy-magnifier/issues/6) | Lock screen comes up at the current zoom and the zoom keys do not work while locked; it should always open at 100% | `hypr/init.lua` (`mag.bind`), `hypr/magnifier.lua`, Omarchy lock hooks | open |

## Catching the next banner

Hyprland writes its log to `$XDG_RUNTIME_DIR/hypr/<signature>/hyprland.log`.
That directory is wiped at reboot and only the first lines reach the journal,
so a reboot destroys the evidence. Before rebooting, run:

```bash
mkdir -p ~/hyprland-banners && cd ~/hyprland-banners
hyprctl configerrors > configerrors.txt
omarchy capture screenshot    # or a phone photo of the banner
cp "$XDG_RUNTIME_DIR"/hypr/*/hyprland.log hyprland-$(date +%F-%H%M).log
ls -la "$XDG_RUNTIME_DIR"/omarchy-magnifier* > magnifier-state.txt 2>&1
cat "$XDG_RUNTIME_DIR"/omarchy-magnifier.frag >> magnifier-state.txt 2>/dev/null || true
journalctl --user -b --no-pager -o short-iso | grep -iE "omarchy-shell|magnif" > shell.log
cp ~/.local/state/omarchy/notifications/history/*.json . 2>/dev/null || true
```

Then try `hyprctl reload` before rebooting. If the banner goes away, it was a
config-time error (see 001 for the two kinds). Omarchy also keeps the last few
desktop notifications in `~/.local/state/omarchy/notifications/history/`, which
is how 005 was found.
