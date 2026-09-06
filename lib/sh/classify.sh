# classify.sh — THE verdict classifier. One copy, sourced by every runner.
#
#   bbh_classify <exit-status> <logfile> [detail-width]
#     sets BBH_VERDICT  (PASS | SKIP | FAIL | TIMEOUT)
#     and  BBH_DETAIL   (the one line a human reads beside the verdict)
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

bbh_classify() {
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
