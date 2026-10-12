# Magnifier plugin: feature verification checklist

Legend: [x] verified (by script, or by hand on the desktop on 2026-10-10, pinch on the laptop on 2026-10-11), [ ] not yet verified; many need a second monitor or the laptop touchpad. Expected results assume the desktop settings (preset 6, step 2, side buttons on, high-contrast popup).

## 1. Zoom keys and buttons (single monitor is enough)

| # | Do this | Expect | Status |
|---|---|---|---|
| 1.1 | Ctrl + Alt + scroll up, three notches | 300%, 500%, 700%; popup shows each value beside the pointer | [x] |
| 1.2 | Ctrl + Alt + scroll down, back down | steps of 200% down to 100%, popup each time | [x] |
| 1.3 | Keep scrolling up past 900% | stops at 1000%, never higher | [x] |
| 1.4 | Keep scrolling down past 100% | stays at 100%, never below | [x] |
| 1.5 | Ctrl + Alt + Z | jumps straight to 600% | [x] |
| 1.6 | Ctrl + Alt + X | back to 100% | [x] |
| 1.7 | Super + front side button (mouse:276) | 600% | [x] |
| 1.8 | Super + back side button (mouse:275) | 100% | [x] |
| 1.9 | Super + Ctrl + Z (Omarchy's own key) | zoom +100% as before, and the new level is kept across a reload | [x] |
| 1.10 | Super + Ctrl + Alt + Z (Omarchy reset) | 100% | [x] |
| 1.11 | Super + K | the nine Magnifier entries are listed with descriptions | [x] |
| 1.12 | `omarchy-magnifier zoom set 3`, `in`, `out`, `toggle`, `off`, `status` | each does what it says; status prints the factor | [x] |

## 2. Popup (OSD)

| # | Do this | Expect | Status |
|---|---|---|---|
| 2.1 | Any zoom change | black card, white bold percentage, yellow border, to the right of the pointer, gone after 1.2 s | [x] rendered via IPC |
| 2.2 | Zoom at 700% or more | card stays readable and small, not blown up to a quarter of the screen | [x] |
| 2.3 | Pointer near the right edge, then zoom | card flips to the left of the pointer | [x] |
| 2.4 | Pointer near the top or bottom edge, then zoom | card stays fully on screen | [x] |
| 2.5 | Click where the card is while it shows | click reaches the window underneath | [x] |
| 2.6 | Remove the osd_style colours from the block, `hyprctl reload`, zoom | card uses the theme colours (on another theme they differ from black/white/yellow) | [x] |
| 2.7 | `omarchy-shell magnifier ping` | `ok` | [x] |

## 3. Zoom survives reloads

| # | Do this | Expect | Status |
|---|---|---|---|
| 3.1 | Zoom to 300%, run `hyprctl reload` | still 300%, no popup | [x] |
| 3.2 | Zoom to 300%, change theme with Super + Ctrl + Shift + Space | still 300% after the theme applies | [x] |
| 3.3 | Zoom to 300%, run `omarchy restart shell` | still 300%; popup works again afterwards | [x] |
| 3.4 | Reboot | starts at 100% (runtime state is cleared on purpose) | [x] |

## 4. Pinch (touchpad only, laptop)

| # | Do this | Expect | Status |
|---|---|---|---|
| 4.1 | Hold Super, pinch out on the touchpad | zoom increases smoothly | [x] |
| 4.2 | Pinch far in | settles at 100%, not below; within half a second the saved state matches | [x] |
| 4.3 | Pinch far out | settles at 1000% | [x] |

## 5. Monitor jump (needs two monitors)

| # | Do this | Expect | Status |
|---|---|---|---|
| 5.1 | Zoom to 500% on monitor A, Super + Ctrl + scroll down | pointer and keyboard focus land on B, at its centre on the first visit, zoom 100%, popup shows 100% | [ ] |
| 5.2 | Look at monitor A while on B | A still shows the same 500% view (frozen zoom), video keeps playing in it | [ ] |
| 5.3 | Zoom to 300% on B, move the pointer, jump back | A at 500% at the spot you left; B keeps a frozen 300% view | [ ] |
| 5.4 | Jump again | B at 300% with the pointer where you left it | [ ] |
| 5.5 | Scroll up instead of down | previous monitor; with two monitors both directions wrap | [ ] |
| 5.6 | `omarchy-magnifier status` while one is frozen | lists the frozen output id and zoom | [ ] |
| 5.7 | `omarchy-magnifier unfreeze` | frozen monitor returns to 100% | [ ] |
| 5.8 | Jump with `omarchy-magnifier jump next` / `prev` | same as the keys | [ ] |

## 6. Mouse lock (needs two monitors)

| # | Do this | Expect | Status |
|---|---|---|---|
| 6.1 | Log in with two monitors | pointer cannot cross from one to the other; `omarchy-magnifier lock status` says locked | [ ] |
| 6.2 | `hyprctl monitors -j` | second monitor sits far to the right (x around 20000 plus the first width) | [ ] |
| 6.3 | Super + Ctrl + M | notification "Mouse unlocked", pointer crosses freely, monitors back side by side | [ ] |
| 6.4 | Super + Ctrl + M again | notification "Mouse locked", layout gapped again | [ ] |
| 6.5 | Unlock, drag a window to the other monitor, lock | window stays on the other monitor | [ ] |
| 6.6 | Unplug and replug a monitor (or dock) | re-locks on its own, frozen views dropped, no reload storm (check `journalctl` or just that the screen settles within ten seconds) | [ ] |
| 6.7 | Change SCALE in the Display panel while locked | layout un-gaps; Super + Ctrl + M twice re-locks | [ ] |
| 6.8 | Super + Ctrl + M with one monitor | notification "Mouse lock needs two or more monitors", nothing else changes | [x] |
| 6.9 | `omarchy update` while locked | the update does not reload Hyprland mid-transaction because of the plugin (reload guard honoured) | [ ] |

## 7. Settings

| # | Do this | Expect | Status |
|---|---|---|---|
| 7.1 | Set `step = 1`, `hyprctl reload`, scroll | 100% steps | [ ] |
| 7.2 | Set `keys = { off = false }`, reload | Ctrl + Alt + X does nothing; eight Magnifier binds in Super + K | [x] in tests |
| 7.3 | Set `side_buttons = false`, reload | seven binds; side buttons do nothing | [x] in tests |
| 7.4 | Set `mouse_lock = false` on a locked two-monitor desk, reload | layout un-gaps, pointer free | [x] in tests |
| 7.5 | Put garbage in the table (`step = "fast"`, `osd_style = 5`) | plugin still loads with defaults; no config error | [x] in tests |
| 7.6 | Remove the whole block, reload | all Magnifier binds gone, Omarchy's own zoom keys still work | [ ] |

## 8. Colour inversion

| # | Do this | Expect | Status |
|---|---|---|---|
| 8.1 | Ctrl + Alt + I | every screen inverted at once; OSD says "Colours inverted" | [x] |
| 8.2 | Ctrl + Alt + I again | back to normal; OSD says "Colours normal" | [x] |
| 8.3 | Invert, then `hyprctl reload` | still inverted | [x] |
| 8.4 | Invert, zoom to 300%, scroll around | inverted and magnified together, no flicker or patchwork | [x] |
| 8.5 | Two monitors: invert, magnify A, jump to B | A stays frozen and inverted, B inverted | [ ] two monitors |
| 8.6 | `omarchy-magnifier invert status` and `status` | report inverted / normal | [x] |
| 8.7 | Reboot | starts normal | [x] |
| 8.8 | Set `invert = false`, reload while inverted | colours return to normal and Ctrl + Alt + I does nothing | [x] in tests |

## 9. Install, uninstall, coexistence

| # | Do this | Expect | Status |
|---|---|---|---|
| 9.1 | `install.sh` twice | second run reports everything already present, no duplicate block | [x] |
| 9.2 | `install.sh --uninstall` then `install.sh` | `hyprland.lua` identical to before, plugin back | [x] on a scratch config |
| 9.3 | `omarchy plugin validate ~/.config/omarchy/plugins/jpdoesdev.magnifier` | exit 0 | [x] |
| 9.4 | Install the community per-window invert plugin while a monitor is frozen | one notification that another shader is active; the plugin's invert and frozen zoom step aside | [ ] optional |
| 9.5 | Per-monitor desktops (Super + Ctrl + Shift + scroll) | still send a desktop across with pointer and focus, zoom reset on arrival | [ ] two monitors |
| 9.6 | `tests/run` in the checkout | 7 files pass | [x] |
