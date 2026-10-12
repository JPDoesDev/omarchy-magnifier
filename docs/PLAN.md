# Upstreaming the lock-on magnifier

Working plan for turning the personal magnifier setup (`~/.local/share/accessibility/magnifier/`, documented in `~/omarchy-config/omarchy-accessibility-setup.md` section 9 and `features/lock-on-magnifier.md`) into (1) a published Omarchy plugin, then (2) a series of small pull requests to Omarchy. This is an Omarchy-only effort: no Hyprland upstream work.

**Current focus: Track A, the plugin.** Track B waits until the plugin is published.

Decisions taken so far (2026-10-10):

| Decision | Choice |
|---|---|
| Route | Omarchy only. Build and publish the plugin first, then open the Omarchy PRs while the plugin is live and demoable. No Hyprland track. |
| Core PR scope | Zoom out + clamp, zoom % OSD, zoom persistence across reload, scroll + pinch bindings. |
| Chords proposed upstream | The personal chords (Ctrl+Alt+scroll, Ctrl+Alt+Z / X presets, Super+side buttons), proposed in addition to the existing Super+Ctrl+Z family, never replacing it. Side-button binds go behind an opt-in variable because button codes are hardware-specific. |
| Settings | Lua variables set in `~/.config/hypr/hyprland.lua` before the module loads (the `omarchy_default_bindings` idiom). `~/magnifier.conf` is retired. |
| Plugin id | `jpdoesdev.magnifier`, display name "Magnifier", repo `JPDoesDev/omarchy-magnifier`, IPC target `magnifier`. |
| OSD colours | Follow the active theme through `Commons.Color` by default; `osd_style` keys override to fixed colours (your config sets black/white/yellow). |
| Mouse lock | Ships in v1, ported from `monitor-lock.sh` to `hypr/lock.lua`. |
| Shipped defaults | step 1, preset 3, off 1, min 1, max 10, OSD on, pinch on, side buttons off, jump on, lock on. |
| License | MIT (assumed; matches Omarchy and the invert plugin). |

## 1. What upstream looks like

- The repo is `omacom/omarchy` (the `basecamp` URL redirects), default branch `quattro`, installed version here 4.0.4. Contribution rules live in `AGENTS.md` and `agents/skills/*.md`: bash 5 style, `#!/bin/bash`, two-space indent, atomic commits, `./test/all` green, visual changes verified with `omarchy capture screenshot fullscreen save` or a short screen recording, manual pages updated.
- Zoom in Omarchy is two function binds in `default/hypr/bindings/utilities.lua`: `SUPER + CTRL + Z` adds 1 to `cursor.zoom_factor`, `SUPER + CTRL + ALT + Z` resets it. No zoom out, no clamp, no OSD, no persistence. Manual: `manual/07-hotkeys.md` lines 53 and 54.
- Zoom itself is Hyprland's. The Lua config API (`hl.config`, `hl.get_config`, `hl.gesture`, `hl.timer`, `hl.bind`) is upstream Hyprland since 0.55 (PR hyprwm/Hyprland#13817). Omarchy only adds the `o.*` helpers in `default/hypr/helpers.lua`. Hyprland 0.56.2 hard-codes zoom to the monitor under the pointer in `src/output/MonitorZoomController.cpp` (`pointerOnMonitor ? zoom : 1.0`), keeps a single global zoom value, and has no `zoom` dispatcher. Nobody has filed a per-monitor zoom request there.
- Open demand on the Omarchy side: issue #11145 "Missing keybinding to zoom out" (labels bug, enhancement), PR #11181 adding `SUPER + CTRL + SHIFT + Z` (unreviewed since 2026-09-10), discussion #4081 "Feature request: Screen magnification support" (Suggestions, low-vision author, no maintainer answer).
- Precedents: PR #5636 (new magnifier script and chords) was closed in four minutes as a duplicate of the existing binds. PR #12133 (colour invert using the same single screen-shader slot trick) got no review in three weeks and moved to a standalone plugin, `Maximilian-Maag/omarchy-invert`. Merges are almost all by DHH and two or three core maintainers, so small PRs that close a labelled issue have the best odds.
- Plugin distribution exists: a public git repo with `manifest.json` at the root, installed with `omarchy plugin add <url>`, listed on plugins.omarchy.org by opening an issue from the `submit-plugin.yml` template in `omacom/omarchy-plugin-marketplace`. Validation and an automated security baseline run on the exact commit. The registry has no zoom, magnifier or accessibility plugin yet.

## 2. Track A: the plugin (`omarchy-magnifier`)

### 2.1 Repo layout

