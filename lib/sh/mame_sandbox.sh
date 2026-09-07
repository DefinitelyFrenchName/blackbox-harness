# mame_sandbox.sh — the headless, sandboxed MAME invocation every MAME
# driver shares (lineage: VampireSaved tools/run_mame.sh, "the most reusable
# file in the tree"). Sourced; BBH_HOME must be set.
#
#   bbh_mame_profile_resolve        BBH_PROFILE -> an absolute path (a bare
#                                   name resolves to lua/mame/profiles/<name>.lua);
#                                   FAILS when unset — a driver never runs on
#                                   an implied board
#   bbh_mame_run <sandbox> <set> [mame args...]
#                                   exec-free: runs MAME_BIN (default `mame`)
#                                   on <set> with the rompath chain and every
#                                   isolation flag; returns its status
#
# Environment:
#   MAME_BIN       the emulator binary (default: `mame` on PATH). A consumer
#                  with a pinned build points this at it; the lineage's rule:
#                  a script that boots a set only a patched binary knows must
#                  carry a real pin, or the run measures nothing.
#   MAME_ROMPATH   the rompath chain "build;reference" (first wins); defaults
#                  to $ROMDIR, the reference-input directory
#   SDL_VIDEODRIVER  default `dummy`: SDL creates NO window at all, so there
#                  is nothing to steal focus and nothing for a stray
#                  keystroke to land on (measured non-perturbing in the
#                  lineage: work RAM bit-identical, VIDEO_OUT still live —
#                  the emulated bitmap is internal to MAME).
#
# INPUT ISOLATION: MAME's "-video none" still creates a window that can take
# focus, and any host keystroke that lands on it is injected into the
# EMULATED controls. A replay is only reproducible if its inputs come
# exclusively from the script, so all four host input providers are
# disabled. This is not a preference; a run that can absorb a stray keypress
# is not an oracle. Every run gets a FRESH sandbox for cfg/nvram/diff/snap/
# sta/home, so no EEPROM or nvram state leaks between runs.

bbh_mame_profile_resolve() {
    _p="${BBH_PROFILE:-}"
    [ -n "$_p" ] || { echo "set BBH_PROFILE to a machine profile (a name under $BBH_HOME/lua/mame/profiles/, or a path)"; return 1; }
    case "$_p" in
    */*) case "$_p" in /*) ;; *) _p="$(cd "$(dirname "$_p")" 2>/dev/null && pwd)/$(basename "$_p")" ;; esac ;;
    *.lua) _p="$BBH_HOME/lua/mame/profiles/$_p" ;;
    *)     _p="$BBH_HOME/lua/mame/profiles/$_p.lua" ;;
    esac
    [ -f "$_p" ] || { echo "machine profile not found: $_p (BBH_PROFILE=${BBH_PROFILE})"; return 1; }
    BBH_PROFILE="$_p"; export BBH_PROFILE
}

bbh_mame_run() {
    _sb="${1:?sandbox}"; _set="${2:?set}"; shift 2
    mkdir -p "$_sb"
    _rp="${MAME_ROMPATH:-${ROMDIR:-}}"
    [ -n "$_rp" ] || { echo "set MAME_ROMPATH (the rompath chain) or ROMDIR (the reference-input directory)"; return 1; }
    : "${SDL_VIDEODRIVER:=dummy}"
    export SDL_VIDEODRIVER
    "${MAME_BIN:-mame}" "$_set" \
        -rompath "$_rp" \
        -keyboardprovider none -mouseprovider none \
        -joystickprovider none -lightgunprovider none \
        -video none -sound none -nothrottle -skip_gameinfo \
        -cfg_directory "$_sb/cfg" \
        -nvram_directory "$_sb/nvram" \
        -diff_directory "$_sb/diff" \
        -snapshot_directory "$_sb/snap" \
        -state_directory "$_sb/sta" \
        -homepath "$_sb" \
        "$@"
}

# bbh_refuse_vars <driver> <why> VAR... — the contract's rule: a driver that
# cannot honour a variable REFUSES it (exit 3), never ignores it.
bbh_refuse_vars() {
    _drv="$1"; _why="$2"; shift 2
    for _v in "$@"; do
        eval "_x=\${$_v:-}"
        [ -z "$_x" ] || { echo "REFUSED: $_drv cannot honour $_v ($_why)"; exit 3; }
    done
}

# bbh_abs_out <path> — an output path made absolute (its directory must exist)
bbh_abs_out() {
    echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}
