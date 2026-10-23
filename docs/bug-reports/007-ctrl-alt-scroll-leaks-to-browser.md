# 007: Ctrl + Alt + scroll in a browser also zooms the page

GitHub issue: https://github.com/JPDoesDev/omarchy-magnifier/issues/7

Filed 2026-10-23 from the user's own observation (desktop, Razer DeathAdder Essential). Status: fixed 2026-10-23, unreleased with fix option 1: the plugin sets `binds:scroll_event_delay = 0` whenever a wheel chord is bound, behind the new `wheel_every_notch` setting (default on), with tests in `settings-test.sh`. Confirmed by test the same day: with the delay at 0 the page zoom no longer moves. Option 3 (upstream report) still to file.

## Symptom

In a web browser, `CTRL + ALT + scroll` zooms the magnifier as intended, but the
page also zooms in or out as if plain `CTRL + scroll` had been pressed. The page
zoom is unintentional and has to be undone with `CTRL + 0` afterwards. The
same thing will happen in any app that treats `CTRL + wheel` as zoom (editors,
image viewers, terminals that resize the font).

It is most visible when scrolling several notches in a row; a single slow notch
usually does not leak.

## Why it happens

Hyprland throttles wheel binds with `binds:scroll_event_delay` (default 300 ms,
not overridden on this machine). In `CKeybindManager::onAxisEvent`
(Hyprland 0.56.2, `src/managers/KeybindManager.cpp`):

- If less than `scroll_event_delay` has passed since the last wheel event that
  was dispatched to binds, the function returns `true` straight away
  (`// timer hasn't passed yet!`) without looking at the binds at all.
- `CInputManager::onMouseWheel` treats `true` as "pass the event to the client"
  and calls `sendPointerAxis`, so the notch reaches the focused window.
- The modifiers are still physically held, so the browser sees `CTRL + wheel`
  and zooms the page. Our bind on `CTRL + ALT + mouse_up` is never consulted
  for that notch.
- Only the first notch after a 300 ms quiet period is matched against binds
  and swallowed. The timer is not reset inside the throttled branch, so with
  continuous scrolling the pattern is: notch 1 to the magnifier, every notch
  in the next 300 ms to the browser, then the next notch to the magnifier
  again.

The plugin cannot intercept this from Lua: the event is passed before any bind
is evaluated. `non_consuming` and `transparent` bind options do not apply
because no bind is reached.

The keyboard chords (`CTRL + ALT + =` and `CTRL + ALT + -`, since 1.1.0) are not
affected and are the workaround today.

## How to confirm

1. Open a browser page, note the page zoom (`CTRL + 0` first).
2. One notch of `CTRL + ALT + scroll up`, wait a second, repeat three times:
   magnifier steps, page zoom unchanged.
3. Three fast notches: magnifier steps once, page zoom changes.
4. Add `binds:scroll_event_delay = 0` to the Hyprland config, `hyprctl reload`,
   repeat step 3: every notch goes to the magnifier, page zoom unchanged.

## Fix options

1. **Set `binds:scroll_event_delay = 0` from the plugin** when the wheel chords
   are bound, with a setting to leave it alone. Every wheel notch is then
   matched against binds. Side effect: Omarchy's own `SUPER + scroll`
   workspace cycling, `SUPER + ALT + scroll` group cycling and the desktops
   module's `SUPER + scroll` fire on every notch instead of at most every
   300 ms. For a magnifier user that is arguably correct, but it is a global
   change and the README has to say so.
2. **Document it only**: README troubleshooting entry telling the user to set
   `binds:scroll_event_delay = 0` (or a value below their wheel's notch
   interval) in `~/.config/hypr/hyprland.lua`. Least surprising, but the
   default install stays broken in browsers.
3. **Upstream**: ask Hyprland to swallow throttled wheel events when a bind
   exists for the current modifier mask and direction, instead of passing them
   through. That is the real fix; the throttle predates modifier-wheel binds
   being common. File against hyprwm/Hyprland and link here.

Recommendation: do 1 with an opt-out, note the side effect, and file 3.
