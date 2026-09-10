#!/bin/sh
# test_run_static.sh — ground truth for bin/bbh-run-static, run against a
# COPY of example/ with stub gates of known verdicts through the REAL runner
# and its registries — never a copy of its logic. ROM-free, ~3 s.
#
# Lineage: VampireSaved's test_static_runner.sh (its seven sections), plus the
# two classifier cases its sweep twin added (exit 0 after a shell error is
# FAIL; a teardown segfault line is not), the static tier's gating by
# static_needs_env, --list, and (its sections 11-13) the must-fire controls
# READ and EXECUTED.
#
# MUST-FIRE: shadow-tool: reader-unplugged — a copy of the runner with the gate script no longer handed to the classifier must let section 10's declared-but-unfired stub read PASS, or section 10 was not proving the reader is in the loop
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
. "$BBH_HOME/lib/sh/controls.sh"
bbh_ctl_mode "$0"
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
FR="$T/fake"; cp -R "$BBH_HOME/example" "$FR"
RUN="$BBH_HOME/bin/bbh-run-static --config $FR/bbh.toml"
# THE SHADOW RUNNER for the must-fire (and the mode): the real runner copied
# under a throwaway home whose lib/ is the real one, with the gate script no
# longer handed to the classifier — so its controls reader is unplugged and
# nothing else differs. Built here so the mode can point RUN at it.
mkdir -p "$T/shadow/bin"; ln -s "$BBH_HOME/lib" "$T/shadow/lib"
sed 's|bbh_classify "$_st" "$WORK/$g.out" 58 "$GATES_DIR/$g.sh"|bbh_classify "$_st" "$WORK/$g.out" 58|' "$BBH_HOME/bin/bbh-run-static" > "$T/shadow/bin/bbh-run-static"
chmod +x "$T/shadow/bin/bbh-run-static"
grep -q 'bbh_classify "$_st" "$WORK/$g.out" 58$' "$T/shadow/bin/bbh-run-static" || { echo "FAIL: the shadow runner was not built (the classify line moved?)"; exit 1; }
SHADOW="$T/shadow/bin/bbh-run-static"
if bbh_ctl_is reader-unplugged; then RUN="$SHADOW --config $FR/bbh.toml"; fi

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
printf '%s' "$oe" | grep -q 'read:     fired 1 / declared 1' && printf '%s' "$oe" | grep -q 'honoured 1  lies 0' \
    && ok "example/: g_control declares one control, it fired, and its mode was HONOURED" \
    || fail "the example's declaring gate did not read fired 1 / declared 1 + honoured 1: $(printf '%s' "$oe" | grep -E 'read:|executed:' || echo '(no readout)')"

echo "== 10. the must-fire controls are READ: declared vs fired =="
# A gate that declares a control in its header and never prints CONTROL FIRED
# for it is FAIL; a CONTROL DEAD line is FAIL; a firing no header declares is
# FAIL; a gate with no declaration at all is untouched (identity for the
# gates that predate the grammar). Written by hand: mk() carries no header.
mkc() {  # mkc <name> <exit> <header-line> <output lines...>
    n="$1"; st="$2"; hdr="$3"; shift 3
    { echo "#!/bin/sh"; echo "# $n.sh — a stub"; echo "$hdr"; for l in "$@"; do echo "echo '$l'"; done; echo "exit $st"; } > "$FR/tests/$n.sh"
    chmod +x "$FR/tests/$n.sh"
}
mkc g_cfired   0 "# MUST-FIRE: perturbed-copy: flip — a flipped byte must fail" "PASS: fine" "CONTROL FIRED: flip — caught"
mkc g_cmissing 0 "# MUST-FIRE: perturbed-copy: flip — a flipped byte must fail" "PASS: fine"
mkc g_cdead    0 "# MUST-FIRE: perturbed-copy: flip — a flipped byte must fail" "PASS: fine" "CONTROL DEAD: flip — the copy passed"
mkc g_cghost   0 "# a header with no declaration" "PASS: fine" "CONTROL FIRED: ghost — nobody declared me"
mkc g_cnone    0 "# MUST-FIRE: none — a lister asserts nothing" "PASS: fine"
printf 'g_pass\ng_cfired\ng_cmissing\ng_cdead\ng_cghost\ng_cnone\n' > "$FR/tests/ci_portable.txt"
o10="$(cd "$FR" && $RUN --tier portable --exec-controls none 2>&1)" && s10=0 || s10=$?
c10() {  # c10 <gate> <verdict>
    printf '%s' "$o10" | grep -qE "^  $1 +$2( |$)" && ok "$1 -> $2" \
        || { fail "$1 not classified $2:"; printf '%s' "$o10" | grep -E "^  $1" | sed 's/^/        /'; }
}
c10 g_cfired PASS
if bbh_ctl_is reader-unplugged; then
    # THE MODE: under the shadow runner the declared-but-unfired stub must read
    # PASS — which is this gate's own FAIL (section 10 asserts FAIL below).
    printf '%s' "$o10" | grep -qE "^  g_cmissing +PASS( |$)" && echo "  (mode) the unplugged runner reads g_cmissing PASS — now failing this gate as the mode requires"
