# 002: Plugin callbacks run subprocesses and shader rebuilds inside Hyprland's Lua watchdog

GitHub issue: https://github.com/JPDoesDev/omarchy-magnifier/issues/2

Filed 2026-10-23. Status: open. Found by reading `src/config/lua/ConfigManager.{hpp,cpp}` at v0.56.2 against `hypr/*.lua`.

## Facts about Hyprland 0.56.2

`guardedPCall` arms a wall-clock deadline around every Lua call and raises
`[Lua] execution timed out in <context>` when the deadline passes. The deadline
is checked on a Lua instruction-count hook, so time spent inside a C call
(`io.popen`, `os.execute`, `hl.dispatch`, `hl.config`) is not interrupted, but
the error fires on the next Lua instruction and the rest of the callback is
skipped. Budgets:

| Context | Budget |
|---|---|
| config reload (whole file, every `dofile`/`require`) | 1500 ms |
| `hl.on` event callback | 50 ms |
| `hl.timer` callback | 50 ms |
| keybind callback | 100 ms |
| `hyprctl eval` | 250 ms |
| dispatch | 100 ms |

A timeout or any other error in a callback becomes a "Runtime error in lua"
banner for 5 seconds (`CConfigManager::addError` outside config parsing).

## Where the plugin is exposed

### `hypr/lock.lua`: `sync()` forks inside 50 ms timers

`sync()` runs from `hl.timer` (`sync_after_change` arms four timers after every
reload and every monitor add/remove) and from the lock keybind. Per call it
does:

- `reload_paused()`: `io.popen("omarchy-hyprland-reload-guard paused ...")`,
  a bash start-up plus `compgen`. 4 ms on an idle laptop; a busy CPU right
  after a dock event (the exact moment these timers fire) is slower.
- `write_flag()`: `os.execute("mkdir -p ...")`, a second fork, on every write.
- `hl.get_monitors()` and string work, cheap.

Two forks inside a 50 ms timer budget is tight. When it times out, the flag
file may be written but `reload_budgeted()` never runs, so the lock layout is
not applied until the next timer, and a banner shows for each miss.

Fix: no subprocesses in timers.
- The reload guard writes `/run/omarchy/hyprland-reload-guard/$HYPRLAND_INSTANCE_SIGNATURE`
  when paused (`pause_instance` in `omarchy-hyprland-reload-guard`). Replace the
  popen with `mag.file_exists(state_dir .. "/" .. os.getenv("HYPRLAND_INSTANCE_SIGNATURE"))`.
- The toggles dir always exists on Omarchy (`flags.lua` lives there and must
  not be removed). Drop the `mkdir -p`, or do it once at load time where the
  budget is 1500 ms.
- `set_lock` also calls `mag.notify` → `hl.exec_cmd`, which is asynchronous and
  fine.

### `hypr/jump.lua` and `hypr/screenfx.lua`: jump/send keybinds rebuild the shader and dispatch several times inside 100 ms

`jump()` → `leave_monitor` (writes the frozen file, regenerates and writes the
shader, `hl.config({ decoration = { screen_shader } })`) → `enter_monitor`
(second shader write and `hl.config`, `focus` dispatch, `cursor.move`
dispatch, `set_zoom` with `hl.config` plus a state-file write). `send()` in
desktops.lua adds `workspace.change_id`, `workspace.move`, `settle()` and a
second `change_id` on top. Each `hl.config` with a new shader path marks the
shader for recompilation on the next frame (`applyScreenShader` runs in the
render path, so compile time is not charged to the callback), but the
dispatches relayout and the file writes are synchronous. On the 4K desktop
with frozen views this is the most expensive thing the plugin does under a
100 ms budget. Not measured yet.

Fix candidates: measure first (`hyprctl eval` with `os.clock()` around
`OmarchyMagnifier.jump()` on the desktop); write the shader once per jump
instead of once in `leave_monitor` and once in `enter_monitor`; move the state
and shader writes to a oneshot `hl.timer` so the keybind only does the
dispatches.

### `bin/omarchy-magnifier` and the bar plugin: `hyprctl eval` has 250 ms

`omarchy-magnifier jump|lock|unfreeze|invert` and `wy02.workspaces`'s
`focusWorkspace` run the same functions through `hyprctl eval`. The budget is
larger, and errors come back on stdout (the CLI prints them), but see report
004 for what they leave behind.

### Config load: 1500 ms

`init.lua` loads four modules with `loadfile`, `screenfx.M.apply()` writes the
shader, `magnifier.lua` reads the state file; `desktops.lua` only arms a
timer. Nothing forks at load time. Fine today; keep it that way.

## How to confirm

On the desktop (two monitors, `mouse_lock = true`):

```bash
hyprctl eval 'local t=os.clock(); OmarchyMagnifier.lock_sync(); hl.exec_cmd("echo sync " .. (os.clock()-t)*1000 .. " ms >> /tmp/mag-timing")'
hyprctl eval 'local t=os.clock(); OmarchyMagnifier.jump(1); hl.exec_cmd("echo jump " .. (os.clock()-t)*1000 .. " ms >> /tmp/mag-timing")'
cat /tmp/mag-timing
```

`os.clock()` is CPU time, so add wall time with `date +%s%N` around the
`hyprctl` call for the full picture. Anything near 40 ms for sync or 80 ms for
jump means the banners are these timeouts.

## Tests

`tests/lock-test.sh` uses `tests/hl-stub.lua`; add a case that asserts
`sync()` does not call `io.popen` or `os.execute` (stub them to fail) once the
fix is in.
