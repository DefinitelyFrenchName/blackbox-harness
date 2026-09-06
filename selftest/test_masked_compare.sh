#!/bin/sh
# test_masked_compare.sh — ground truth for lib/sh/masked_compare.sh, the ONE
# implementation of the masked comparison vocabulary: every class in BOTH
# directions, the baseset/mask guard, the unknown class, the mask default
# from config. No emulator, ~3 s. Lineage: VampireSaved's
# tests/test_masked_compare.sh, verbatim cases (it caught a real bug in the
# original lift: the diverge spec's temp-file STEM).
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
. "$BBH_HOME/lib/sh/masked_compare.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0

MASKSTR="043c-043d,7f00-8000"
ROOT="$W/expected"
mkdir -p "$ROOT/basis/logs" "$ROOT/theset"
printf '%s\n' "$MASKSTR" > "$ROOT/basis/MASK"
printf '%s\n' "$MASKSTR" > "$ROOT/theset/mask"

mk() {   # mk <file> <divergent frames...> — 400 frames
    _f="$1"; shift; _d=" $* "; i=1; : > "$_f"
    while [ "$i" -le 400 ]; do
        case "$_d" in *" $i "*) printf '%d %s\n' "$i" "ffffffffffffffff" >> "$_f" ;; *) printf '%d %s\n' "$i" "0000000000000000" >> "$_f" ;; esac
        i=$((i + 1))
    done
    echo "END 400" >> "$_f"
}
mkrange() {   # mkrange <file> <lo> <hi> [extra frames...]
    _f="$1"; _lo="$2"; _hi="$3"; shift 3; _x=" $* "; i=1; : > "$_f"
    while [ "$i" -le 400 ]; do
        if [ "$i" -ge "$_lo" ] && [ "$i" -le "$_hi" ]; then printf '%d %s\n' "$i" "ffffffffffffffff" >> "$_f"
        else case "$_x" in *" $i "*) printf '%d %s\n' "$i" "ffffffffffffffff" >> "$_f" ;; *) printf '%d %s\n' "$i" "0000000000000000" >> "$_f" ;; esac; fi
        i=$((i + 1))
    done
    echo "END 400" >> "$_f"
}

check() {  # check <label> <want-rc> <name> <spec> <runmask> <log> [want-substring]
    _l="$1"; _w="$2"; _n="$3"; _s="$4"; _m="$5"; _lg="$6"; _want="${7:-}"
    if out=$(masked_check "$ROOT/theset" "$_n" "$_s" "$_m" "$_lg" 2>&1); then _rc=0; else _rc=$?; fi
    if [ "$_rc" != "$_w" ]; then echo "  FAIL  $_l (rc=$_rc want $_w)"; printf '%s\n' "$out" | sed 's/^/        /'; fail=1; return; fi
    if [ -n "$_want" ] && ! printf '%s' "$out" | grep -q "$_want"; then echo "  FAIL  $_l (rc ok, but the verdict did not mention '$_want')"; printf '%s\n' "$out" | sed 's/^/        /'; fail=1; return; fi
    echo "  PASS  $_l"
}

mk       "$ROOT/basis/logs/case.log"
mk       "$W/same"
mk       "$W/onebyte" 7
mk       "$W/flick" 100 200
mk       "$W/flick3" 100 200 300
mkrange  "$W/window" 100 104
mkrange  "$W/comp"   100 150 200
mkrange  "$W/comp2"  100 150 200 300
mkrange  "$W/late"   42 400
mkrange  "$W/early"  10 400

