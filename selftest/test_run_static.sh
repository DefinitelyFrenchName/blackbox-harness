#!/bin/sh
# test_run_static.sh — ground truth for bin/bbh-run-static, run against a
# COPY of example/ with stub gates of known verdicts through the REAL runner
# and its registries — never a copy of its logic. ROM-free, ~3 s.
#
# Lineage: VampireSaved's test_static_runner.sh (its seven sections), plus the
# two classifier cases its sweep twin added (exit 0 after a shell error is
# FAIL; a teardown segfault line is not), the static tier's gating by
# static_needs_env, and --list.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
FR="$T/fake"; cp -R "$BBH_HOME/example" "$FR"
RUN="$BBH_HOME/bin/bbh-run-static --config $FR/bbh.toml"

mk() {  # mk <name> <exit> <output...>
    n="$1"; st="$2"; shift 2
    { echo "#!/bin/sh"; for l in "$@"; do echo "echo '$l'"; done; echo "exit $st"; } > "$FR/tests/$n.sh"
    chmod +x "$FR/tests/$n.sh"
}
mk g_fail 1 "something broke" "FAIL: nope"
mk g_skip_fail 2 "  SKIPPED: no reference binary" "PARTIAL: the invariant was NOT run"
mk g_shellcrash 0 "tests/g_shellcrash.sh: line 3: FOO: set FOO to a dir OUTSIDE the repo"
printf 'g_pass\ng_fail\ng_skip\ng_skip_indent\ng_prose\ng_skip_fail\ng_shellcrash\ng_segv_prose\n' > "$FR/tests/ci_portable.txt"
: > "$FR/tests/ci_static.txt"

out="$(cd "$FR" && $RUN --tier portable 2>&1)" && st=0 || st=$?

echo "== 1. each verdict is classified correctly =="
check() {  # check <name> <expected-verdict>
    if printf '%s' "$out" | grep -qE "^  $1 +$2( |$)"; then ok "$1 -> $2"
    else fail "$1 was not classified $2:"; printf '%s' "$out" | grep -E "^  $1" | sed 's/^/        /'; fi
}
check g_pass PASS
check g_fail FAIL
check g_skip SKIP
check g_skip_indent SKIP
check g_prose PASS
check g_skip_fail FAIL
check g_shellcrash FAIL
check g_segv_prose PASS

echo "== 2. the TALLY matches (the number a human reads) =="
printf '%s' "$out" | grep -q "PASS 3 .*SKIP 2 .*FAIL 3" \
    && ok "PASS 3  SKIP 2  FAIL 3 (the SKIP-and-exit-2 gate and the shell crash count FAIL)" \
    || fail "wrong tally: $(printf '%s' "$out" | grep -E '^PASS ' || echo '(none printed)')"

echo "== 3. a FAIL makes the runner exit nonzero =="
[ "$st" != 0 ] && ok "exit $st" || fail "the runner exited 0 with a failing gate"

echo "== 4. an all-SKIP run is not GREEN under --strict =="
printf 'g_skip\ng_skip_indent\n' > "$FR/tests/ci_portable.txt"
o2="$(cd "$FR" && $RUN --tier portable 2>&1)" && s2=0 || s2=$?
if [ "$s2" = 0 ]; then
    printf '%s' "$o2" | grep -qE "SKIP 2" && ok "without --strict: exit 0, and the tally says SKIP 2" || fail "the tally hides the skips"
else fail "a plain all-SKIP run failed; skips are legitimate without --strict"; fi
o3="$(cd "$FR" && $RUN --tier portable --strict 2>&1)" && s3=0 || s3=$?
[ "$s3" != 0 ] && ok "--strict turns SKIP into failure (exit $s3)" || fail "--strict accepted an all-SKIP run"

echo "== 5. a registered-but-missing gate is MISSING, not silently dropped =="
printf 'g_pass\nno_such_gate\n' > "$FR/tests/ci_portable.txt"
o4="$(cd "$FR" && $RUN --tier portable 2>&1)" && s4=0 || s4=$?
printf '%s' "$o4" | grep -q "MISSING" && [ "$s4" != 0 ] && ok "reported MISSING and exited nonzero" \
    || fail "a registered gate that does not exist was ignored"