```
omarchy-magnifier/
  manifest.json            kinds: ["panel"]; entryPoints.panel = "ZoomOsd.qml"; keepLoaded: true
  ZoomOsd.qml              pointer-anchored zoom percentage popup (the shell plugin)
  ZoomOsdModel.js          pure layout math (card scale, on-screen to logical mapping), unit-testable with node
  hypr/
    init.lua               single entry point loaded from hyprland.lua; sets package.path, reads settings, requires the rest
    magnifier.lua          zoom set/step/preset, OSD call, reload persistence, pinch gesture
    jump.lua               per-monitor jump with pointer and zoom memory
    screenfx.lua           frozen-zoom screen shader generator
    lock.lua               mouse lock as Hyprland monitor rules (replaces monitor-lock.sh, see 2.3)
  bin/
    omarchy-magnifier      CLI: zoom in|out|set N|toggle|status, jump next|prev, lock on|off|toggle|status
  install.sh               idempotent: appends the dofile line to hyprland.lua, enables the plugin, reloads; --uninstall reverses it
  tests/
    lua-syntax-test.sh     luac -p over hypr/*.lua
    osd-model-test.sh      node tests for ZoomOsdModel.js (same pass/fail protocol as Omarchy's test/shell.d)
    settings-test.sh       defaults, clamping, bad values fall back
  README.md                hotkeys, settings, install and removal, multi-monitor guide (from features/lock-on-magnifier.md), limits
  CHANGELOG.md
  LICENSE                  MIT
  preview.png              marketplace card image
```

### 2.2 Hard-defined modifications from the personal setup

1. Plugin identity. `wy.zoom-osd` becomes `jpdoesdev.magnifier`. IPC target `zoomosd` becomes `magnifier`. The `omarchy.` prefix is reserved.
2. Panel contract. Keep the `IpcHandler`, and add the `open(payloadJson)` and `close()` methods the shell requires of panel plugins. The payload is JSON: `{ "zoom": 7, "style": { ... } }`.
3. Settings move to Lua. Replace every `~/magnifier.conf` read in both Lua and QML with one table:

   ```lua
   omarchy_magnifier = {
     preset_zoom = 3, off_zoom = 1, step = 1, min_zoom = 1, max_zoom = 10,
     osd = true, pinch = true, pinch_fingers = 2, pinch_zoom_level = 1.0,
     side_buttons = false, side_button_in = 276, side_button_out = 275,
     jump = true, mouse_lock = true,
     -- colours default to the active theme; set any of background / text / border to force a colour
     osd_style = { font_size = 48, duration_ms = 1200, border_width = 4, padding = 15, min_scale = 2, pointer_gap = 104, pointer_drop = 28 },
   }
   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/<id>/hypr/init.lua")
   ```

   The QML never reads a file again. Lua sends the style with every show, so a reload picks up changes with no shell restart. Missing keys fall back to defaults in Lua, and the QML keeps its own defaults for a payload with no style.
4. Loading. One `dofile` line in `hyprland.lua` instead of copying files into `~/.config/hypr/`. `dofile` is not cached, so Omarchy's reload logic in `bootstrap.lua` needs no changes. `init.lua` prepends its own directory to `package.path` and requires `magnifier`, `jump`, `screenfx`, `lock` from there. Note that a plugin id containing a dot cannot be `require`d through `~/.config/?.lua`, which is why the entry is a `dofile`.
5. Self-healing scripts go away. `ensure-magnifier.sh`, the post-boot and post-update hooks and the master-copy directory are replaced by the git checkout under `~/.config/omarchy/plugins/`, which `omarchy plugin update` maintains. `install.sh` stays idempotent and is the only thing that touches `hyprland.lua`.
6. Shader sharing. `screenfx.lua` currently also owns colour invert. The plugin version owns only frozen zoom. Add a guard: if `decoration.screen_shader` is already set by something else when the plugin first needs the slot, log a notice through `omarchy-notification-send` and skip freezing instead of overwriting it. Document the conflict with the invert plugin in the README.
7. Mouse lock. `monitor-lock.sh` (bash, socat, jq, toggle flag file) becomes `hypr/lock.lua`: listen on `monitor.added`, `monitor.removed` and `monitor.layout_changed`, compute the gapped layout from `hl.get_monitors()`, apply it with `hl.monitor`, and keep the unlocked flag in `$XDG_RUNTIME_DIR`. No daemon, no autostart line, no external tools. The `SUPER + CTRL + M` bind calls it directly instead of looking up `display-mode.sh` or `monitor-lock.sh`. The laptop display modes (section 17) stay out of the plugin.
8. Persistence. Keep the `$XDG_RUNTIME_DIR/magnifier-state` file. Save on every `set_zoom` and on `config.reloaded`, and keep the 500 ms timer only as a fallback for zoom changed by the pinch gesture, since Hyprland emits no event for that. Restore on load.
9. Gesture name. Verify `cursorZoom` against `cursor_zoom` with `mode = "live"` on 0.56.2 and use whichever the stubs accept. Clamp after a pinch ends so `min_zoom` and `max_zoom` hold for the gesture too.
10. Decouple from `desktops.lua`. Keep returning the helper table so the personal `desktops.lua` keeps working, but nothing in the plugin references desktops or the `wy02.*` clones.
11. Remove machine-specific values: mouse button codes become settings, no paths under `~/.local/share/accessibility`, no `wy.` or `wy02.` names.
12. Style. Bash files follow Omarchy's `AGENTS.md` (`#!/bin/bash`, `[[ ]]`, `(( ))`, no `notify-send`). QML imports `qs.Commons as Commons` for theme colours (required alias since Qt 6.12 shadows `Color`), with `osd_style` overrides applied on top.
13. Tests and validation. `omarchy plugin validate .` must pass. The node test for `ZoomOsdModel.js` covers card scale at zoom 1, 2, 7 and 10, the left-flip near the right edge, and vertical clamping.
14. Documentation. README written for low-vision readers: large hotkey table first, settings table second, troubleshooting third. Include the capture of the OSD at 700% and a short recording of the monitor jump.

