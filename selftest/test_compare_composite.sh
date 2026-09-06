#!/bin/sh
# test_compare_composite.sh — ground truth for the composite class (v4: frozen
# flicker inventory + frozen bounded windows). Synthetic, no emulator, ~2 s.
# Lineage: VampireSaved's tests/test_compare_composite.sh, verbatim cases:
#
#   1. exactly the frozen shape                     -> PASS
#   2. an EXTRA flicker frame                       -> FAIL (inventory grew)
#   3. a MISSING flicker frame                      -> FAIL (drift either way)
#   4. a window that starts one frame late          -> FAIL (onset is frozen)
#   5. a window that never re-converges             -> FAIL (the whole point)
#   6. bit-identical logs                           -> FAIL (asserts existence)
#   7. a second, unfrozen window appearing          -> FAIL (nothing extra)
# plus the truncation cases, the inventory cap, the inter-run flag both
# ways, and the no-loophole check.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fail=0

python3 - "$WORK" <<'PY'
import sys
work = sys.argv[1]
N = 4000
def write(path, diverge):
    lines = [f"{f} {'%016x' % (0xdeadbeef if f in diverge else f)}" for f in range(1, N + 1)]
    open(f"{work}/{path}", "w").write("\n".join(lines + [f"END {N}"]))
base = set()
shape = {829, 2093} | set(range(890, 1803))
write("base.log", base)
write("ok.log", shape)
write("extra_flicker.log", shape | {3100})
write("missing_flicker.log", shape - {2093})
write("late_onset.log", ({829, 2093} | set(range(891, 1803))))
write("no_reconverge.log", ({829, 2093} | set(range(890, N + 1))))
write("identical.log", base)
write("second_window.log", shape | set(range(3000, 3200)))
write("latebreak.log", shape | set(range(3000, N + 1)))
src = open(f"{work}/ok.log").read().splitlines()
open(f"{work}/trunc.log", "w").write("\n".join(src[:2200]) + "\nEND 2200\n")
lb = open(f"{work}/latebreak.log").read().splitlines()
open(f"{work}/latebreak_trunc.log", "w").write("\n".join(lb[:2500]) + "\nEND 2500\n")
write("bigflicker.log", set(range(1, 21, 2)) | set(range(890, 1803)))
write("closeflicker.log", {829, 885, 2093} | set(range(945, 1858)))
PY

check() {  # check <file> <expect pass|fail> <description>
    if python3 -m bbh.compare_composite "$WORK/base.log" "$WORK/$1" \
            --flicker 829,2093 --windows 890-1802 > "$WORK/$1.out" 2>&1; then got=pass; else got=fail; fi
    if [ "$got" = "$2" ]; then echo "  ok: $3 -> $got"
    else echo "  FAIL: $3 -> $got (expected $2)"; sed 's/^/        /' "$WORK/$1.out"; fail=1; fi
}

echo "== ground truth for the composite comparison class =="
check ok.log              pass "exactly the frozen shape"
check extra_flicker.log   fail "an extra flicker frame appears"
check missing_flicker.log fail "a frozen flicker frame disappears"
check late_onset.log      fail "the window onset moves by one frame"
check no_reconverge.log   fail "the window never re-converges"
check identical.log       fail "the logs are bit-identical"
check second_window.log   fail "an unfrozen second window appears"
check trunc.log           fail "a truncated log is not prefix-compared"
check latebreak.log       fail "a permanent break after the frozen shape"
check latebreak_trunc.log fail "truncating before that break does not rescue it"

if python3 -m bbh.compare_composite "$WORK/base.log" "$WORK/bigflicker.log" \
        --flicker 1,3,5,7,9,11,13,15,17,19 --windows 890-1802 >"$WORK/big.out" 2>&1; then
    echo "  FAIL: a 10-frame flicker inventory passed the max-total cap"; fail=1
else echo "  ok: an over-cap flicker inventory is rejected (max-total)"; fi

if python3 -m bbh.compare_composite "$WORK/base.log" "$WORK/closeflicker.log" \
        --flicker 829,885,2093 --windows 945-1857 >"$WORK/cf1.out" 2>&1; then
    echo "  ok: a 55-frame flicker gap passes by DEFAULT (the inter-run rule is policy, off)"
else echo "  FAIL: the default is now stricter — this would red frozen specs"; fail=1; fi
if python3 -m bbh.compare_composite "$WORK/base.log" "$WORK/closeflicker.log" \
        --flicker 829,885,2093 --windows 945-1857 --min-converge-flicker 60 >"$WORK/cf2.out" 2>&1; then
    echo "  FAIL: --min-converge-flicker 60 accepted a 55-frame gap — the flag does nothing"; fail=1
else echo "  ok: --min-converge-flicker 60 rejects a 55-frame gap when asked"; fi

if python3 -m bbh.compare_composite "$WORK/base.log" "$WORK/ok.log" \
        --flicker 829,2093 --windows - > "$WORK/nowin.out" 2>&1; then
    echo "  FAIL: a long run passed while the window list was empty"; fail=1
else echo "  ok: with no windows frozen, a long run is rejected (not a loophole)"; fi

[ "$fail" = 0 ] || { echo "FAIL: composite class ground truth"; exit 1; }
echo "PASS: composite class ground truth (7 cases + truncation + cap + no-loophole)"