echo "== 6. the anti-orphan check =="
printf 'g_pass\n' > "$FR/tests/ci_portable.txt"
mk g_orphan 0 "PASS: nobody registered me"
o5="$(cd "$FR" && $RUN --tier portable 2>&1)"
printf '%s' "$o5" | grep -q "g_orphan" && ok "an unregistered driver-free gate is named" || fail "an unregistered gate was NOT reported"
printf '%s' "$o5" | grep -q "g_needs_fake" && fail "a gate reaching the driver through a sourced lib was nagged about" \
    || ok "a driver gate (reached only through a sourced lib) is left out of the nag list"
printf '#!/bin/sh\nFAKE_BIN=x python3 fakesys/fakesys.py\n' > "$FR/tests/g_direct.sh"; chmod +x "$FR/tests/g_direct.sh"
o6="$(cd "$FR" && $RUN --tier portable 2>&1)"
printf '%s' "$o6" | grep -q "g_direct" && fail "a gate naming the driver directly was nagged about" || ok "a gate naming the driver directly is left out too"
rm -f "$FR/tests/g_orphan.sh" "$FR/tests/g_direct.sh"

echo "== 7. the static tier is gated by static_needs_env =="
# g_abs FAILS unless the input variable reached it ABSOLUTE — so its PASS
# verdict is the proof (a runner prints no output for a passing gate).
printf '#!/bin/sh\ncase "${FAKE_ROOT:-}" in /*) echo "PASS: absolute";; *) echo "FAIL: relative or unset: ${FAKE_ROOT:-}"; exit 1;; esac\n' > "$FR/tests/g_abs.sh"
chmod +x "$FR/tests/g_abs.sh"
printf 'g_pass\n' > "$FR/tests/ci_portable.txt"; printf 'g_static_pass\ng_abs\n' > "$FR/tests/ci_static.txt"
o7="$(cd "$FR" && env -u FAKE_ROOT $RUN 2>&1)" && s7=0 || s7=$?
printf '%s' "$o7" | grep -q "NOT RUN: FAKE_ROOT is unset" && printf '%s' "$o7" | grep -q "SKIP 2 " \
    && ok "FAKE_ROOT unset: the static tier is NOT RUN and its gates count as SKIP" || fail "static tier gating: $(printf '%s' "$o7" | grep -E 'NOT RUN|^PASS')"
o8="$(cd "$FR" && FAKE_ROOT=. $RUN 2>&1)" && s8=0 || s8=$?
printf '%s' "$o8" | grep -qE "^  g_static_pass +PASS" && [ "$s8" = 0 ] \
    && ok "FAKE_ROOT set: the static tier runs and the run is GREEN (exit 0)" || fail "static tier did not run: $(printf '%s' "$o8" | grep g_static_pass)"
printf '%s' "$o8" | grep -qE "^  g_abs +PASS" && ok "the input variable was made ABSOLUTE before the gates ran (g_abs fails on a relative one)" || fail "FAKE_ROOT reached the gate relative: $(printf '%s' "$o8" | grep g_abs)"
rm -f "$FR/tests/g_abs.sh"
o9="$(cd "$FR" && FAKE_ROOT=/no/such/dir $RUN 2>&1)" && s9=0 || s9=$?
[ "$s9" = 2 ] && ok "an input dir that does not resolve is refused at the entrance (exit 2)" || fail "unresolvable FAKE_ROOT accepted (exit $s9)"

echo "== 8. --list prints the registries =="
o10="$(cd "$FR" && $RUN --list 2>&1)"
printf '%s' "$o10" | grep -q "portable (1):" && printf '%s' "$o10" | grep -q "static (2):" && ok "--list: portable (1) / static (2), as §7 registered them" || fail "--list: $o10"

echo "== 9. the shipped example is GREEN and registers everything =="
oe="$(cd "$BBH_HOME/example" && "$BBH_HOME/bin/bbh-run-static" --tier portable 2>&1)" && se=0 || se=$?
[ "$se" = 0 ] && printf '%s' "$oe" | grep -q "ok: every driver-free gate is registered" && ok "example/: exit 0, nothing unregistered" \
    || { fail "the shipped example is not green:"; printf '%s\n' "$oe" | tail -8 | sed 's/^/        /'; }

echo
[ "$rc" = 0 ] && echo "PASS: the runner's verdicts mean what they say." || { echo "FAIL: see above."; exit 1; }
