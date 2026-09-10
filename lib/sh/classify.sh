# classify.sh — THE verdict classifier. One copy, sourced by every runner.
#
#   bbh_classify <exit-status> <logfile> [detail-width] [gate-script]
#     sets BBH_VERDICT  (PASS | SKIP | FAIL | TIMEOUT)
#     and  BBH_DETAIL   (the one line a human reads beside the verdict)
#     (the gate script, when given, is read for its MUST-FIRE declarations —
#      a red controls block on a PASS is plain FAIL; see below)
#   bbh_classify_control <exit-status> <logfile>
#     sets BBH_CTL_EXEC (HONOURED | LIES | REFUSED | DIED | TIMEOUT) and
#     BBH_CTL_EXEC_DETAIL — the verdict on a `CONTROL=<name>` run
#
# EXIT STATUS DECIDES FIRST. A gate that prints `SKIP:` AND exits non-zero is
# a FAILURE, not a skip: it ran, could not complete, and said so. The case is
# not hypothetical — VampireSaved's first sweep had a gate print "SKIPPED: set
# FBNEO_REF" and exit 2 with "PARTIAL: the invariant was NOT run", and an
# exit-status-second classifier called it a skip: the ONE gate that justified
# modifying an emulator at all read as benign. SKIP is only ever exit 0 plus
# the marker.
#
# THE THREE EXCEPTIONS, each written for a false green that was paid for:
#   1. exit 124 / 137 (the timeout wrapper's) -> TIMEOUT, not FAIL, so a killed
#      gate is never read as a defect in the artifact.
#   2. exit 0 with the shell's OWN `<script>.sh: line N: NAME: message` in the
#      log -> FAIL. macOS bash 3.2 returns 0 for a `${VAR:?}` abort once an
#      EXIT trap is armed; a 65-minute gate was recorded `PASS 0s` on four
#      lines of log. The benign look-alike — an emulator segfaulting at
#      teardown AFTER the summary line, `line N:  <pid> Segmentation fault` —
#      has digits where the NAME would be and does not match.
#   3. exit 0 with `^ *SKIP` -> SKIP; the word SKIP in PROSE is not a marker.
#
# Every regex and the exit list come from the consumer's [classify] section
# through the BBH_CLASSIFY_* variables the runner exports; the defaults here
# are the literals the lineage carried.
#
# THE CONTROLS CONTRACT IS READ HERE, NOT AS A FIFTH VERDICT (docs/gate_contract.md
# §5). An optional 4th argument names the gate SCRIPT; when given and the
# verdict is PASS, the header's `# MUST-FIRE:` declarations are compared with
# the log's `CONTROL FIRED:` / `CONTROL DEAD:` lines (lib/sh/controls.sh, the
# one reader) and a red block — a declared control that did not fire, a DEAD
# line, a firing no header declares — turns the verdict into plain FAIL. A
# gate with no declaration is left alone (UNDECLARED is counted by the
# runners, never failed here: a consumer's gates may predate the grammar).
# SKIP and FAIL are never touched: a skipped gate ran nothing, a failed gate
# is already red. Lineage: VampireSaved's 14z-147 ("no fourth verdict").
if [ -n "${BBH_HOME:-}" ] && [ -f "$BBH_HOME/lib/sh/controls.sh" ]; then
    . "$BBH_HOME/lib/sh/controls.sh"
fi

bbh_classify() {  # bbh_classify <exit-status> <logfile> [detail-width] [gate-script]
    _st="$1"; _log="$2"; _w="${3:-90}"; _gate="${4:-}"
    _bbh_classify_base "$_st" "$_log" "$_w"
    [ "$BBH_VERDICT" = PASS ] && [ -n "$_gate" ] && [ -f "$_gate" ] || return 0
    command -v bbh_ctl_read >/dev/null 2>&1 || return 0
    bbh_ctl_read "$_gate" "$_log"
    if [ "$BBH_CTL_VERDICT" = RED ]; then
        BBH_VERDICT=FAIL; BBH_DETAIL="$(printf '%s' "$BBH_CTL_DETAIL" | cut -c1-"$_w")"
    fi
    return 0
}

