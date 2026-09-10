# controls.sh — THE MUST-FIRE CONTRACT'S READER, one copy, sourced by the
# classifier (lib/sh/classify.sh) and by any gate that declares a control.
#
# THE GRAMMAR (docs/gate_contract.md §5). A control is DECLARED in the gate's
# HEADER — the LEADING COMMENT BLOCK: every `#` line after the shebang up to
# the first non-comment line; a bare `#` does NOT end it — FIRED at run time
# as a column-0 line, and EXECUTABLE as a mode:
#
#   # MUST-FIRE: <shape>: <name> — <what must fail, and why that proves the gate can fail>
#       shape ∈ perturbed-copy | shadow-tool | known-bad ; name [a-z0-9-]+
#   # MUST-FIRE: none — <why this gate asserts no property>
#   CONTROL FIRED: <name> — <evidence>           (printed at run time, col 0)
#   CONTROL DEAD: <name> — <what happened>       (the verdict is FAIL, whatever else said)
#
# THE EXECUTABLE FORM: a declared name is also a MODE. `CONTROL=<name> <gate>`
# applies that control's perturbation to the gate's REAL input and runs to
# the gate's own verdict, which must be FAIL. A name the header does not
# declare is REFUSED (exit 3) — a runner reads that as a dead mode.
#
# Lineage: VampireSaved's tests/lib/controls.sh (its 14z-147, "step two of
# the must-fire machine"), itself a copy of the BBX project's R10/R29/R30 —
# independent but compatible, never a dependency. The four regexes are the
# whole reader; a malformed line (a wrong shape, a name with a capital or an
# underscore, a hyphen where the em dash belongs) declares NOTHING, so the
# census of a tree is what the regex counts and nothing looser.
#
# Functions (sh, no bashisms — gates are #!/bin/sh):
#   bbh_ctl_header <script>            the leading comment block, to stdout
#   bbh_ctl_declared <script>          declared names, one per line
#   bbh_ctl_none <script>              the `none` reason, or nothing
#   bbh_ctl_mode <script>              honour $CONTROL: sets BBH_CTL to the name
#                                      (or empty); REFUSES an undeclared name
#   bbh_ctl_is <name>                  true when $BBH_CTL is <name>
#   bbh_ctl_fired <name> <evidence>    print the FIRED line
#   bbh_ctl_dead <name> <what>         print the DEAD line (returns 1 so a
#                                      caller can `|| fail=1`; under set -e
#                                      guard it — a bare `[ ] && f` aborts)
#   bbh_ctl_read <script> <log>        declared vs fired for one run; sets
#                                      BBH_CTL_DECLARED/FIRED/DEAD/UNDECLARED
#                                      (counts), BBH_CTL_MISSING (names),
#                                      BBH_CTL_VERDICT OK|RED|UNDECLARED|NONE,
#                                      BBH_CTL_DETAIL
# Ground truth: selftest/test_controls.sh.

BBH_CTL_SHAPES='perturbed-copy|shadow-tool|known-bad'

bbh_ctl_header() {  # the leading comment block after the shebang; a bare # continues it
    awk 'NR == 1 { next } /^#/ { print; next } { exit }' "$1"
}

bbh_ctl_declared() {
    bbh_ctl_header "$1" \
        | sed -n -E "s/^# MUST-FIRE: ($BBH_CTL_SHAPES): ([a-z0-9-]+) — .+\$/\2/p"
}

bbh_ctl_none() {
    bbh_ctl_header "$1" | sed -n -E 's/^# MUST-FIRE: none — (.+)$/\1/p' | head -1
}

bbh_ctl_mode() {  # bbh_ctl_mode <script>
    BBH_CTL="${CONTROL:-}"
    [ -n "$BBH_CTL" ] || return 0
    if ! bbh_ctl_declared "$1" | grep -qx -- "$BBH_CTL"; then
        echo "REFUSED: CONTROL=$BBH_CTL is not a mode of this gate"
        exit 3
    fi
    echo "CONTROL MODE: $BBH_CTL — the perturbation is applied to the REAL input; this run must FAIL"
    return 0
}

bbh_ctl_is() { [ "${BBH_CTL:-}" = "$1" ]; }

bbh_ctl_fired() { echo "CONTROL FIRED: $1 — $2"; }
bbh_ctl_dead()  { echo "CONTROL DEAD: $1 — $2"; return 1; }

bbh_ctl_read() {  # bbh_ctl_read <script> <log>
    _s="$1"; _l="$2"
    BBH_CTL_DECLARED=0; BBH_CTL_FIRED=0; BBH_CTL_DEAD=0; BBH_CTL_UNDECLARED=0
    BBH_CTL_MISSING=""; BBH_CTL_DETAIL=""; BBH_CTL_VERDICT=OK
    _decl="$(bbh_ctl_declared "$_s")"
    _none="$(bbh_ctl_none "$_s")"
    _fired="$(grep -aE '^CONTROL FIRED: [a-z0-9-]+' "$_l" 2>/dev/null | sed -E 's/^CONTROL FIRED: ([a-z0-9-]+).*/\1/')"
    _dead="$(grep -aE '^CONTROL DEAD: [a-z0-9-]+' "$_l" 2>/dev/null | sed -E 's/^CONTROL DEAD: ([a-z0-9-]+).*/\1/')"
    for _n in $_decl; do
        BBH_CTL_DECLARED=$((BBH_CTL_DECLARED + 1))
        if printf '%s\n' "$_dead" | grep -qx -- "$_n"; then
            BBH_CTL_DEAD=$((BBH_CTL_DEAD + 1)); BBH_CTL_MISSING="$BBH_CTL_MISSING $_n(dead)"
        elif printf '%s\n' "$_fired" | grep -qx -- "$_n"; then
            BBH_CTL_FIRED=$((BBH_CTL_FIRED + 1))
        else
            BBH_CTL_DEAD=$((BBH_CTL_DEAD + 1)); BBH_CTL_MISSING="$BBH_CTL_MISSING $_n(not fired)"
        fi
    done
    for _n in $_fired $_dead; do
        printf '%s\n' "$_decl" | grep -qx -- "$_n" \
            || { BBH_CTL_UNDECLARED=$((BBH_CTL_UNDECLARED + 1)); BBH_CTL_MISSING="$BBH_CTL_MISSING $_n(undeclared)"; }
    done
    if [ "$BBH_CTL_DEAD" != 0 ] || [ "$BBH_CTL_UNDECLARED" != 0 ]; then
        BBH_CTL_VERDICT=RED
        BBH_CTL_DETAIL="controls RED:$BBH_CTL_MISSING"
    elif [ "$BBH_CTL_DECLARED" = 0 ]; then
        if [ -n "$_none" ]; then BBH_CTL_VERDICT=NONE; BBH_CTL_DETAIL="none — $_none"
        else BBH_CTL_VERDICT=UNDECLARED; BBH_CTL_DETAIL="no MUST-FIRE line"; fi
    fi
    return 0
}
