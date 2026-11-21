# 008: After the monitor sleeps, the zoomed pointer is drawn small and clicks land off its tip

GitHub issue: none. This is a Hyprland bug that the plugin cannot repair, so no issue was filed in this repository.

Closed 2026-11-20: worked around with `cursor:no_hardware_cursors = 1`, which the README lists as a known limit. The upstream report against hyprwm/Hyprland (fix option 3 below) is still to file.

Filed 2026-11-10 from the user's own observation (desktop, LG ULTRAGEAR+ 3440x1440 on DP-1, scale 1.25, Hyprland 0.56.2). Status: worked around the same day with `cursor:no_hardware_cursors = 1` in `~/.config/hypr/looknfeel.lua`; upstream fix proposed below.

## Symptom

After the machine has sat idle long enough for the screen to sleep, or after
some fullscreen apps have run, the magnifier is still zooming the screen but the
pointer is wrong in two ways:

- it stays small: it does not grow with the zoom the way it normally does, and
  it shrinks relative to the content as the zoom goes up;
- where it points is not where a click lands. The offset grows towards the
  edges of the screen and with higher zoom.

Zooming out to 100% and back in does not fix it. Only restarting Hyprland does
(logging out and in). Until then the plugin's own behaviour (steps, preset,
popup, state file) is all normal; what is wrong is how Hyprland draws the
pointer.

## Why it happens

Hyprland draws the pointer one of two ways: on the GPU's hardware cursor plane,
which is cheap but is composited after everything else at the raw screen
position and native size, or in software as part of the frame. Whole-screen
zoom (`cursor:zoom_factor`) is a transform of the frame, so while zoomed the
pointer has to be drawn in software; a hardware-plane pointer is neither scaled
nor moved by the zoom. That is the small pointer, and the offset is the zoom
box being clamped at the screen edges while the hardware pointer is not.

The switch to software is made once, with a global flag, in
`IHyprRenderer::renderMonitor` (Hyprland 0.56.2, `src/render/Renderer.cpp`
line 2120):

```cpp
static bool zoomLock = false;
if (zoomLock && ZOOMFACTOR == 1.f) {
    Pointer::mgr()->unlockSoftwareAll();
    zoomLock = false;
} else if (!zoomLock && ZOOMFACTOR != 1.f) {
    Pointer::mgr()->lockSoftwareAll();
    zoomLock = true;
}
```

`lockSoftwareAll()` increments `softwareLocks` on every per-monitor pointer
state that exists at that moment (`src/pointer/PointerManager.cpp` line 64).
A monitor's state is created with `softwareLocks = 0`
(`src/pointer/PointerManager.hpp` line 175) and is erased when the monitor
object is destroyed (`destroy` listener in the `CPointerManager` constructor).

Sequence on this machine, from the Hyprland log and the user journal of
2026-11-10:

1. Zoom at 500%. First frame: `lockSoftwareAll()`, DP-1's state has one lock,
   `zoomLock = true`. Pointer drawn in software, correct.
2. 20:05 idle; the screen sleeps. 20:54 on wake the LG drops and re-trains its
   DisplayPort link: aquamarine logs `Connector DP-1 disconnected`, Hyprland
   creates its FALLBACK output, then `Connector DP-1 connected` and
   omarchy-shell logs `Got removal for monitor "FALLBACK"`. The old `CMonitor`
   is destroyed and a new one created, so DP-1 now has a fresh pointer state
   with `softwareLocks = 0`.
3. `zoomLock` is still `true`, so the renderer never calls `lockSoftwareAll()`
   again. `updateCursorBackend()` sees no lock and puts the pointer back on the
   hardware plane: `drm: Cursor buffer imported into KMS` right after the
   reconnect in the log. From here every zoom level uses the hardware pointer.
4. Zooming out to 100% runs `unlockSoftwareAll()`, which takes the new state to
   -1 (it does not clamp). Zooming back in runs `lockSoftwareAll()`: 0 again.
   The round trip is a no-op, so the user cannot recover by hand. A disconnect
   that happens while at 100% would reset things, as would a Hyprland restart.