fi
c10 g_cmissing FAIL
c10 g_cdead FAIL
c10 g_cghost FAIL
c10 g_cnone PASS
c10 g_pass PASS
printf '%s' "$o10" | grep -q 'read:     fired 1 / declared 3' \
    && ok "the readout counts fired 1 / declared 3 (three declaring stubs, one fired)" \
    || fail "readout wrong: $(printf '%s' "$o10" | grep 'read:' || echo '(none)')"
printf '%s' "$o10" | grep -q 'gates declaring none: 1; undeclared: 1' \
    && ok "one none-declaring gate and one undeclared gate (g_pass) are counted, not failed" \
    || fail "the none/undeclared counts are wrong: $(printf '%s' "$o10" | grep 'read:' || echo '(none)')"
printf '%s' "$o10" | grep -q 'PASS 3 .*SKIP 0 .*FAIL 3' \
    && ok "tally PASS 3  FAIL 3 — a red controls block is plain FAIL, no fourth verdict" \
    || fail "wrong tally: $(printf '%s' "$o10" | grep -E '^PASS ' || echo '(none printed)')"
[ "$s10" != 0 ] && ok "and the runner exits nonzero ($s10)" || fail "a dead control left the runner green"

echo "== 11. the must-fire controls are EXECUTED: CONTROL=<name> must reach the gate's own FAIL =="
# Four stubs: one honours the mode (FAIL under it), one LIES (stays green),
# one REFUSES (declares a name it never reads), one DIES (a shell error under
# the mode). Only the first is a pass; the rows name the others.
mkx() {  # mkx <name> <body-under-mode>
    { echo "#!/bin/sh"; echo "# $1.sh — a stub"
      echo "# MUST-FIRE: perturbed-copy: flip — a flipped byte must fail"
      echo 'if [ "${CONTROL:-}" = flip ]; then'; echo "$2"; echo 'fi'
      echo "echo 'PASS: fine'"; echo "echo 'CONTROL FIRED: flip — caught'"; echo "exit 0"; } > "$FR/tests/$1.sh"
    chmod +x "$FR/tests/$1.sh"
}
mkx g_xhon  'echo "FAIL: the flipped input was caught"; exit 1'
mkx g_xlies 'echo "PASS: nothing changed"; exit 0'
mkx g_xref  'echo "REFUSED: CONTROL=flip is not a mode of this gate"; exit 3'
mkx g_xdied 'echo "tests/g_xdied.sh: line 9: FOO: parameter not set"; exit 0'
printf 'g_xhon\ng_xlies\ng_xref\ng_xdied\n' > "$FR/tests/ci_portable.txt"
o11="$(cd "$FR" && $RUN --tier portable 2>&1)" && s11=0 || s11=$?
for pair in "g_xlies:LIES" "g_xref:REFUSED" "g_xdied:DIED"; do
    g="${pair%%:*}"; v="${pair##*:}"
    printf '%s' "$o11" | grep -qE "^  $g +CONTROL $v: flip" && ok "$g -> CONTROL $v" \
        || { fail "$g was not reported CONTROL $v:"; printf '%s' "$o11" | grep -E "^  $g" | sed 's/^/        /'; }
