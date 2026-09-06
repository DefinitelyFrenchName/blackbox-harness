#!/bin/sh
# g_fields.sh — the DUAL-IMPLEMENTATION protocol on the fake machine: the
# base image and the hooked build agree on every mapped field at the
# match-start anchor and after it, and differ frame-exact on the hook's
# phase field (the must-fire: --exact must fail). Reaches the driver. ~2 s.
#
# Usage: FAKE_ROOT=. tests/g_fields.sh [roms/build-a]
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO"
BBH_HOME="${BBH_HOME:-$(cd "$REPO/.." && pwd)}"
BUILD="${1:-roms/build-a}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT INT TERM
printf '100 sys=C1\n200 sys=S1\n450 p1=1\n600 wait\n' > "$W/match.rpl"   # match at 400; a press at +50
SPEC="$(python3 -c "print(';'.join(f'{f}:0100-0110;{f}:0400-0404;{f}:0058-005e;{f}:0700-0702' for f in range(380, 521)))")"
mkdir -p "$W/base" "$W/build"
DUMPS="$SPEC" FAKE_ROMPATH=roms/base "$BBH_HOME/drivers/fake.sh" fake "$W/match.rpl" "$W/base/out.log" "$W/b1" > /dev/null
DUMPS="$SPEC" FAKE_ROMPATH="$BUILD" "$BBH_HOME/drivers/fake.sh" fake "$W/match.rpl" "$W/build/out.log" "$W/b2" > /dev/null
"$BBH_HOME/bin/bbh" check-dumps "$W/base" --config bbh.toml --first 380 --last 520 --quiet || { echo "FAIL: the base dump set is incomplete"; exit 1; }
"$BBH_HOME/bin/bbh" check-dumps "$W/build" --config bbh.toml --first 380 --last 520 --quiet || { echo "FAIL: the build dump set is incomplete"; exit 1; }
"$BBH_HOME/bin/bbh" compare-fields "$W/base" "$W/build" --config bbh.toml --follow 0,30,60 --label-a base --label-b build \
    || { echo "FAIL: base and $BUILD disagree at the anchors"; exit 1; }
if "$BBH_HOME/bin/bbh" compare-fields "$W/base" "$W/build" --config bbh.toml --exact --label-a base --label-b build > "$W/exact.out" 2>&1; then
    echo "FAIL: --exact agreed — the hook's late byte should differ frame-exact (the must-fire is dead)"; exit 1
fi
grep -q '^MISMATCH frame 450 late ' "$W/exact.out" || { echo "FAIL: --exact failed for another reason:"; cat "$W/exact.out"; exit 1; }
echo "PASS: base and $BUILD agree at the anchor and +30/+60; --exact disagrees on the phase field at frame 450 (the control fired)"