Anything that destroys and recreates the monitor while zoomed does the same:
display sleep on a DP monitor that drops the link, a KVM switch, a game or
sim-mode session that forces a re-train through a mode change. This is the
"after sitting or after certain applications" pattern.

Two things make it hard to see:

- `hyprctl monitors` prints `hardwareCursorsInUse: true` whatever the live
  state; the field is `!shouldUseSoftwareCursors()`, i.e. the config setting
  (`src/debug/HyprCtl.cpp` line 299). The live state does show in
  `tearingBlockedBy`: `hw cursor` is listed only when
  `hasVisibleHWCursor()` is true, which needs `softwareLocks == 0`. At 500%
  that entry should never be present; on 2026-11-10 it was.
- The plugin cannot repair it. Hyprland's Lua API has nothing that adds a
  software lock. `cursor:no_hardware_cursors` is read in
  `updateCursorBackend()`, which runs on a lock change, a layout change, the
  pointer entering or leaving an output, or a cursor image change
  (`setCursorBuffer` / `setCursorSurface`), so a value changed at runtime
  takes effect at the next hover that swaps the pointer shape, not at once.

## How to confirm

1. `omarchy-magnifier zoom set 5`, then `hyprctl monitors | grep tearingBlockedBy`:
   no `hw cursor` entry. Pointer large and on target.
2. Let the monitor sleep and wake it (or unplug and replug the DP cable), with
   the zoom still at 5. Check that the Hyprland log shows
   `Connector DP-1 disconnected` and `connected`.
3. Move the mouse. Pointer is small and offset. `tearingBlockedBy` now lists
   `hw cursor`. `hardwareCursorsInUse` says `true` in both steps, so ignore it.
4. `omarchy-magnifier zoom off` then `zoom set 5`: unchanged.
5. Add `hl.config({ cursor = { no_hardware_cursors = 1 } })` to the config,
   `hyprctl reload`, hover something that changes the pointer shape: the
   `hw cursor` entry leaves `tearingBlockedBy`, the log stops printing
   `drm: Cursor buffer imported into KMS`, the pointer is correct again and
   stays so across the next sleep. Verified 2026-11-10 at 500% on DP-1.

## Fix options

1. **Config workaround (done 2026-11-10):** `cursor:no_hardware_cursors = 1` in
   `~/.config/hypr/looknfeel.lua`. The pointer is always drawn in software, so
   the lock counter no longer matters. Costs: the pointer is part of the frame
   at 100% too (no visible difference on a 144 Hz monitor), and direct scanout
   is blocked by the software pointer, which on this machine it already was by
   `user settings`. Tearing was never in use.
2. **Plugin:** the install script and README recommend option 1 whenever
   Hyprland is at or below the affected version. The plugin cannot do more from
   Lua (see above).
3. **Upstream:** make the zoom lock per monitor and idempotent. In
   `renderMonitor`, replace the static `zoomLock` with a flag on the monitor and
   use `lockSoftwareForMonitor(pMonitor)` / `unlockSoftwareForMonitor(pMonitor)`:

   ```cpp
   if (pMonitor->m_zoomSwLocked && ZOOMFACTOR == 1.f) {
       Pointer::mgr()->unlockSoftwareForMonitor(pMonitor);
       pMonitor->m_zoomSwLocked = false;
   } else if (!pMonitor->m_zoomSwLocked && ZOOMFACTOR != 1.f) {
       Pointer::mgr()->lockSoftwareForMonitor(pMonitor);
       pMonitor->m_zoomSwLocked = true;
   }
   ```

   A new monitor then takes its own lock on its first zoomed frame. Also clamp
   `unlockSoftwareAll()` at zero the way `unlockSoftwareForMonitor()` already
   does, and make `hardwareCursorsInUse` in `hyprctl monitors` report
   `hasVisibleHWCursor()` rather than the config value.

Recommendation: 1 now, 2 in the next release, file 3 against hyprwm/Hyprland
with this write-up and link it here.