### 2.3 Publishing steps

1. Create the public repo under `JPDoesDev`, push, tag `v1.0.0`.
2. Install it on both machines with `omarchy plugin add`, remove the old master copy and hooks, run for a few days.
3. Submit through the marketplace issue form (category `Desktop`, tags `hyprland`, `quickshell`, `system`). Expect `review-required` because `install.sh` edits `hyprland.lua`; no sudo, no downloads, so no blocking finding.
4. Post in Omarchy discussion #4081 with the install command and the recording. This is the demo the PRs will link to.

## 3. Track B: Omarchy pull requests

One fork, one branch per PR, each atomic and tested. Order by mergeability.

| # | PR | Files | Closes | Notes |
|---|---|---|---|---|
| B1 | Zoom out and clamp | `default/hypr/bindings/utilities.lua`, `manual/07-hotkeys.md`, a test in `test/shell.d/` | #11145 | Extract `set_zoom(z)` that clamps to 1..10. Add `SUPER + CTRL + SHIFT + Z` zoom out to stay compatible with PR #11181, and `CTRL + ALT + mouse_up` / `mouse_down` for wheel zoom. Smallest diff, best odds. Reference #11181 and offer to supersede it. |
| B2 | Zoom feedback on the OSD | `shell/plugins/osd/Osd.qml`, `OsdModel.js`, `test/shell.d/osd-test.sh`, `bin/omarchy-osd`, `utilities.lua` | #4081 partially | Add a `zoom` icon key and an `anchor: "pointer"` payload option so the card sits beside the pointer and stays on screen inside a magnified viewport. Without the anchor a centred OSD is off-screen at 7x. The zoom binds call `omarchy-osd -i zoom -p <pct> --anchor pointer`. Visual verification captures at 1x and 7x. |
| B3 | Zoom survives reload | new `default/hypr/zoom.lua`, `default/hypr/omarchy.lua` | none yet, file an issue first | Save zoom on `config.reloaded` and restore on load from `$XDG_RUNTIME_DIR`. Open a bug issue first with the reproduction: set zoom, change theme, zoom is gone. A PR that closes a labelled bug is reviewed sooner. |
| B4 | Presets and pinch | `utilities.lua`, `config/hypr/hyprland.lua` template, `manual/07-hotkeys.md`, `manual/34-keyboard-mouse-trackpad.md` | #4081 | `CTRL + ALT + Z` jump to preset, `CTRL + ALT + X` zoom off, `SUPER + pinch` live zoom, `omarchy_zoom_preset` and `omarchy_zoom_side_buttons` opt-in variables documented in the template next to `omarchy_default_bindings`. |

Per-monitor jump, frozen zoom and the mouse lock stay in the plugin. They depend on a shader workaround and a layout trick that core is unlikely to carry.

Before opening B1, check `hyprland-binding-conflicts-test.sh` passes with the new chords, since it resolves `code:N` and modifier order. `CTRL + ALT + scroll` and `CTRL + ALT + Z/X` collide with nothing in the defaults.

## 4. Order of work

1. Round-2 decisions below.
2. Scaffold the plugin repo in this directory, port the Lua and QML with the modifications in 2.2, write tests, install on this machine, verify with captures.
3. Publish, submit to the marketplace, post in #4081.
4. Fork `omacom/omarchy` into this directory, open B1, then B2, B3, B4 one at a time as each gets a response.

