#!/bin/sh
# test_accounting.sh — ground truth for lib/sh/accounting.sh: "BATTERY GREEN"
# cannot print while a gate self-skipped; a FAIL stops the battery and names
# the gate; a clean battery still reports GREEN. ROM-free, ~1 s.
#
# The lineage's sections (VampireSaved test_battery_accounting.sh §3-5) on
# stub gates, plus the two verdicts the lineage's wrapper could not see and
# this one takes from the ONE classifier: exit 0 after the shell's own error
# line, and the timeout wrapper's exit — both stop the battery.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
mk() { printf '#!/bin/sh\n%s\nexit %s\n' "$2" "$3" > "$T/$1"; chmod +x "$T/$1"; }
mk g_pass.sh 'echo "PASS: fine"' 0
mk g_skip.sh 'echo "SKIP: no build dir"' 0
mk g_fail.sh 'echo "FAIL: broken"' 1
mk g_crash.sh 'echo "tests/g_crash.sh: line 3: FOO: set FOO"' 0
mk g_kill.sh 'echo "running"' 124
run() { ( cd "$T" && sh -c ". \"$BBH_HOME/lib/sh/classify.sh\"; . \"$BBH_HOME/lib/sh/accounting.sh\"; $1" 2>&1 ); }

echo "== 1. the tally =="
out="$(run 'bbh_bat ./g_pass.sh; bbh_bat ./g_skip.sh; bbh_bat_group_skip wide-mame 5; echo "TALLY pass=$_bat_pass skip=$_bat_skip list=$_bat_skipped"')"
printf '%s\n' "$out" | grep -q "TALLY pass=1 skip=6" && ok "1 pass, 1 self-skip + a 5-gate group skip = 6 skipped" || fail "tally: $(printf '%s\n' "$out" | grep TALLY || echo none)"
printf '%s\n' "$out" | grep -q "wide-mame(x5)" && ok "the group skip names itself and its size" || fail "group skip anonymous"
printf '%s\n' "$out" | grep -q "^PASS: fine$" && printf '%s\n' "$out" | grep -q "^SKIP: no build dir$" && ok "each gate's output is printed through" || fail "output not printed"

echo "== 2. a FAIL stops the battery immediately and names the gate =="
if run 'bbh_bat ./g_fail.sh; echo REACHED-AFTER-FAIL' > "$T/f.out"; then fail "a failing gate did not stop the battery"; else
    grep -q REACHED-AFTER-FAIL "$T/f.out" && fail "execution continued past a failing gate" || ok "aborted at the failure"
    grep -q "BATTERY FAILED at g_fail (exit 1" "$T/f.out" && ok "and it names the gate that failed, with its exit" || fail "abort text: $(cat "$T/f.out")"; fi

echo "== 3. the verdicts the lineage's wrapper read as PASS =="
if run 'bbh_bat ./g_crash.sh; echo REACHED' > "$T/c.out"; then fail "exit 0 after a shell error did not stop the battery"; else
    grep -q "BATTERY FAILED at g_crash (exit 0: exit 0 after a shell error" "$T/c.out" && ok "exit 0 after the shell's own error line: BATTERY FAILED (the classifier's detail carried)" || fail "$(cat "$T/c.out")"; fi
run 'bbh_bat ./g_kill.sh' > "$T/k.out" 2>&1 && st=0 || st=$?
[ "$st" = 124 ] && grep -q "BATTERY FAILED at g_kill (exit 124: killed" "$T/k.out" && ok "a timeout exit stops it and is passed through as the exit status" || fail "timeout: exit $st, $(cat "$T/k.out")"

echo "== 4. the report =="
out="$(run 'bbh_bat ./g_pass.sh; bbh_bat ./g_pass.sh; bbh_bat_report')" && ok "a clean battery exits 0" || fail "clean battery non-zero"
printf '%s\n' "$out" | grep -q "^BATTERY GREEN — 2 gates, 0 skipped$" && ok "…and prints GREEN with the count (the CONTROL: 'never print GREEN' would pass every other section)" || fail "green line: $(printf '%s\n' "$out" | tail -1)"
out="$(run 'bbh_bat ./g_pass.sh; bbh_bat ./g_skip.sh; bbh_bat_group_skip sim 2; bbh_bat_report')" && fail "a skipped battery exited 0" || ok "a skipped battery exits non-zero"
printf '%s\n' "$out" | grep -q "^BATTERY INCOMPLETE — 1 passed, 3 SKIPPED: g_skip sim(x2)$" && ok "INCOMPLETE names the count and the skipped gates" || fail "incomplete line: $(printf '%s\n' "$out" | grep BATTERY)"
printf '%s\n' "$out" | grep -q "^BATTERY GREEN" && fail "GREEN printed beside INCOMPLETE" || ok "GREEN is not printable while a gate self-skipped"

echo
[ "$rc" = 0 ] && echo "PASS: the battery cannot call itself green while skipping" || { echo "FAIL: see above"; exit 1; }
