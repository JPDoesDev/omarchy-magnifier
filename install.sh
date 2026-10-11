#!/bin/bash

# Wire the Magnifier plugin into the live Omarchy session, or take it out again.
#
#   install.sh              add the settings block + loader line to ~/.config/hypr/hyprland.lua,
#                           link the CLI into ~/.local/bin, enable the popup plugin, reload
#   install.sh --uninstall  reverse all of that and remove the plugin's runtime files
#
# Safe to run again: every step checks before it changes anything. No sudo.
# `omarchy plugin add` only clones the repo; the Hyprland side has to be loaded
# from hyprland.lua, which is the one line this script owns.

set -euo pipefail

PLUGIN_ID="jpdoesdev.magnifier"
PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
HYPR_MAIN="$HYPR_DIR/hyprland.lua"
PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
BIN_DIR="$HOME/.local/bin"
CLI_LINK="$BIN_DIR/omarchy-magnifier"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
LOCK_FLAG="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/toggles/hypr/magnifier-mouse-lock.lua"
BEGIN_MARK="-- >>> omarchy-magnifier >>>"
END_MARK="-- <<< omarchy-magnifier <<<"

# Written as a HOME-relative expression when the checkout is under HOME, so the
# config stays portable between machines that share dotfiles.
loader_path() {
  if [[ $PLUGIN_DIR == "$HOME"/* ]]; then
    printf 'os.getenv("HOME") .. "%s"' "${PLUGIN_DIR#"$HOME"}/hypr/init.lua"
  else
    printf '"%s"' "$PLUGIN_DIR/hypr/init.lua"
  fi
}

config_block() {
  cat <<BLOCK
$BEGIN_MARK
-- Magnifier plugin. Settings go in this table; every key is optional and the
-- README lists them all. Remove the whole block (or run install.sh --uninstall)
-- to switch the plugin off.
omarchy_magnifier = {
  -- preset_zoom = 3,   -- CTRL + ALT + Z jumps here (3 = 300%)
  -- step = 1,          -- change per CTRL + ALT + scroll notch
  -- side_buttons = false,
  -- invert = true,       -- CTRL + ALT + I inverts the colours
  -- osd_style = { background = "#000000", text = "#ffffff", border = "#ffff00" },
}
dofile($(loader_path))
$END_MARK
BLOCK
}

say() {
  echo "omarchy-magnifier: $*"
}

die() {
  echo "omarchy-magnifier: $*" >&2
  exit 1
}

in_session() {
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && hyprctl version >/dev/null 2>&1
}

shell_running() {
  omarchy-shell shell ping >/dev/null 2>&1
}

has_block() {
  [[ -f $HYPR_MAIN ]] && grep -Fq -- "$BEGIN_MARK" "$HYPR_MAIN"
}

remove_block() {
  local tmp
  tmp=$(mktemp)
  # Drop the block and one blank line directly above it, if there is one.
  awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
    $0 == begin { skipping = 1; held = 0; next }
    $0 == end { skipping = 0; next }
    skipping { next }
    /^$/ { if (held) print ""; held = 1; next }
    { if (held) print ""; held = 0; print }
    END { if (held) print "" }
  ' "$HYPR_MAIN" >"$tmp"
  cat "$tmp" >"$HYPR_MAIN"
  rm -f "$tmp"
}

install() {
  [[ -f $PLUGIN_DIR/hypr/init.lua && -f $PLUGIN_DIR/manifest.json ]] || die "run this from the plugin checkout; hypr/init.lua not found next to $0"
  if [[ ! -f $HYPR_MAIN ]]; then
    die "$HYPR_MAIN not found. This plugin needs Omarchy 4 with the Lua Hyprland config."
  fi
  if ! grep -Fq 'require("default.hypr.omarchy")' "$HYPR_MAIN"; then
    say "warning: $HYPR_MAIN does not look like an Omarchy config; continuing anyway"
  fi

  if has_block; then
    say "loader already present in $HYPR_MAIN"
  else
    printf '\n%s\n' "$(config_block)" >>"$HYPR_MAIN"
    say "added the settings block and loader to $HYPR_MAIN"
  fi

  # The shell only discovers plugins under ~/.config/omarchy/plugins. A checkout
  # elsewhere (development, or a dotfiles tree) is linked in by its id.
  if [[ $PLUGIN_DIR != "$PLUGINS_DIR"/* ]]; then
    mkdir -p "$PLUGINS_DIR"
    if [[ -L $PLUGINS_DIR/$PLUGIN_ID && $(readlink -f "$PLUGINS_DIR/$PLUGIN_ID") == "$PLUGIN_DIR" ]]; then
      say "plugin already linked at $PLUGINS_DIR/$PLUGIN_ID"
    elif [[ -e $PLUGINS_DIR/$PLUGIN_ID ]]; then
      say "warning: $PLUGINS_DIR/$PLUGIN_ID exists and is not this checkout; the popup will load from there"
    else
      ln -s "$PLUGIN_DIR" "$PLUGINS_DIR/$PLUGIN_ID"
      say "linked this checkout at $PLUGINS_DIR/$PLUGIN_ID"
    fi
  fi

  mkdir -p "$BIN_DIR"
  if [[ -L $CLI_LINK && $(readlink -f "$CLI_LINK") == "$PLUGIN_DIR/bin/omarchy-magnifier" ]]; then
    say "CLI already linked at $CLI_LINK"
  elif [[ -e $CLI_LINK ]]; then
    say "warning: $CLI_LINK exists and is not ours; leaving it alone"
  else
    ln -s "$PLUGIN_DIR/bin/omarchy-magnifier" "$CLI_LINK"
    say "linked the CLI at $CLI_LINK"
  fi
  chmod +x "$PLUGIN_DIR/bin/omarchy-magnifier"

  if ! in_session; then
    say "no Hyprland session: the plugin loads at your next login"
    return 0
  fi

  if shell_running; then
    omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true
    if omarchy-shell shell listPlugins 2>/dev/null | jq -e --arg id "$PLUGIN_ID" 'any(.[]?; .id == $id and .enabled == true)' >/dev/null 2>&1; then
      say "popup plugin already enabled"
    else
      omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1 && say "enabled the popup plugin" || say "warning: could not enable $PLUGIN_ID; run: omarchy plugin enable $PLUGIN_ID"
    fi
  else
    say "warning: omarchy-shell is not running; enable the popup later with: omarchy plugin enable $PLUGIN_ID"
  fi

  hyprctl reload >/dev/null 2>&1 || true
  sleep 1
  local errors
  errors=$(hyprctl configerrors 2>/dev/null | grep -v '^[[:space:]]*$' || true)
  if [[ -n $errors ]]; then
    die "Hyprland reported config errors after loading the plugin: $errors"
  fi
  if hyprctl binds 2>/dev/null | grep -q "Magnifier zoom in"; then
    say "Hyprland bindings are active"
  else
    say "warning: magnifier bindings not found in hyprctl binds; check $HYPR_MAIN"
  fi
  if shell_running; then
    local i
    for i in 1 2 3 4 5; do
      omarchy-shell magnifier ping >/dev/null 2>&1 && break
      sleep 1
    done
    if omarchy-shell magnifier ping >/dev/null 2>&1; then
      say "popup is responding"
    else
      say "warning: the popup is not answering yet; try: omarchy restart shell"
    fi
  fi
  say "done. Try CTRL + ALT + scroll, or: omarchy-magnifier zoom toggle"
}

uninstall() {
  if has_block; then
    remove_block
    say "removed the settings block and loader from $HYPR_MAIN"
  else
    say "no loader block in $HYPR_MAIN"
  fi

  if [[ -L $CLI_LINK && $(readlink -f "$CLI_LINK") == "$PLUGIN_DIR/bin/omarchy-magnifier" ]]; then
    rm -f "$CLI_LINK"
    say "removed $CLI_LINK"
  fi
  if [[ -L $PLUGINS_DIR/$PLUGIN_ID && $(readlink -f "$PLUGINS_DIR/$PLUGIN_ID") == "$PLUGIN_DIR" ]]; then
    rm -f "$PLUGINS_DIR/$PLUGIN_ID"
    say "removed the plugin link at $PLUGINS_DIR/$PLUGIN_ID"
  fi

  rm -f "$LOCK_FLAG" "$RUNTIME"/omarchy-magnifier-state "$RUNTIME"/omarchy-magnifier-frozen \
    "$RUNTIME"/omarchy-magnifier.frag "$RUNTIME"/omarchy-magnifier-unlocked

  if in_session; then
    if shell_running; then
      omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
    fi
    hyprctl keyword cursor:zoom_factor 1 >/dev/null 2>&1 || true
    hyprctl reload >/dev/null 2>&1 || true
  fi
  say "uninstalled. Remove the files with: omarchy plugin remove $PLUGIN_ID"
}

case ${1:-} in
  "" | --install) install ;;
  --uninstall | uninstall) uninstall ;;
  -h | --help)
    sed -n '3,11p' "$0"
    ;;
  *)
    die "unknown option: $1 (use --uninstall or --help)"
    ;;
esac
