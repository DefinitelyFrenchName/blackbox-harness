# accounting.sh — THE ACCOUNTING RULE for a battery: "GREEN" cannot print
# while a gate self-skipped. Sourced by a battery script (one that runs a
# sequence of gates and ends with one sentence). Lineage: VampireSaved
# tests/run_battery_m2.sh (14z-94, GitHub #24 there).
#
# WHY. That battery was `set -eu` and invoked each gate as a bare command, so
# exit 0 was indistinguishable from PASS — and at least four gates `exit 0`
# when a prerequisite is absent, while two whole GROUPS are skipped by an
# `if [ -x <instrument> ]` branch. On a machine without the instrument and
# with pruned build dirs, nine of ~24 gates never ran and the script still
# printed "BATTERY GREEN". That sentence is what a session records under
# "no untested change survives"; it must not be printable when a third of
# the battery self-skipped.
#
# Every gate call goes through the counted wrapper; a whole-group skip is
# counted by size; the closing sentence is GREEN only at zero skips. A FAIL
# still stops the battery immediately, exactly as `set -e` did — and since
# the verdict comes from lib/sh/classify.sh (the ONE classifier), a gate that
# exits 0 after the shell's own error line, or is killed by the timeout
# wrapper, stops it too; the lineage read those as PASS.
#
#   bbh_bat <gate.sh> [args...]       run a gate, print its output, count it
#   bbh_bat_group_skip <label> <n>    a whole group skipped by a branch
#   bbh_bat_report                    the closing sentence; returns 1 unless GREEN
#
# Needs classify.sh sourced first (bbh_classify); honours its BBH_CLASSIFY_*
# environment. A battery that wants the counters reads $_bat_pass,
# $_bat_skip and $_bat_skipped.

_bat_pass=0; _bat_skip=0; _bat_skipped=""

bbh_bat() {   # bbh_bat <gate.sh> [args...]
    _bat_name="$(basename "$1" .sh)"
    [ -n "${_BAT_TMP:-}" ] || { _BAT_TMP="$(mktemp -d)"; export _BAT_TMP; }
    "$@" > "$_BAT_TMP/out" 2>&1 && _bat_st=0 || _bat_st=$?
    cat "$_BAT_TMP/out"
    bbh_classify "$_bat_st" "$_BAT_TMP/out"
    case "$BBH_VERDICT" in
    PASS) _bat_pass=$((_bat_pass + 1)) ;;
    SKIP) _bat_skip=$((_bat_skip + 1)); _bat_skipped="$_bat_skipped $_bat_name" ;;
    *)    echo "BATTERY FAILED at $_bat_name (exit $_bat_st${BBH_DETAIL:+: $BBH_DETAIL})"
          rm -rf "$_BAT_TMP"
          exit "$([ "$_bat_st" = 0 ] && echo 1 || echo "$_bat_st")" ;;
    esac
}

# For the `if [ -x <instrument> ]` / `else note:` branches, which skip whole
# GROUPS without ever invoking a gate.
bbh_bat_group_skip() {   # bbh_bat_group_skip <label> <n-gates>
    _bat_skip=$((_bat_skip + $2))
    _bat_skipped="$_bat_skipped $1(x$2)"
}

bbh_bat_report() {
    [ -n "${_BAT_TMP:-}" ] && rm -rf "$_BAT_TMP"
    if [ "$_bat_skip" = 0 ]; then
        echo "BATTERY GREEN — $_bat_pass gates, 0 skipped"
        return 0
    fi
    echo "BATTERY INCOMPLETE — $_bat_pass passed, $_bat_skip SKIPPED:$_bat_skipped"
    echo "  A skipped gate asserts NOTHING. 'BATTERY GREEN' is the sentence a"
    echo "  session records; it is not printable while a gate self-skipped."
    return 1
}
