#!/bin/sh
# run.sh — THE HARNESS'S OWN GATE CHAIN. Every selftest/test_*.sh, classified
# by the same lib/sh/classify.sh the runners use (the harness eats its own
# verdicts), tallied PASS / SKIP / FAIL separately. ROM-free, no emulator.
#
# Usage: selftest/run.sh [--strict]      (--strict: SKIP is a failure too)
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
. "$BBH_HOME/lib/sh/classify.sh"
STRICT=0; [ "${1:-}" = "--strict" ] && STRICT=1
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT INT TERM
n_pass=0; n_skip=0; n_fail=0; failed=""; skipped=""
echo "== bbh selftest =="
for t in "$BBH_HOME"/selftest/test_*.sh; do
    g="$(basename "$t" .sh)"
    _t0=$(date +%s)
    sh "$t" </dev/null > "$W/$g.out" 2>&1 && _st=0 || _st=$?
    _dur=$(( $(date +%s) - _t0 ))
    bbh_classify "$_st" "$W/$g.out" 70
    case "$BBH_VERDICT" in
    PASS) printf '  %-28s PASS  %3ss\n' "$g" "$_dur"; n_pass=$((n_pass+1)) ;;
    SKIP) printf '  %-28s SKIP  %3ss  %s\n' "$g" "$_dur" "$BBH_DETAIL"; n_skip=$((n_skip+1)); skipped="$skipped $g" ;;
    *)    printf '  %-28s %s  %3ss  %s\n' "$g" "$BBH_VERDICT" "$_dur" "$BBH_DETAIL"
          sed 's/^/        | /' "$W/$g.out" | tail -"${FAIL_TAIL:-12}"
          n_fail=$((n_fail+1)); failed="$failed $g" ;;
    esac
done
echo "======================================================================"
printf 'PASS %-4s  SKIP %-4s  FAIL %s\n' "$n_pass" "$n_skip" "$n_fail"
[ -n "$skipped" ] && echo "skipped:$skipped"
[ -n "$failed" ] && echo "failed: $failed"
rc=0; [ "$n_fail" = 0 ] || rc=1
[ "$STRICT" = 1 ] && [ "$n_skip" != 0 ] && { echo "--strict: SKIP counts as failure"; rc=1; }
[ "$rc" = 0 ] && echo "GREEN — the harness's own gates pass." || echo "NOT GREEN — see above."
exit $rc
