# Contributing

Thanks for taking an interest. This plugin exists so low-vision users of Omarchy get a magnifier that works on one monitor and on many. Bug reports, accessibility feedback and pull requests are all welcome.

## Reporting a problem

Open an issue on GitHub with:

- your Omarchy version (`omarchy version`) and Hyprland version (`hyprctl version | head -1`),
- your monitor layout (`hyprctl monitors -j | jq -c '.[] | {name,width,height,scale,x,y}'`),
- the `omarchy_magnifier` block from your `hyprland.lua`,
- the output of the troubleshooting commands in the README's "Something does not work" section.

Reports written up inside the repo, with the steps for saving Hyprland's log and `hyprctl configerrors`
before a reboot wipes them, live in [docs/bug-reports/](docs/bug-reports/README.md).

## Running from a checkout

The plugin is loaded from wherever its folder lives, so a development checkout can replace the marketplace copy without any build step.

```bash
git clone https://github.com/JPDoesDev/omarchy-magnifier
cd omarchy-magnifier
ln -s "$PWD" ~/.config/omarchy/plugins/jpdoesdev.magnifier
./install.sh
```

`install.sh` writes the loader line with the checkout's path, so `hyprctl reload` picks up every edit to the Lua files. Edits to `ZoomOsd.qml` or `ZoomOsdModel.js` need `omarchy restart shell`.

Note that `omarchy plugin validate` refuses symlinks, so validate the checkout directory itself: `omarchy plugin validate .`

## Tests

```bash
tests/run
omarchy plugin validate .
```

Both must pass before a pull request. [docs/TESTING.md](docs/TESTING.md) describes what the automated tests cover and lists the manual checks done on a live desktop before each release. If your change touches something the automated tests cannot reach, say in the pull request which manual rows you ran.

## Style

- Bash: `#!/bin/bash`, `set -euo pipefail`, two-space indent, `[[ ]]` and `(( ))`, no `sudo`. Scripts must stay safe to run twice.
- Lua: two-space indent, every setting optional with a default, no machine-specific values in the code.
- QML and JavaScript: layout math goes in `ZoomOsdModel.js` so it stays testable with Node.
- Settings are documented in the README table in the same commit that adds them.
- Changes go in `CHANGELOG.md` under "Unreleased" in [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) form.

## Releases

Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). A release bumps `version` in `manifest.json`, turns the "Unreleased" section of the changelog into a dated section, and tags the commit `vX.Y.Z`.
