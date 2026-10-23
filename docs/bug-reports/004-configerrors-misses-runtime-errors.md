# 004: `hyprctl configerrors` never shows runtime Lua errors and keeps stale `hyprctl eval` errors

GitHub issue: https://github.com/JPDoesDev/omarchy-magnifier/issues/4

Filed 2026-10-23. Status: open. Documentation and CLI issue, verified in `CConfigManager::addError`, `eval` and `verify` at v0.56.2.

## What happens

- Errors raised inside keybind, event and timer callbacks go straight to a
  5 second "Runtime error in lua" notification and are never added to the
  error list. `hyprctl configerrors` stays empty while the user is looking at
  a banner. The README's "Something does not work" section tells people to run
  `hyprctl configerrors` first and treats an empty result as "config is fine";
  for the banners in report 001 that is misleading.
- `eval()` clears the error list when it starts and only clears it again when
  the call produced no errors. After a failed `hyprctl eval` (for example a
  typo in `omarchy-magnifier zoom set`'s generated Lua, or a watchdog timeout
  in `OmarchyMagnifier.jump()`), the errors stay in the list, so
  `hyprctl configerrors` reports them until the next reload even though the
  config itself is fine. Running `hyprctl reload` to "fix" that is harmless but
  confusing, and it re-arms every plugin timer (report 002).

## Fix

- README "Something does not work": say that a yellow "Runtime error in lua"
  banner is not in `configerrors`; the text is only in Hyprland's log
  (`grep -i "runtime error\|timed out\|error in" "$XDG_RUNTIME_DIR"/hypr/*/hyprland.log`)
  and only until reboot. Point at `docs/bug-reports/README.md` for the capture
  steps.
- `bin/omarchy-magnifier`: after a failed `eval_lua`, print the error (it
  already does) and add a hint that `hyprctl configerrors` will repeat it
  until the next reload.
- Consider an `omarchy-magnifier doctor` subcommand that collects
  `configerrors`, the runtime-dir state files, the shader, the tail of the
  Hyprland log and the magnifier lines of the shell journal into one folder.
  That is the capture script from `README.md` here, made permanent.
