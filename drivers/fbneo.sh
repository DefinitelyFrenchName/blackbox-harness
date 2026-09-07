#!/bin/sh
# fbneo.sh — THE FBNeo DRIVER: the contract over a patched FBNeo frontend
# that carries a replay harness (`-hinput <rpl> -hout <log> [-hframes N]
# [-hdump <spec>]`, env FBNEO_HVIDEO / FBNEO_HPOKE — the lineage's
# emu/fbneo-patches/0001). A SECOND implementation of the same machine, so
# the same replay can be compared at anchors (bbh compare-fields). Lineage:
# VampireSaved tools/run_replay_fbneo.sh.
#
# Usage: FBNEO_BIN=<fbneo> FBNEO_ROMPATH="<build>;<ref>" drivers/fbneo.sh <set> <replay.rpl> <out.log> [sandbox]
#   env FBNEO_BIN      the patched frontend (required)
#   env FBNEO_ROMPATH  the search path, first wins; ROMDIR (the reference
#                      input) is always the LAST component. The frontend has
#                      NO -rompath option (it reads `roms/` under its cwd), so
#                      the driver builds an OVERLAY of symlinks — every
#                      component's zips, later components first, so the
#                      first component's zip wins by name.
#   env DUMPS          honoured: mapped to -hdump (files land beside the log
#                      as <out.log>.dump_<f>_<a>.bin — the frontend's own
#                      naming, which bbh check-dumps / compare-fields accept)
#   env POKES          honoured: mapped to FBNEO_HPOKE (same grammar)
#   env VIDEO_OUT      honoured: mapped to FBNEO_HVIDEO
#   env TAIL_FRAMES    honoured only at the frontend's default (120) — any
#                      other value is REFUSED (the frontend's -hframes is an
#                      absolute total, not a tail)
#
# REFUSES MASK_RANGES, SNAP_FRAMES, INPUT_OUT, INPUT_INJECT_TEST,
# NO_INPUT_CHECK and the guard family with exit 3: the frontend implements
# none of them. (The lineage passed masks to this driver for a session
# before a gate noticed the logs were unmasked — the rule this line enforces.)
#
# Exit 0 only if the log ends with "END "; 1 otherwise. The frontend returns
# 0 unconditionally on some failures, so the artifact is REMOVED before the
# run and its presence afterwards is the completion check.
set -eu
SET="${1:?usage: fbneo.sh <set> <replay.rpl> <out.log> [sandbox]}"
RPL="${2:?replay path required}"
OUT="${3:?output log path required}"
SANDBOX="${4:-}"
BBH_HOME="${BBH_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"; export BBH_HOME
. "$BBH_HOME/lib/sh/mame_sandbox.sh"

bbh_refuse_vars drivers/fbneo.sh "the FBNeo harness does not implement it" \
    MASK_RANGES SNAP_FRAMES INPUT_OUT INPUT_INJECT_TEST NO_INPUT_CHECK
bbh_refuse_vars drivers/fbneo.sh "a guarded driver's variable; FBNeo has no guard" \
    GUARD_DEBUG GUARD_PROBE GUARD_PROBE_COND GUARD_TRACE GUARD_PC_LOG GUARD_BREAK GUARD_MATCH GUARD_FORCE CRASH_VECTORS CODE_RANGES
if [ -n "${TAIL_FRAMES:-}" ] && [ "$TAIL_FRAMES" != 120 ]; then
    echo "REFUSED: drivers/fbneo.sh cannot honour TAIL_FRAMES=$TAIL_FRAMES (the frontend's tail is fixed at 120; -hframes is an absolute total)"; exit 3
fi

# ABSOLUTE sandbox: the emulator runs from inside it, so a RELATIVE one
# produced NO checksum log at all in the lineage (0 lines vs 3,120).
if [ -n "$SANDBOX" ]; then mkdir -p "$SANDBOX"; SANDBOX="$(cd "$SANDBOX" && pwd)"; fi
FBNEO="${FBNEO_BIN:-}"
[ -n "$FBNEO" ] || { echo "set FBNEO_BIN to the patched FBNeo frontend"; exit 1; }
[ -x "$FBNEO" ] || { echo "FBNEO_BIN is not executable: $FBNEO"; exit 1; }
REF="${ROMDIR:-}"

RPL="$(cd "$(dirname "$RPL")" && pwd)/$(basename "$RPL")"
OUT="$(bbh_abs_out "$OUT")"

# Clear the outputs BEFORE the run: the frontend discards its harness status
# on some paths and returns 0, so a failed run would otherwise leave the
# PREVIOUS run's log in place for the completion check to read as success.
rm -f "$OUT" "$OUT".tap "$OUT".dump_*.bin "$OUT".gfx_*.bin
[ -n "${VIDEO_OUT:-}" ] && rm -f "$VIDEO_OUT"

WORK="${SANDBOX:-$(mktemp -d)}"
mkdir -p "$WORK"

# The overlay: components of FBNEO_ROMPATH (first wins) then ROMDIR last.
# Every component is made ABSOLUTE: the symlinks are resolved from INSIDE
# the sandbox (the emulator cds there), so a relative one is a broken link
# and a bare "DrvInit failed" with every member present.
_comps=""
_rest="${FBNEO_ROMPATH:-};"
while [ -n "$_rest" ]; do
    _d="${_rest%%;*}"; _rest="${_rest#*;}"
    [ -n "$_d" ] || continue
    case "$_d" in /*) ;; *) _d="$(CDPATH= cd "$_d" 2>/dev/null && pwd)" || { echo "fbneo.sh: search-path component '$_d' does not resolve from $(pwd)"; exit 1; } ;; esac
    _comps="$_comps$_d
"
done
if [ -n "$REF" ]; then
    REF="$(CDPATH= cd "$REF" 2>/dev/null && pwd)" || { echo "fbneo.sh: ROMDIR '$ROMDIR' does not exist"; exit 1; }
    _comps="$_comps$REF
"
fi
[ -n "$_comps" ] || { echo "set FBNEO_ROMPATH (the search path) or ROMDIR (the reference-input directory)"; exit 1; }
# NO trailing slash on the rm: `rm -rf "$WORK/roms/"` follows a symlink and
# would empty the reference directory; a REUSED sandbox may hold one.
rm -rf "$WORK/roms"; mkdir -p "$WORK/roms"
# later components first, so an earlier component's zip overwrites the link
printf '%s' "$_comps" | sed '1!G;h;$!d' | while IFS= read -r _d; do
    [ -n "$_d" ] || continue
    for z in "$_d"/*.zip; do [ -e "$z" ] && ln -sf "$z" "$WORK/roms/$(basename "$z")"; done
done

set -- "$SET" -hinput "$RPL" -hout "$OUT"
[ -n "${DUMPS:-}" ] && set -- "$@" -hdump "$DUMPS"
[ -n "${POKES:-}" ] && { FBNEO_HPOKE="$POKES"; export FBNEO_HPOKE; }
[ -n "${VIDEO_OUT:-}" ] && { FBNEO_HVIDEO="$VIDEO_OUT"; export FBNEO_HVIDEO; }

( cd "$WORK" && HOME="$WORK" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
    "$FBNEO" "$@" > "$WORK/fbneo_replay.log" 2>&1 ) \
    || { cat "$WORK/fbneo_replay.log"; exit 1; }
[ -f "$OUT" ] && grep -q "^END " "$OUT" || { echo "harness did not complete (no END line)"; cat "$WORK/fbneo_replay.log"; exit 1; }
