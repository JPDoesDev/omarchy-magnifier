# Bug reports

One file per report, numbered in the order they were filed. A report stays here
until it is fixed or closed; the fix goes into `CHANGELOG.md` as usual and the
report gets a closing line at the top.

| # | Title | Where | Status |
|---|---|---|---|
| [001](001-hyprland-banners-cleared-by-reboot.md) | Hyprland banners near the top of the screen, cleared by a reboot | both machines | open: cause not captured |
| [002](002-lua-watchdog-budgets.md) | Plugin callbacks run subprocesses and shader rebuilds inside Hyprland's 50 to 100 ms Lua watchdog | `hypr/lock.lua`, `hypr/jump.lua`, `hypr/screenfx.lua` | open |
| [003](003-desktops-rehome-timer-budget.md) | `desktops.lua` re-homes workspaces inside a 50 ms timer and indexes a monitor that may be gone | desktops module (omarchy-config) | open |
| [004](004-configerrors-misses-runtime-errors.md) | `hyprctl configerrors` never shows runtime Lua errors and keeps stale `hyprctl eval` errors | README troubleshooting, `bin/omarchy-magnifier` | open |
| [005](005-desktop-buckets-plugin-not-loaded.md) | "Desktop buckets: the Magnifier plugin is not loaded" notification on 2026-10-11 | `~/.config/hypr/hyprland.lua` ordering | needs confirming closed |

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
