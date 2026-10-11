#!/bin/bash
# Shared helpers for the Magnifier plugin tests. Source it; do not run it.
#
# Output follows Omarchy's test/shell.d protocol: one "ok - ..." line per
# check, "not ok - ..." on stderr and exit 1 at the first failure,
# "ok - ... # SKIP" for a check that could not run here.

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "source tests/base.sh from a test; do not run it directly" >&2
  exit 1
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export ROOT

pass() {
  printf 'ok - %s\n' "$1"
}

skip() {
  printf 'ok - %s # SKIP\n' "$1"
}

fail() {
  local description="$1"
  local detail="${2:-}"

  [[ -n $detail ]] && printf '%s\n' "$detail" >&2
  printf 'not ok - %s\n' "$description" >&2
  exit 1
}

require_command() {
  local command="$1"

  command -v "$command" >/dev/null || fail "required command is available: $command"
}

# Point HOME, XDG_RUNTIME_DIR and XDG_STATE_HOME at a throwaway directory so
# the plugin never reads or writes a real file, and put a stub
# omarchy-hyprland-reload-guard first on PATH. The stub reports "paused" only
# while $MAG_TEST_TMP/guard-paused exists (default: not paused, exit 1).
scratch_env() {
  MAG_TEST_TMP=$(mktemp -d)
  trap 'rm -rf "$MAG_TEST_TMP"' EXIT
  mkdir -p "$MAG_TEST_TMP/home" "$MAG_TEST_TMP/runtime" "$MAG_TEST_TMP/state" "$MAG_TEST_TMP/bin"

  cat > "$MAG_TEST_TMP/bin/omarchy-hyprland-reload-guard" <<SH
#!/bin/bash
[[ \$1 == paused ]] || exit 1
[[ -e "$MAG_TEST_TMP/guard-paused" ]]
SH
  chmod +x "$MAG_TEST_TMP/bin/omarchy-hyprland-reload-guard"

  export MAG_TEST_TMP
  export HOME="$MAG_TEST_TMP/home"
  export XDG_RUNTIME_DIR="$MAG_TEST_TMP/runtime"
  export XDG_STATE_HOME="$MAG_TEST_TMP/state"
  export PATH="$MAG_TEST_TMP/bin:$PATH"
}

# Run a Lua test body from stdin with tests/hl-stub.lua bound as `stub`.
# The body reports through stub.check / stub.eq, which print the ok /
# not ok lines and exit 1 on the first failure; that status is returned, so
# a test that ends with run_lua_test exits with it.
run_lua_test() {
  require_command "${LUA:-lua}"

  {
    printf 'local stub = dofile(os.getenv("ROOT") .. "/tests/hl-stub.lua")\n'
    cat
  } | "${LUA:-lua}" -
}