## 5. Resolved questions

Round 1 (route, core scope, chords, settings) and round 2 (id, OSD colours, mouse lock, defaults) are recorded in the decisions table at the top. Nothing is open before scaffolding starts.

## 6. Status (2026-10-10, evening)

Plugin built in `omarchy-magnifier/` per 2.1 and 2.2. `tests/run` passes 7 of 7 files (about 410 checks) under Lua 5.4 and 5.5; `omarchy plugin validate` passes; install and uninstall round-trip `hyprland.lua` byte-identical. Not yet done: live test on this machine, `preview.png`, git init and first push, marketplace submission.

Review findings fixed before the live test: settings merge dropped `false` values and boolean-with-false defaults (side buttons), `off_zoom`/`preset_zoom` were not clamped so `off_zoom = 0` wedged toggle, the reload guard check used `os.execute` which cannot read an exit status inside Hyprland, and the lock's sync could reload without bound when Hyprland refuses a layout (now capped at 3 per mismatch, reset by a match, a hotplug or a lock keypress).

## 7. Live test (2026-10-10, desktop, single monitor DP-1 3440x1440 at 1.25)

Done: snapshot committed and pushed to `omarchy-config` (tag `pre-magnifier-plugin-2026-10-10`, `snapshots/2026-10-10-pre-magnifier-plugin/` with RESTORE.md). Personal magnifier, invert and monitor-lock switched off (hooks moved to `~/.local/share/accessibility/backups/20261010-pre-plugin/`, require lines commented, daemon stopped, `wy.zoom-osd` disabled). `desktops.lua` now reads its jump helpers from the plugin's `OmarchyMagnifier` global, so the plugin block sits above `require("hypr.desktops")` in hyprland.lua. Plugin installed from the dev checkout, linked at `~/.config/omarchy/plugins/jpdoesdev.magnifier`.

Verified live: no config errors, 9 bindings, popup answers ping and renders beside the pointer (high-contrast override and theme colours), zoom set/in/out/clamp/toggle through the CLI, zoom 3 survives `hyprctl reload`, lock toggle on one monitor reports and notifies correctly, no QML errors in the journal. Verified by hand on 2026-10-10 (checklist 1.1 to 1.6): scroll-wheel steps and both clamps, Ctrl+Alt+Z to the preset and Ctrl+Alt+X off (a first report that they did nothing predated the second install run; a Hyprland-side key logger was armed and then removed once they worked). Verified by hand on 2026-10-11: side buttons, Super+K listing, popup edge behaviour, theme switch, shell restart and reboot persistence, colour inversion (checklist 1.7 to 3.4, section 8); on the laptop, pinch (4.1 to 4.3) after adding `mode = "live"` to the gesture, which until then was a toggle that snapped the zoom back to 100%. Still to test by hand with two monitors: jump, frozen zoom, mouse lock, hotplug re-lock, desktops interplay (sections 5, 6, 8.5).

Colour inversion was then folded into the plugin (2026-10-11): `screenfx.lua` generates invert and frozen zoom into the one shader, `invert = true` and `keys.invert` settings, `omarchy-magnifier invert`, tests and docs. Verified live: Ctrl+Alt+I bound, CLI on/off, correct shader, slot cleared when off. The personal `invert.lua` stays unloaded.

## 8. Live test plan (reference)

1. Roll back the personal setup so the two cannot fight: remove the `require("hypr.magnifier")` and `require("hypr.invert")` lines from `~/.config/hypr/hyprland.lua` (invert shares the screen-shader slot), the post-boot and post-update `ensure-magnifier` and `ensure-monitor-lock` hooks, the `monitor-lock.sh` autostart line, the `wy.zoom-osd` plugin entry, and the `accessibility-monitor-lock.lua` toggle flag. Keep the master copies under `~/.local/share/accessibility/` untouched as the rollback path. `desktops.lua` requires `hypr.magnifier`; point it at the plugin's `mag.jump` helpers or leave desktops disabled during the test.
2. Install: `omarchy-magnifier/install.sh` from the checkout (later `omarchy plugin add`), with the personal settings in the block: `preset_zoom = 7, step = 2, side_buttons = true, osd_style = { background = "#000000", text = "#ffffff", border = "#ffff00" }`.
3. Verify: `hyprctl configerrors` empty, `hyprctl binds | grep -i magnifier` shows 9, `omarchy-shell magnifier ping`, popup at 300% and 700%, theme-colour popup with the override removed, jump between monitors with frozen zoom, lock on and off, zoom kept across `hyprctl reload` and a theme change, pinch, and `omarchy-magnifier status`.
4. Capture `preview.png` and a short recording for the README and the #4081 post.
