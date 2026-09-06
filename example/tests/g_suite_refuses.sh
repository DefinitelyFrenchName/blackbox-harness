#!/bin/sh
# g_suite_refuses.sh — the suite REFUSES an unregistered image loudly: the
# must-fire control of fingerprint dispatch. The image dir is the argument
# (the sweep passes %HOOK%); default roms/hook. ~1 s.
#
# Usage: FAKE_ROOT=. tests/g_suite_refuses.sh [roms/hook]
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO"
BBH_HOME="${BBH_HOME:-$(cd "$REPO/.." && pwd)}"
BUILD="${1:-roms/hook}"
FAKE_ROOT="${FAKE_ROOT:-$REPO}"; export FAKE_ROOT
out="$(FAKE_ROMPATH="$BUILD" "$BBH_HOME/bin/bbh" run-suite --config "$REPO/bbh.toml" 2>&1)" && st=0 || st=$?
[ "$st" = 1 ] && printf '%s\n' "$out" | grep -q "^unregistered build fingerprint" && echo "PASS: $BUILD refused (exit 1, named)" \
    || { printf '%s\n' "$out"; echo "FAIL: $BUILD was not refused (exit $st)"; exit 1; }
