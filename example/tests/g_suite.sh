#!/bin/sh
# g_suite.sh — the replay suite is GREEN on a registered build. The build dir
# is the argument (the sweep passes %BUILD_A%); default roms/build-a. ~3 s.
#
# Usage: FAKE_ROOT=. tests/g_suite.sh [roms/build-a]
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO"
BBH_HOME="${BBH_HOME:-$(cd "$REPO/.." && pwd)}"
BUILD="${1:-roms/build-a}"
FAKE_ROOT="${FAKE_ROOT:-$REPO}"; export FAKE_ROOT
out="$(FAKE_ROMPATH="$BUILD" "$BBH_HOME/bin/bbh" run-suite --config "$REPO/bbh.toml" 2>&1)" && st=0 || st=$?
printf '%s\n' "$out"
[ "$st" = 0 ] && printf '%s\n' "$out" | grep -q "^SUITE GREEN$" && echo "PASS: SUITE GREEN on $BUILD" || { echo "FAIL: the suite is not green on $BUILD"; exit 1; }
