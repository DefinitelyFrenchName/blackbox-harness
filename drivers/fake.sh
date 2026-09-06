#!/bin/sh
# fake.sh — THE FAKE DRIVER: drivers/README.md's contract over the fake
# machine (example/fakesys/fakesys.py), so the suite, the comparators and
# every selftest run end to end with no ROM and no emulator.
#
# Usage: FAKE_ROMPATH="<dir>[;<dir>]" drivers/fake.sh <set> <replay.rpl> <out.log> [sandbox]
#   env FAKE_ROMPATH   the search path holding <set>.zip (falls back to FAKE_ROOT)
#   env FAKE_BIN       the machine (default: python3 example/fakesys/fakesys.py)
#   env MASK_RANGES DUMPS POKES SNAP_FRAMES VIDEO_OUT INPUT_OUT TAIL_FRAMES
#       INPUT_INJECT_TEST NO_INPUT_CHECK   — honoured, per the contract
#   env FAKE_BUILD FAKE_NONDET FAKE_CRASH_AT — the machine's own knobs
#
# REFUSES the guarded driver's variables (GUARD_*, CRASH_VECTORS,
# CODE_RANGES) with exit 3: the fake has no debugger, and a driver that
# cannot honour a variable REFUSES — it never ignores one, because a caller
# that set it is measuring something this run would silently not measure.
#
# Exit 0 only if the log ends with a clean "END " line and carries no
# INPUT-VIOLATION; 2 when the machine reports a CRASH (the guard's exit,
# the log is the report); 1 otherwise.
set -eu
SET="${1:?usage: fake.sh <set> <replay.rpl> <out.log> [sandbox]}"
RPL="${2:?replay path required}"
OUT="${3:?output log path required}"
SANDBOX="${4:-}"
BBH_HOME="${BBH_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"

for v in GUARD_DEBUG GUARD_PROBE GUARD_PROBE_COND GUARD_TRACE GUARD_PC_LOG GUARD_BREAK GUARD_MATCH CRASH_VECTORS CODE_RANGES; do
    eval "_x=\${$v:-}"
    [ -z "$_x" ] || { echo "REFUSED: drivers/fake.sh cannot honour $v (a guarded driver's variable; the fake machine has no debugger)"; exit 3; }
done

RPL="$(cd "$(dirname "$RPL")" && pwd)/$(basename "$RPL")"
OUT_DIR="$(cd "$(dirname "$OUT")" && pwd)"; OUT="$OUT_DIR/$(basename "$OUT")"
# ABSOLUTE sandbox: the machine runs from inside it, so a relative one would
# resolve against the wrong directory (the lineage measured 0 log lines on a
# relative sandbox).
if [ -n "$SANDBOX" ]; then mkdir -p "$SANDBOX"; SANDBOX="$(cd "$SANDBOX" && pwd)"; fi
ROMPATH="${FAKE_ROMPATH:-${FAKE_ROOT:-}}"
[ -n "$ROMPATH" ] || { echo "fake.sh: set FAKE_ROMPATH (or FAKE_ROOT) to the directory holding $SET.zip"; exit 1; }
# ABSOLUTE search path, component by component: the machine runs from the
# sandbox, and a relative component would be resolved against it (the
# lineage's FBNeo driver produced a bare "DrvInit failed" on exactly this).
_abs=""; _rest="$ROMPATH;"
while [ -n "$_rest" ]; do
    _d="${_rest%%;*}"; _rest="${_rest#*;}"
    [ -n "$_d" ] || continue
    case "$_d" in /*) ;; *) _d="$(CDPATH= cd "$_d" 2>/dev/null && pwd)" || { echo "fake.sh: search-path component '$_d' does not resolve from $(pwd)"; exit 1; } ;; esac
    _abs="${_abs:+$_abs;}$_d"
done
ROMPATH="$_abs"
FAKE_BIN="${FAKE_BIN:-python3 $BBH_HOME/example/fakesys/fakesys.py}"

WORK="${SANDBOX:-$(mktemp -d)}"
mkdir -p "$WORK"
# Clear the artifact BEFORE the run: "no END line" must never be satisfied by
# a previous run's file (the lineage's FBNeo driver read yesterday's log as
# today's success).
rm -f "$OUT"
[ -n "${VIDEO_OUT:-}" ] && rm -f "$VIDEO_OUT"
[ -n "${INPUT_OUT:-}" ] && rm -f "$INPUT_OUT"

( cd "$WORK" && REPLAY="$RPL" CHECKSUM_OUT="$OUT" FAKE_SANDBOX="$WORK" \
    $FAKE_BIN "$SET" --rompath "$ROMPATH" > "$WORK/fake_replay.log" 2>&1 ) && _st=0 || _st=$?
if [ "$_st" != 0 ]; then
    if [ -f "$OUT" ] && grep -Eq "^(CRASH|END-CRASH) " "$OUT"; then
        echo "GUARD TRIPPED:"
        grep -E "^(CRASH|REGS|STACK|END-CRASH) " "$OUT"
        exit 2
    fi
    cat "$WORK/fake_replay.log"
    exit 1
fi
grep -q "^END " "$OUT" || { echo "replay did not complete (no END line)"; cat "$WORK/fake_replay.log"; exit 1; }
if grep -q "^INPUT-VIOLATION " "$OUT"; then
    echo "INPUT INTEGRITY VIOLATION — external input reached the machine:"
    grep "^INPUT-VIOLATION " "$OUT"
    echo "  (the run is discarded: it is not a replay of the script)"
    exit 1
fi
