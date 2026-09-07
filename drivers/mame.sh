#!/bin/sh
# mame.sh — THE MAME DRIVER: drivers/README.md's contract over MAME and
# lua/mame/replay.lua under a machine profile. Lineage: VampireSaved
# tools/run_replay_mame.sh + tools/run_mame.sh; the log is byte-identical to
# theirs on the cps2 profile (fidelity F8).
#
# Usage: BBH_PROFILE=<board> MAME_ROMPATH="<build>;<ref>" drivers/mame.sh <set> <replay.rpl> <out.log> [sandbox]
#   env BBH_PROFILE    the machine profile (required): a name under
#                      lua/mame/profiles/ or a path
#   env MAME_BIN       the emulator binary (default `mame` on PATH — a pinned
#                      build is the consumer's to name)
#   env MAME_ROMPATH   the rompath chain, first wins (falls back to ROMDIR)
#   env MASK_RANGES DUMPS POKES SNAP_FRAMES VIDEO_OUT INPUT_OUT TAIL_FRAMES
#       INPUT_INJECT_TEST NO_INPUT_CHECK   — honoured, per the contract
#
# REFUSES the guarded driver's variables (GUARD_*, CRASH_VECTORS,
# CODE_RANGES) with exit 3: this driver has no debugger and no PC
# classifier, and a driver that cannot honour a variable never ignores one.
#
# Exit 0 only if the log ends with a clean "END " line and carries no
# INPUT-VIOLATION; 1 otherwise (the emulator's own log is printed).
set -eu
SET="${1:?usage: mame.sh <set> <replay.rpl> <out.log> [sandbox]}"
RPL="${2:?replay path required}"
OUT="${3:?output log path required}"
SANDBOX="${4:-}"
BBH_HOME="${BBH_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"; export BBH_HOME
. "$BBH_HOME/lib/sh/mame_sandbox.sh"

bbh_refuse_vars drivers/mame.sh "a guarded driver's variable; use drivers/mame_guarded.sh" \
    GUARD_DEBUG GUARD_PROBE GUARD_PROBE_COND GUARD_PROBE_MEM GUARD_PROBE_MAX GUARD_PROBE_HIST \
    GUARD_PROBE_TRACE GUARD_TRACE GUARD_PC_LOG GUARD_BREAK GUARD_MATCH GUARD_FORCE CRASH_VECTORS CODE_RANGES
bbh_mame_profile_resolve || exit 1

RPL="$(cd "$(dirname "$RPL")" && pwd)/$(basename "$RPL")"
OUT="$(bbh_abs_out "$OUT")"
if [ -n "$SANDBOX" ]; then mkdir -p "$SANDBOX"; SANDBOX="$(cd "$SANDBOX" && pwd)"; fi

WORK="${SANDBOX:-$(mktemp -d)}"
mkdir -p "$WORK"
# Clear the artifacts BEFORE the run: "no END line" must never be satisfied
# by a previous run's file.
rm -f "$OUT"
[ -n "${VIDEO_OUT:-}" ] && rm -f "$VIDEO_OUT"
[ -n "${INPUT_OUT:-}" ] && rm -f "$INPUT_OUT"

REPLAY="$RPL" CHECKSUM_OUT="$OUT"; export REPLAY CHECKSUM_OUT
bbh_mame_run "$WORK" "$SET" \
    -autoboot_script "$BBH_HOME/lua/mame/replay.lua" > "$WORK/mame_replay.log" 2>&1 \
    || { cat "$WORK/mame_replay.log"; exit 1; }
[ -f "$OUT" ] && grep -q "^END " "$OUT" || { echo "replay did not complete (no END line)"; cat "$WORK/mame_replay.log"; exit 1; }
# Input-integrity violation: host input reached the emulated controls, so
# this run is not a replay of the script and must never be compared against
# anything.
if grep -q "^INPUT-VIOLATION " "$OUT"; then
    echo "INPUT INTEGRITY VIOLATION — external input reached the machine:"
    grep "^INPUT-VIOLATION " "$OUT"
    echo "  (the run is discarded: it is not a replay of the script)"
    exit 1
fi