# THE EXECUTABLE CONTROL'S VERDICT — one copy, here, so no runner carries a
# second shell-error regex. A gate run under `CONTROL=<name>` must reach its
# OWN FAIL:
#   HONOURED  exit non-zero and no crash — the perturbation was caught
#   LIES      exit 0 (or a SKIP) — the perturbation left the gate green
#   REFUSED   the gate printed `REFUSED: CONTROL=` — a declared name it never reads
#   DIED      the shell's own error line or a Python traceback — a crash is
#             not a verdict
#   TIMEOUT   the wrapper's exits, as for any gate
bbh_classify_control() {  # bbh_classify_control <exit-status> <logfile>
    _cst="$1"; _clog="$2"
    _err_re="${BBH_CLASSIFY_SHELL_ERROR_RE:-\\.sh: line [0-9]+: [A-Za-z_][A-Za-z0-9_]*: }"
    if grep -qa '^REFUSED: CONTROL=' "$_clog"; then
        BBH_CTL_EXEC=REFUSED; BBH_CTL_EXEC_DETAIL="declared in the header, not a mode of the gate"; return 0
    fi
    _bbh_classify_base "$_cst" "$_clog" 90
    case "$BBH_VERDICT" in
    TIMEOUT) BBH_CTL_EXEC=TIMEOUT; BBH_CTL_EXEC_DETAIL="$BBH_DETAIL" ;;
    PASS|SKIP) BBH_CTL_EXEC=LIES; BBH_CTL_EXEC_DETAIL="exit $_cst under its own perturbation — the control tests nothing" ;;
    FAIL)
        if [ "$_cst" = 0 ] || grep -qa '^Traceback' "$_clog"; then
            BBH_CTL_EXEC=DIED; BBH_CTL_EXEC_DETAIL="a crash is not a verdict: $(grep -aE "$_err_re|^Traceback|Error" "$_clog" | head -1 | cut -c1-90)"
        else
            BBH_CTL_EXEC=HONOURED; BBH_CTL_EXEC_DETAIL="reached the gate's own FAIL (exit $_cst)"
        fi ;;
    esac
    return 0
}

_bbh_classify_base() {
    _st="$1"; _log="$2"; _w="${3:-90}"
    _skip_re="${BBH_CLASSIFY_SKIP_RE:-^ *SKIP}"
    _err_re="${BBH_CLASSIFY_SHELL_ERROR_RE:-\\.sh: line [0-9]+: [A-Za-z_][A-Za-z0-9_]*: }"
    for _x in ${BBH_CLASSIFY_TIMEOUT_EXITS:-124 137}; do
        if [ "$_st" = "$_x" ]; then
            BBH_VERDICT=TIMEOUT; BBH_DETAIL="killed (exit $_st)"; return 0
        fi
    done
    if [ "$_st" != 0 ]; then
        BBH_VERDICT=FAIL
        BBH_DETAIL="exit $_st: $(grep -aE '^ *(SKIP|PARTIAL)|FAIL|ERROR|Traceback|not found' "$_log" | tail -1 | cut -c1-"$_w")"
        return 0
    fi
    if grep -qaE "$_err_re" "$_log"; then
        BBH_VERDICT=FAIL
        BBH_DETAIL="exit 0 after a shell error: $(grep -aE "$_err_re" "$_log" | head -1 | cut -c1-"$_w")"
        return 0
    fi
    if grep -qaE "$_skip_re" "$_log"; then
        BBH_VERDICT=SKIP
        BBH_DETAIL="$(grep -aE "$_skip_re" "$_log" | head -1 | cut -c1-"$_w")"
        return 0
    fi
    BBH_VERDICT=PASS; BBH_DETAIL=""
    return 0
}

# bbh_classify_env <bbh.toml> — export the [classify] section for bbh_classify.
# Needs config.sh sourced (bbh_cfg).
bbh_classify_env() {
    BBH_CLASSIFY_SKIP_RE="$(bbh_cfg classify.skip_regex)"
    BBH_CLASSIFY_SHELL_ERROR_RE="$(bbh_cfg classify.shell_error_regex)"
    BBH_CLASSIFY_TIMEOUT_EXITS="$(bbh_cfg classify.timeout_exits | tr '\n' ' ')"
    BBH_CLASSIFY_FAIL_TAIL="$(bbh_cfg classify.fail_tail)"
    export BBH_CLASSIFY_SKIP_RE BBH_CLASSIFY_SHELL_ERROR_RE BBH_CLASSIFY_TIMEOUT_EXITS BBH_CLASSIFY_FAIL_TAIL
}