echo "== exact =="
check "bit-identical passes"                 0 case "exact basis -" "$MASKSTR" "$W/same"     "PASS masked-exact"
check "one differing byte fails"             1 case "exact basis -" "$MASKSTR" "$W/onebyte"  "FAIL masked live-state"
echo "== flicker (frozen inventory, drift either way is loud) =="
check "the frozen inventory passes"          0 case "flicker basis 2 100,200" "$MASKSTR" "$W/flick"  "PASS masked-flicker"
check "a GROWN inventory fails"              1 case "flicker basis 2 100,200" "$MASKSTR" "$W/flick3" "FAIL masked-flicker"
check "a SHRUNK inventory fails too"         1 case "flicker basis 2 100,200" "$MASKSTR" "$W/onebyte" "FAIL masked-flicker"
check "bit-identical is not a silent pass"   1 case "flicker basis 2 100,200" "$MASKSTR" "$W/same"    "FAIL masked-flicker"
echo "== diverge (the regression lock for the spec-stem bug) =="
check "divergence at the frozen frame"       0 case "diverge basis 42" "$MASKSTR" "$W/late"  "PASS"
check "an EARLIER onset fails"               1 case "diverge basis 42" "$MASKSTR" "$W/early"
check "no divergence at all fails"           1 case "diverge basis 42" "$MASKSTR" "$W/same"
if masked_check "$ROOT/theset" case "diverge basis 42" "$MASKSTR" "$W/late" | grep -q "NO-BASE-LOG"; then
    echo "  FAIL  a healthy diverge spec printed NO-BASE-LOG (the stem bug is back)"; fail=1
else echo "  PASS  a healthy diverge spec finds its base log"; fi
echo "== window =="
check "one contiguous run at the frozen onset" 0 case "window basis 100 104" "$MASKSTR" "$W/window" "PASS masked-window"
check "a drifting onset fails"                 1 case "window basis 110 114" "$MASKSTR" "$W/window"
check "bit-identical FAILS (the class asserts the divergence exists)" 1 case "window basis 100 104" "$MASKSTR" "$W/same"
echo "== composite (strict conjunction; adds no tolerance) =="
check "frozen flicker + frozen window passes" 0 case "composite basis 200 100-150" "$MASKSTR" "$W/comp"  "PASS masked-composite"
check "an unaccounted extra run fails"        1 case "composite basis 200 100-150" "$MASKSTR" "$W/comp2"
check "bit-identical fails"                   1 case "composite basis 200 100-150" "$MASKSTR" "$W/same"
echo "== the baseset/mask invariant =="
check "a set running a DIFFERENT mask than its basis is refused" 1 case "exact basis -" "043c-043d,dead-beef,7f00-8000" "$W/same" "mask mismatch"
mkdir -p "$ROOT/oldbasis/logs"; cp "$ROOT/basis/logs/case.log" "$ROOT/oldbasis/logs/case.log"
check "a record-less basis cited by a mask-carrying set is refused" 1 case "exact oldbasis -" "$MASKSTR" "$W/same" "no MASK record"
echo "== an unknown class is a failure, not a skip =="
check "unknown class"                        1 case "sortof basis -" "$MASKSTR" "$W/same" "unknown .masked class"
echo "== masked_mask_for =="
[ "$(masked_mask_for "$ROOT/theset")" = "$MASKSTR" ] && echo "  PASS  a set with a mask file reports it" || { echo "  FAIL  a set with a mask file did not report it"; fail=1; }
mkdir -p "$ROOT/nomask"
[ "$(masked_mask_for "$ROOT/nomask")" = "043c-043d,4182-41a2,7f00-8000" ] && echo "  PASS  a set without one falls back to the lineage default" || { echo "  FAIL  the default moved: $(masked_mask_for "$ROOT/nomask")"; fail=1; }
# MUST-FIRE: the consumer's mask default reaches the library through the env
# the runners export.
m2="$(BBH_MASK_DEFAULT=aa-bb sh -c '. "$BBH_HOME/lib/sh/masked_compare.sh"; masked_mask_for "$1"' _ "$ROOT/nomask")"
[ "$m2" = "aa-bb" ] && echo "  PASS  BBH_MASK_DEFAULT (from [suite].mask_default) overrides the built-in default" || { echo "  FAIL  the env default was ignored: '$m2'"; fail=1; }

echo
[ "$fail" = 0 ] && echo "PASS: masked_compare dispatch validated" || { echo "FAIL: see above"; exit 1; }
