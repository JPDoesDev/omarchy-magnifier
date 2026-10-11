#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base.sh"

require_command "${LUAC:-luac}"

shopt -s nullglob
files=("$ROOT"/hypr/*.lua)
(( ${#files[@]} > 0 )) || fail "hypr/ contains Lua files to check"

for file in "${files[@]}"; do
  output=$("${LUAC:-luac}" -p "$file" 2>&1) || fail "$(basename "$file") compiles with luac -p" "$output"
  pass "$(basename "$file") compiles with luac -p"
done

for name in init magnifier jump screenfx lock; do
  [[ -f $ROOT/hypr/$name.lua ]] || fail "hypr/$name.lua exists"
done
pass "all five plugin modules are present"
