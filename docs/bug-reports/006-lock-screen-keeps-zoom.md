# 006: Lock screen comes up at the current zoom; it should always open at 100%

GitHub issue: https://github.com/JPDoesDev/omarchy-magnifier/issues/6

Filed 2026-10-23 from the user's own observation on both machines. Status: open. Enhancement with a usability bug behind it.

## Symptom

When the screen locks with the magnifier zoomed in, the lock screen comes up
zoomed in as well, at the same level and pan position. Password field, clock
and fingerprint prompt are off-screen or huge, and the lock screen is the one
place where a magnified user most needs to see the whole thing at once.

Expected: the lock screen always comes up at 100%, whatever the zoom was
before. What happens to the zoom after unlocking is a separate choice (see
"Open question").

## Why it happens

- `cursor:zoom_factor` is compositor-wide. Hyprland renders the
  ext-session-lock surface through the same zoom as every other surface, so
  the lock screen inherits whatever the plugin last set.
- Omarchy's lock screen is omarchy-shell's own session lock
  (`omarchy-shell lock lock`), reached two ways: `SUPER + CTRL + L` runs
  `omarchy-system-lock`, and omarchy-shell locks on its own idle timer
  (`"lock": 1350` seconds in `~/.config/omarchy/shell.json` on the laptop).
  Neither path tells the plugin anything.
- Hyprland 0.56.2 has no Lua event for the session lock. The `hl.on` list
  (`/usr/share/hypr/stubs/hl.meta.lua`) has `layer.opened` / `layer.closed`,
  but the lock surface is an ext-session-lock surface, not a layer, so nothing
  fires. Omarchy's own `omarchy-hyprland-session-locked` has to infer the lock
  from `LOCK` in `solitaryBlockedBy` of `hyprctl -j monitors`.
- The plugin's binds are made with `mag.bind` → `o.bind(keys, description, fn)`
  with no options, so none of them carry `locked = true`. Hyprland drops every
  non-locked bind while a session lock is active, which means
  `CTRL + ALT + X` (zoom off), `CTRL + ALT + -` and the back side button do
  nothing at the lock screen. The user is stuck zoomed in until they type the
  password blind.
- A frozen view (`omarchy-magnifier.frag` screen shader) and colour invert
  persist the same way: the shader is applied to the whole output, lock
  surface included.

## Fix, in two parts

### 1. Zoom out when the lock starts (the actual request)

There is no event to hook, so the plugin needs a signal from whoever locks:

- **Omarchy-side, clean:** ask Omarchy for lock hooks
  (`~/.config/omarchy/hooks/lock.d/` and `unlock.d/`, matching the existing
  `theme-set.d`, `post-boot.d`, `battery-low.d` convention). omarchy-shell's
  lock would run them on lock and on successful unlock. The plugin's
  `install.sh` drops a hook that runs `omarchy-magnifier zoom off` (and
  `unfreeze`). This covers both the keybind and the idle path.
- **Plugin-side, today, keybind path only:** rebind `SUPER + CTRL + L` in the
  plugin (or document it for `~/.config/hypr/bindings.lua`) to a function that
  calls `mag.zoom_off({ silent = true })`, clears the frozen view, then
  `hl.exec_cmd("omarchy-system-lock")`. Does not cover the idle lock.
- **Plugin-side, idle path, avoid:** a repeating `hl.timer` polling
  `hyprctl -j monitors` for `LOCK`. That is a fork inside a 50 ms timer, the
  exact problem of report 002. Only acceptable if Hyprland exposes the lock
  state to Lua without a subprocess; it does not on 0.56.2.

Until Omarchy has hooks, do the keybind path and document the idle gap.

### 2. Let the zoom keys work at the lock screen (makes the bug survivable)

Give `mag.bind` an options argument and pass `{ locked = true }` for
`zoom_out`, `zoom_out_key`, `off`, the side-button off binding and `invert`.
`o.bind` already takes a fourth `options` table and forwards it to `hl.bind`,
and Omarchy uses the same flag for its volume and brightness keys
(`default/hypr/bindings/media.lua`). Zoom-in keys stay unlocked on purpose:
nothing should be able to zoom the lock screen further in.

Then whatever locked the screen, `CTRL + ALT + X` fixes it.

## Open question

After unlock, restore the zoom that was active before the lock or stay at
100%? The state file already holds the pre-lock zoom (`mag.save_state`), so
restoring is one `hl.config` call in an unlock hook. Default suggestion: stay
at 100%, add a setting `restore_zoom_after_unlock = false`. Needs the user's
preference.

## How to confirm

1. `CTRL + ALT + Z`, then `SUPER + CTRL + L`. Lock screen is at 500% today;
   should be at 100% after the fix.
2. Lock, then press `CTRL + ALT + X` at the lock screen. Nothing happens
   today; should zoom out after part 2.
3. Zoom in and leave the machine until the idle lock fires (22.5 min on the
   laptop). Only the Omarchy hook path fixes this one.

## Tests

- `tests/zoom-test.sh`: assert the recorded `hl.bind` options for the off and
  zoom-out binds contain `locked = true` and the zoom-in binds do not
  (`S.calls.bind` in `tests/hl-stub.lua`).
- If the lock keybind lands: a test that the recorded exec_cmd for the lock
  binding runs after `cursor.zoom_factor` was set to 1.

## Docs to update when fixed

README "Hotkeys" (the lock-screen note), "Known limits" until the idle path is
covered, `CHANGELOG.md`.