done
printf '%s' "$o11" | grep -qE "^  g_xhon +CONTROL" && fail "the honoured control printed a red row" || ok "g_xhon (honoured) prints no red row"
printf '%s' "$o11" | grep -q 'executed: 4  honoured 1  lies 1  refused 1  died 1' \
    && ok "readout — executed 4, honoured 1, lies 1, refused 1, died 1" \
    || fail "executable readout wrong: $(printf '%s' "$o11" | grep 'executed:' || echo '(none)')"
printf '%s' "$o11" | grep -q 'PASS 4 .*SKIP 0 .*FAIL 3' \
    && ok "tally PASS 4  FAIL 3 — every gate passed its own run, three controls failed theirs" \
    || fail "wrong tally: $(printf '%s' "$o11" | grep -E '^PASS ' || echo '(none printed)')"
printf '%s' "$o11" | grep -q 'g_xlies(control:flip:LIES)' && ok "the failure list names the gate, the control and the verdict" \
    || fail "the failure list does not name the lying control: $(printf '%s' "$o11" | grep '^failed:' || echo '(none)')"
[ "$s11" != 0 ] && ok "and the runner exits nonzero ($s11)" || fail "a lying control left the runner green"
o11b="$(cd "$FR" && $RUN --tier portable --exec-controls none 2>&1)" && s11b=0 || s11b=$?
[ "$s11b" = 0 ] && printf '%s' "$o11b" | grep -q 'PASS 4 .*FAIL 0' && printf '%s' "$o11b" | grep -q 'executed: (off' \
    && ok "control — with --exec-controls none the same four stubs are PASS 4 and the readout says off" \
    || fail "--exec-controls none still executed or failed something: $(printf '%s' "$o11b" | grep -E '^PASS |executed' || echo '(none)')"
: > "$FR/tests/ci_portable.txt"; printf 'g_xlies\n' > "$FR/tests/ci_static.txt"
o11c="$(cd "$FR" && FAKE_ROOT=. $RUN --tier static --exec-controls portable 2>&1)" && s11c=0 || s11c=$?
[ "$s11c" = 0 ] && ok "--exec-controls portable does not execute a static-tier gate's controls" \
    || fail "--exec-controls portable executed a static gate's control: $(printf '%s' "$o11c" | grep 'CONTROL' || echo '(none)')"
: > "$FR/tests/ci_static.txt"
# a declaration-free tier prints NO readout: a consumer that has not adopted
# the grammar sees the runner it always had (fidelity F1 rests on this)
printf 'g_pass\n' > "$FR/tests/ci_portable.txt"
o11d="$(cd "$FR" && $RUN --tier portable 2>&1)" || true
printf '%s' "$o11d" | grep -q 'must-fire controls' && fail "a declaration-free tier printed the controls readout" \
    || ok "a declaration-free tier prints no controls readout"

echo "== 12. MUST-FIRE: with the controls reader unplugged, section 10's dead-control stub reads PASS =="
mkc g_cmissing 0 "# MUST-FIRE: perturbed-copy: flip — a flipped byte must fail" "PASS: fine"
printf 'g_cmissing\n' > "$FR/tests/ci_portable.txt"
o12="$(cd "$FR" && $SHADOW --config "$FR/bbh.toml" --tier portable --exec-controls none 2>&1)" || true
if printf '%s' "$o12" | grep -qE '^  g_cmissing +PASS'; then
    bbh_ctl_fired reader-unplugged "with no gate script handed to the classifier, a declared-but-unfired control reads PASS"
else
    bbh_ctl_dead reader-unplugged "the unplugged runner still failed g_cmissing: $(printf '%s' "$o12" | grep -E '^  g_cmissing')" || rc=1
fi

echo
[ "$rc" = 0 ] && echo "PASS: the runner's verdicts mean what they say." || { echo "FAIL: see above."; exit 1; }
