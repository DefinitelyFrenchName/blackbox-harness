#!/bin/sh
# mame_guarded.sh — THE GUARDED MAME DRIVER: the contract over MAME and
# lua/mame/replay_guard.lua (crash detection). Lineage: VampireSaved
# tools/run_replay_guarded.sh.
#
# Usage: BBH_PROFILE=<board> drivers/mame_guarded.sh <set> <replay.rpl> <out.log> [sandbox]
#   env GUARD_DEBUG=0     cheap mode (no -debug); default 1 = authoritative
#   env CRASH_VECTORS / CODE_RANGES / GUARD_MATCH / GUARD_PROBE[_COND|_MEM|
#       _MAX|_HIST|_TRACE] / GUARD_TRACE / GUARD_PC_LOG / GUARD_BREAK /
#       GUARD_FORCE          pass through to the guard (its header)
#   env DUMPS POKES SNAP_FRAMES TAIL_FRAMES INPUT_INJECT_TEST   honoured
#   env MAME_BIN MAME_ROMPATH BBH_PROFILE   as drivers/mame.sh
#
# REFUSES MASK_RANGES, NO_INPUT_CHECK, VIDEO_OUT and INPUT_OUT with exit 3:
# the guard does not implement them, and a masked expectation compared
# against its unmasked log would be a phantom regression with no reachable
# green state (the lineage's GitHub #31). Use drivers/mame.sh for those.
#
# NOTE: -debug runs are deterministic but NOT checksum-comparable to
# non-debug runs (the scheduler's timeslicing differs); GUARD_DEBUG=0 when
# the checksum log must match a frozen expectation.
#
# Exit 0 only if the log ends with a clean "END " line AND contains no
# CRASH/PCWEEDS/SOFTRESET/END-CRASH/INPUT-VIOLATION lines; 2 when the guard
# tripped (the log is the bug report); 1 when the emulator failed.
set -eu
SET="${1:?usage: mame_guarded.sh <set> <replay.rpl> <out.log> [sandbox]}"
RPL="${2:?replay path required}"
OUT="${3:?output log path required}"
SANDBOX="${4:-}"
BBH_HOME="${BBH_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"; export BBH_HOME
. "$BBH_HOME/lib/sh/mame_sandbox.sh"

bbh_refuse_vars drivers/mame_guarded.sh "the guard does not implement it; use drivers/mame.sh" \
    MASK_RANGES NO_INPUT_CHECK VIDEO_OUT INPUT_OUT
bbh_mame_profile_resolve || exit 1

RPL="$(cd "$(dirname "$RPL")" && pwd)/$(basename "$RPL")"
OUT="$(bbh_abs_out "$OUT")"
if [ -n "$SANDBOX" ]; then mkdir -p "$SANDBOX"; SANDBOX="$(cd "$SANDBOX" && pwd)"; fi

WORK="${SANDBOX:-$(mktemp -d)}"
mkdir -p "$WORK"
rm -f "$OUT"

# With -debug the debugger halts at the first instruction; the -debugscript
# "go" resumes it at emulated time zero (the guard's periodic callback would
# also resume it, but this is deterministic insurance).
set -- "$SET" -autoboot_script "$BBH_HOME/lua/mame/replay_guard.lua"
if [ "${GUARD_DEBUG:-1}" = "1" ]; then
    printf 'go\n' > "$WORK/guard_go.dbs"
    set -- "$@" -debug -debugger none -debugscript "$WORK/guard_go.dbs"
fi

REPLAY="$RPL" CHECKSUM_OUT="$OUT"; export REPLAY CHECKSUM_OUT
bbh_mame_run "$WORK" "$@" > "$WORK/mame_guard.log" 2>&1 \
    || { cat "$WORK/mame_guard.log"; exit 1; }

# INPUT-VIOLATION joins the trip set: a violation means the run stopped being
# a replay of the script. Without it in this grep the line would be written
# to the log and never read — the same silent PASS the check exists to remove.
[ -f "$OUT" ] || { echo "replay did not complete (no log)"; cat "$WORK/mame_guard.log"; exit 1; }
if grep -Eq "^(CRASH|PCWEEDS|SOFTRESET|END-CRASH|INPUT-VIOLATION) " "$OUT"; then
    echo "GUARD TRIPPED:"
    grep -E "^(CRASH|STACK|PCWEEDS|SOFTRESET|END-CRASH|INPUT-VIOLATION) " "$OUT"
    exit 2
fi
grep -q "^END " "$OUT" || { echo "replay did not complete (no END line)"; cat "$WORK/mame_guard.log"; exit 1; }
