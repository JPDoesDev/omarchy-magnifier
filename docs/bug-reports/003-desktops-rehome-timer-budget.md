# 003: desktops.lua re-homes workspaces inside a 50 ms timer and indexes a monitor that may be gone

GitHub issue: https://github.com/JPDoesDev/omarchy-magnifier/issues/3

Filed 2026-10-23. Status: open. Lives in the desktops module (master copy
`~/.local/share/accessibility/desktops/desktops.lua`, live copy
`~/.config/hypr/desktops.lua`, documented in omarchy-config), not in this
repo, but it is part of the same setup and the same watchdog applies (report 002).

## What it does

`monitors_changed()` arms a 1.5 s oneshot `hl.timer` on `monitor.added`,
`monitor.removed`, `monitor.layout_changed` and at the end of every config
reload. The callback `rehome()`:

1. lists every workspace and builds the list of moves;
2. `hl.dispatch(workspace.move)` once per misplaced workspace;
3. `hl.get_monitor(name):set_workspace(...)` for each homed monitor;
4. `settle()` per monitor, which may dispatch `workspace.change_id`;
5. focus and cursor dispatches, then `remember_shown()` writes the state file.

All of it runs inside the timer's 50 ms budget. After a dock or undock with
several workspaces to move, each `workspace.move` relayouts a monitor; the
budget is easy to exceed. The result is a "Runtime error in lua: [Lua]
execution timed out in timer callback" banner and a half-done re-home: some
desktops moved, the rest left on the wrong monitor, the shown-workspace
memory not updated. That matches "something is off after docking, a reboot
fixes it".

Second issue, same function: `hl.get_monitor(name):set_workspace(...)` is
called without a nil check. `homed` was built from `mag.monitors()` a few
dispatches earlier; if the monitor vanished in between (KVM flap, the second
`monitor.removed` of an undock) this raises "attempt to index a nil value",
also a 5 second banner, and aborts the rest of `rehome()`.

## Fix candidates

- Do one move per timer tick: `rehome()` performs the first pending move and
  re-arms itself with a short oneshot timer until the move list is empty, then
  runs the settle/focus/remember tail. Each tick stays well under 50 ms.
- Guard `hl.get_monitor(name)` with `if mon then`, as `settle()` already does.
- `remember_shown()` runs on every `workspace.active` event (50 ms budget) and
  writes a file; it is cheap, but if the above moves to ticks it should only
  write when the set changed, which it already checks.

## How to confirm

On the desktop, dock or undock with four or more desktops in use and watch
for the banner; or time it:

```bash
hyprctl eval 'local t=os.clock(); desktops_rehome(); hl.exec_cmd("echo rehome " .. (os.clock()-t)*1000 .. " ms >> /tmp/mag-timing")'
```

## Docs to update when fixed

The three homes: this repo's README (two-monitor section) if behaviour
changes, `~/omarchy-config/features/lock-on-magnifier.md` and the history
table in `omarchy-accessibility-setup.md`, and the master `desktops.lua`
copied to `~/.config/hypr/desktops.lua` followed by `hyprctl reload`.
