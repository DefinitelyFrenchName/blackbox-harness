#!/bin/sh
# test_run_sweep.sh — ground truth for bin/bbh-run-sweep: a synthetic repo of
# stub gates with KNOWN verdicts, a consumer config, driven through the REAL
# runner — never a copy of its logic. ROM-free, ~45 s (three deliberately slow
# gates: the timeout, the per-row timeout, the lane boundary).
#
# Lineage: VampireSaved's test_emulator_runner.sh, its thirteen sections
# carried: the three verdicts + SKIP-in-prose + MISSING; placeholders reaching
# argv and VAR=value tokens becoming environment; the anti-orphan check both
# ways; --strict; the prereq STOP and --keep-going; --scope all; cadence and
# --freeze naming what it dropped; TIMEOUT; --lane accumulating; a lane
# waiting for its own gates under --jobs; the env default exported with its
# must-fire control; exit 0 after a shell error; the per-row timeout and the
# per-slot scratch. Plus H4's own: --resume, --only, the precondition hook.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
rc=0
fail() { echo "  FAIL: $*"; rc=1; }
ok()   { echo "  ok: $*"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
FR="$T/fakerepo"
mkdir -p "$FR/tests/lib" "$FR/tools" "$FR/build/fake_merged/rompath" "$T/roms"
unset MAME_BIN JTSIM_SCRATCH ROMDIR MERGED 2>/dev/null || true

cat > "$FR/bbh.toml" <<EOF
[project]
root = "."
instrument_word = "emulator"
[registries]
sweep = "tests/ci_emulator.tsv"
[tier]
patterns = ['MAME_BIN']
[sweep]
lanes = ["prereq", "fbneo", "mame", "mister"]
default_lanes = ["prereq", "fbneo", "mame"]
prereq_lane = "prereq"
release_scope = "release"
cadences = ["romset", "bitstream"]
freeze_cadence = "romset"
cadence_drop_note = ["These follow the bitstream, not the romset.", ">> IS THIS FREEZE TARGETING THE CORE?"]
default_timeout = 5400
precondition = 'python3 tools/audit_roms.py "\$ROMDIR" > /dev/null'
precondition_fail_text = "ROM audit FAILED — stop"
input_env = "ROMDIR"
log_dir_prefix = "build/emu_sweep_"
placeholders = { MERGED = "build/fake_merged", DON = "build/fake_don" }
rompath_placeholder_suffix = "_RP"
rompath_suffix = "/rompath"
build_sets = ["vsavjw", "vsavj"]
instruments = [["mame-wide", "MAME_WIDE_BIN", "\$HOME/nowhere/mame"], ["fbneo", "", "\$REPO/emu/fbneo/fbneo"]]
env_defaults = [["MAME_BIN", "mame-wide"]]
scratch_lanes = ["mister"]
scratch_env = "JTSIM_SCRATCH"
scratch_default = "fake-jtsim"
prereq_cite = "[CPE-24]"
EOF
printf '#!/usr/bin/env python3\nimport sys\n' > "$FR/tools/audit_roms.py"; chmod +x "$FR/tools/audit_roms.py"
: > "$FR/tests/ci_portable.txt"; : > "$FR/tests/ci_static.txt"

mk() {  # mk <name> <exit> <line...> — a stub gate the tier classifier calls instrument-tier
    n="$1"; st="$2"; shift 2
    { echo "#!/bin/sh"
      echo ': "${MAME_BIN:-}"   # emulator-tier marker for the classifier'
      echo 'echo "argv: $*"'
      for l in "$@"; do echo "echo '$l'"; done
      echo "exit $st"; } > "$FR/tests/$n.sh"
    chmod +x "$FR/tests/$n.sh"
}
mk g_pass    0 "all good"
mk g_fail    1 "something broke" "FAIL: nope"
mk g_skip    0 "SKIP: no build at build/nope"
mk g_prose   0 "checked 3 things, none had to be skipped"
mk g_skipfail 2 "  SKIPPED: no reference binary" "PARTIAL: the invariant was NOT run"
mk g_out     0 "an out-of-release-scope gate ran"
mk g_args    0 "argument check"
mk g_prereq  0 "the instrument is sound"
printf '#!/bin/sh\n: "${MAME_BIN:-}"\nsleep 30\n' > "$FR/tests/g_slow.sh"; chmod +x "$FR/tests/g_slow.sh"
printf '#!/bin/sh\nexit 0\n' > "$FR/tests/g_noexec.sh"; chmod 644 "$FR/tests/g_noexec.sh"
mk g_orphan  0 "nobody registered me"

reg() { { echo "# fake registry"; for r in "$@"; do printf '%s\n' "$r"; done; } > "$FR/tests/ci_emulator.tsv"; }
row()  { printf '%s\t%s\t%s\tromset\t%s\t%s' "$1" "$2" "$3" "$4" "$5"; }
rowc() { printf '%s\t%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4" "$5" "$6"; }
run() { (cd "$FR" && ROMDIR="$T/roms" "$BBH_HOME/bin/bbh-run-sweep" --config bbh.toml "$@" 2>&1); }

echo "1. the three verdicts, plus SKIP-in-prose and MISSING"
reg "$(row g_pass mame release - '')" "$(row g_fail mame release - '')" "$(row g_skip mame release - '')" \
    "$(row g_prose mame release - '')" "$(row g_noexec mame release - '')" "$(row g_out mame out - 'momentary: a stub')" \
    "$(row g_args mame release '%MERGED_RP% %DON% EXTRA=1' '')" "$(row g_orphan mame release - '')" "$(row g_skipfail mame release - '')"
out="$(run --log "$T/l1" || true)"
line="$(printf '%s\n' "$out" | grep -E '^PASS ' || true)"
case "$line" in *"PASS 4 "*) ok "PASS counted 4 (g_pass, g_prose, g_args, g_orphan): $line" ;; *) fail "expected PASS 4, got: $line" ;; esac
case "$line" in *"FAIL 2 "*) ok "a SKIP marker with a NON-ZERO exit counts FAIL, not SKIP" ;; *) fail "expected FAIL 2, got: $line" ;; esac
case "$line" in *"SKIP 1 "*) ok "SKIP counted separately from PASS" ;; *) fail "expected SKIP 1, got: $line" ;; esac
case "$line" in *"MISSING 1"*) ok "a non-executable registered gate is MISSING" ;; *) fail "expected MISSING 1, got: $line" ;; esac
printf '%s\n' "$out" | grep -q "g_out" && fail "an \`out\` row ran under the release scope" || ok "the release scope excluded the out-of-scope row"
printf '%s\n' "$out" | grep -qE '^GREEN' && fail "a run with a FAIL printed GREEN" || ok "a run with a FAIL is NOT GREEN"
printf '%s\n' "$out" | grep -q "^== the emulator-tier sweep ==" && ok "the banner uses the consumer's instrument word" || fail "banner: $(printf '%s\n' "$out" | head -1)"
printf '%s\n' "$out" | grep -q "^    MERGED  build/fake_merged        vsavj  ?" && ok "builds under test: a present dir is fingerprinted (no zip -> '?'), the set from build_sets" || fail "builds banner: $(printf '%s\n' "$out" | grep MERGED)"
printf '%s\n' "$out" | grep -q "^    DON     build/fake_don           ABSENT" && ok "…and an absent dir says ABSENT" || fail "absent banner: $(printf '%s\n' "$out" | grep 'DON ')"

echo "2. placeholders reach the gate's argv; VAR=value becomes environment"
grep -q "argv: build/fake_merged/rompath build/fake_don" "$T/l1/g_args.log" 2>/dev/null && ok "%MERGED_RP% and %DON% expanded into argv (the _RP suffix first)" || fail "placeholders: $(grep argv "$T/l1/g_args.log" 2>/dev/null)"
grep -q "cmd: env EXTRA=1 tests/g_args.sh" "$T/l1/g_args.log" 2>/dev/null && ok "a VAR=value token became environment, not a positional" || fail "VAR=value: $(grep cmd: "$T/l1/g_args.log")"
o2b="$(cd "$FR" && ROMDIR="$T/roms" MERGED=build/other "$BBH_HOME/bin/bbh-run-sweep" --config bbh.toml --list --only g_args 2>&1)"
printf '%s\n' "$o2b" | grep -q "build/other/rompath build/fake_don" && ok "an environment variable of the placeholder's name overrides its default" || fail "env override: $o2b"

echo "3. the anti-orphan check, both directions"
mk g_orphan2 0 "no row for me"
out2="$(run --log "$T/l2" || true)"
printf '%s\n' "$out2" | grep -q "g_orphan2" && ok "an instrument-tier gate with no row is reported UNREGISTERED" || fail "the unregistered gate was not reported"
reg "$(row g_pass mame release - '')" "$(row g_gone mame release - '')"
out3="$(run --log "$T/l3" || true)"
printf '%s\n' "$out3" | grep -q "DEAD ROW" && ok "a row whose script is gone is reported DEAD" || fail "a dead registry row was not reported"
rm -f "$FR/tests/g_orphan2.sh"

echo "4. --strict makes SKIP and an unregistered gate fatal"
reg "$(row g_pass mame release - '')" "$(row g_skip mame release - '')"
run --strict --log "$T/l4" >/dev/null 2>&1 && fail "--strict returned 0 with a SKIP present" || ok "--strict is non-zero on SKIP"
run --log "$T/l5" >/dev/null 2>&1 && ok "without --strict the same run is zero (SKIP is reported, not fatal)" || fail "a PASS+SKIP run failed without --strict"
reg "$(row g_pass mame release - '')"
run --strict --log "$T/l5b" >/dev/null 2>&1 && fail "--strict returned 0 with g_orphan unregistered" || ok "--strict is non-zero on an UNREGISTERED gate"

echo "5. a red prereq STOPS the run"
mk g_prereq_bad 1 "the instrument moved" "FAIL: parity lost"
reg "$(row g_prereq_bad prereq release - '')" "$(row g_pass mame release - '')" "$(row g_orphan mame release - '')"
out6="$(run --log "$T/l6" || true)"
printf '%s\n' "$out6" | grep -q "STOP: the prereq lane is not green" && ok "the run stopped at the prereq lane" || fail "a red prereq did not stop the run"
printf '%s\n' "$out6" | grep -q "not evidence (\[CPE-24\])" && ok "…citing the consumer's prereq_cite" || fail "cite: $(printf '%s\n' "$out6" | grep evidence)"
printf '%s\n' "$out6" | grep -q "== mame lane" && fail "the mame lane ran after a red prereq" || ok "no later lane ran after a red prereq"
out7="$(run --keep-going --log "$T/l7" || true)"
printf '%s\n' "$out7" | grep -q "== mame lane" && ok "--keep-going runs the later lanes anyway" || fail "--keep-going did not continue past the prereq lane"

echo "6. --scope all includes the out-of-release-scope rows; --only selects"
reg "$(row g_pass mame release - '')" "$(row g_out mame out - 'momentary: a stub')" "$(row g_orphan mame release - '')"
out8="$(run --scope all --log "$T/l8" || true)"
printf '%s\n' "$out8" | grep -q "g_out .*PASS" && ok "--scope all ran the out-of-scope row" || fail "--scope all did not run the out-of-scope row"
out8b="$(run --scope all --only 'g_o*' --log "$T/l8b" || true)"
[ "$(printf '%s\n' "$out8b" | grep -cE '^  g_(out|orphan) +PASS')" = 2 ] && ! printf '%s\n' "$out8b" | grep -q "g_pass .*PASS" && ok "--only 'g_o*' ran exactly the two matching gates" || fail "--only: $(printf '%s\n' "$out8b" | grep -E '^  g_')"

echo "6b. CADENCE selects independently of scope, and --freeze ASKS the question"
reg "$(row g_pass mame release - '')" "$(rowc g_bits mister release bitstream - 'a bitstream-cadence gate')" "$(row g_orphan mame release - '')"
outc="$(run --lane mame --lane mister --log "$T/lc" || true)"
printf '%s\n' "$outc" | grep -q "g_bits" && ok "cadence=all (the default) runs the bitstream row" || fail "the default cadence did NOT run the bitstream row"
outf="$(run --lane mame --lane mister --freeze --log "$T/lf" || true)"
printf '%s\n' "$outf" | grep -q "g_bits .*PASS" && fail "--freeze RAN a bitstream-cadence gate" || ok "--freeze excluded the bitstream-cadence gate"
printf '%s\n' "$outf" | grep -q "CADENCE: bitstream gates DROPPED" && ok "--freeze NAMED the dropped cadence" || fail "--freeze dropped silently"
printf '%s\n' "$outf" | grep -q "^     g_bits" && ok "…and the dropped gate by name" || fail "dropped gate not named"
printf '%s\n' "$outf" | grep -q "IS THIS FREEZE TARGETING THE CORE?" && ok "…with the consumer's cadence_drop_note" || fail "the note was not printed"
printf '%s\n' "$outf" | grep -q "g_pass .*PASS" && ok "--freeze kept the romset-cadence gate" || fail "--freeze dropped a ROMSET-cadence gate"

echo "7. a gate that overruns --timeout is TIMEOUT, not PASS"
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
    reg "$(row g_slow mame release - '')" "$(row g_orphan mame release - '')"
    out9="$(run --timeout 2 --log "$T/l9" || true)"
    case "$(printf '%s\n' "$out9" | grep -E '^PASS ' || true)" in *"TIMEOUT 1"*) ok "an overrunning gate is TIMEOUT" ;; *) fail "expected TIMEOUT 1: $(printf '%s\n' "$out9" | grep -E '^PASS ')" ;; esac
    grep -q "TIMEOUT	.*killed after 2s" "$T/l9/results.tsv" && ok "…with the lineage's detail 'killed after 2s'" || fail "detail: $(grep g_slow "$T/l9/results.tsv")"
else
    echo "  note: no timeout(1) — TIMEOUT case not exercised"
fi

echo "8. --lane ACCUMULATES"
reg "$(row g_pass mame release - '')" "$(row g_prereq fbneo release - '')" "$(row g_orphan mame release - '')"
out10="$(run --lane fbneo --lane mame --log "$T/l10" || true)"
printf '%s\n' "$out10" | grep -q "== fbneo lane" && printf '%s\n' "$out10" | grep -q "== mame lane" && ok "two --lane flags select BOTH lanes" || fail "two --lane flags did not select both lanes"
out11="$(run --lane mame --lane mame --log "$T/l11" || true)"
[ "$(printf '%s\n' "$out11" | grep -c '== mame lane')" = 1 ] && ok "a repeated --lane is not run twice" || fail "a repeated --lane ran the lane more than once"
printf '%s\n' "$out10" | grep -q "^  lanes      fbneo mame$" && ok "…in the order given" || fail "lane order: $(printf '%s\n' "$out10" | grep lanes)"

echo "9. a lane WAITS for its own gates (--jobs > 1)"
{ echo '#!/bin/sh'; echo ': "${MAME_BIN:-}"'; echo 'sleep 3'; echo 'echo slow-done'; } > "$FR/tests/g_slow3.sh"; chmod +x "$FR/tests/g_slow3.sh"
reg "$(row g_slow3 fbneo release - '')" "$(row g_pass mame release - '')" "$(row g_orphan mame release - '')"
out12="$(run --jobs 4 --log "$T/l12" || true)"
slow_line="$(printf '%s\n' "$out12" | grep -n 'g_slow3 ' | head -1 | cut -d: -f1)"
mame_line="$(printf '%s\n' "$out12" | grep -n '== mame lane' | head -1 | cut -d: -f1)"
[ -n "$slow_line" ] && [ -n "$mame_line" ] && [ "$slow_line" -lt "$mame_line" ] && ok "a lane's gates finish before the next lane is announced" || fail "lane boundary crossed"
awk -F'\t' 'NR>1 && $1=="g_slow3" && $2=="fbneo"' "$T/l12/results.tsv" | grep -q . && ok "its result is recorded under its OWN lane" || fail "g_slow3 filed wrong"

echo "10. --resume skips gates already in results.tsv"
reg "$(row g_pass mame release - '')" "$(row g_prose mame release - '')" "$(row g_orphan mame release - '')"
run --only g_pass --log "$T/l10r" >/dev/null 2>&1 || true
out10r="$(run --resume --log "$T/l10r" || true)"
printf '%s\n' "$out10r" | grep -q "g_pass .*(resumed: already in results.tsv)" && printf '%s\n' "$out10r" | grep -q "g_prose .*PASS" \
    && [ "$(awk -F'\t' 'NR>1 && $1=="g_pass"' "$T/l10r/results.tsv" | wc -l | tr -d ' ')" = 1 ] && ok "--resume: the done gate is announced as resumed, the rest run, results.tsv keeps one row per gate" || fail "resume: $(printf '%s\n' "$out10r" | grep -E 'g_pass|g_prose')"

echo "11. the runner EXPORTS the env default, and a caller's value wins"
printf '#!/bin/sh\necho "mame_bin=${MAME_BIN:-UNSET}"\nexit 0\n' > "$FR/tests/g_mamebin.sh"; chmod +x "$FR/tests/g_mamebin.sh"
reg "$(row g_mamebin mame release - '')"
out11a="$( (unset MAME_BIN; MAME_WIDE_BIN="$T/fake_wide" run --lane mame --only g_mamebin --log "$T/l11a") )"
grep -q "mame_bin=$T/fake_wide" "$T/l11a/g_mamebin.log" 2>/dev/null && printf '%s' "$out11a" | grep -q "MAME_BIN.*(runner default)" \
    && ok "unset by the caller -> the gate receives the instrument, and the log says 'runner default'" || fail "runner default not delivered: $(grep mame_bin "$T/l11a/g_mamebin.log" 2>/dev/null)"
printf '%s' "$out11a" | grep -q "^    mame-wide  $T/fake_wide   MISSING" && ok "the instruments banner names the override and says MISSING for a path that is not executable" || fail "instruments banner: $(printf '%s' "$out11a" | grep mame-wide)"
out11b="$( MAME_BIN="$T/caller_mame" MAME_WIDE_BIN="$T/fake_wide" run --lane mame --only g_mamebin --log "$T/l11b" )"
grep -q "mame_bin=$T/caller_mame" "$T/l11b/g_mamebin.log" 2>/dev/null && printf '%s' "$out11b" | grep -q "MAME_BIN.*(set by the caller)" \
    && ok "set by the caller -> the caller's value wins, and the log says so" || fail "caller's MAME_BIN not honoured"
# MUST-FIRE CONTROL: a copy of the runner with the export line removed must
# leave the gate UNSET — the assertion depends on the export, not on the env.
sed '/# ENV-DEFAULT-EXPORT$/d' "$BBH_HOME/bin/bbh-run-sweep" > "$T/sweep_noexport"; chmod +x "$T/sweep_noexport"
(cd "$FR" && unset MAME_BIN && ROMDIR="$T/roms" MAME_WIDE_BIN="$T/fake_wide" "$T/sweep_noexport" --config bbh.toml --lane mame --only g_mamebin --log "$T/l11c" >/dev/null 2>&1) || true
grep -q "mame_bin=UNSET" "$T/l11c/g_mamebin.log" 2>/dev/null && ok "control fires: without the export line the gate reports UNSET" || fail "control did not fire: $(grep mame_bin "$T/l11c/g_mamebin.log" 2>/dev/null)"
rm -f "$FR/tests/g_mamebin.sh"

echo "12. exit 0 after a SHELL ERROR is FAIL; a teardown segfault line is not"
printf '#!/bin/sh\n: "${MAME_BIN:-}"\necho "tests/g_shellcrash.sh: line 3: FOO: set FOO to a dir OUTSIDE the repo"\nexit 0\n' > "$FR/tests/g_shellcrash.sh"
printf '#!/bin/sh\n: "${MAME_BIN:-}"\necho "PASS: the summary line"\necho "tests/g_segv.sh: line 64:  2444 Segmentation fault: 11  REPLAY=x"\nexit 0\n' > "$FR/tests/g_segv.sh"
chmod +x "$FR/tests/g_shellcrash.sh" "$FR/tests/g_segv.sh"
reg "$(row g_shellcrash mame release - '')" "$(row g_segv mame release - '')"
run --lane mame --log "$T/l12b" >/dev/null 2>&1 || true
v12a="$(awk -F'\t' '$1=="g_shellcrash"{print $4}' "$T/l12b/results.tsv")"; v12b="$(awk -F'\t' '$1=="g_segv"{print $4}' "$T/l12b/results.tsv")"
[ "$v12a" = FAIL ] && ok "a shell-error line with exit 0 is FAIL" || fail "shell-error crash classified '$v12a'"
[ "$v12b" = PASS ] && ok "a teardown segfault line after the summary stays PASS" || fail "the benign segfault shape classified '$v12b'"
rm -f "$FR/tests/g_shellcrash.sh" "$FR/tests/g_segv.sh"

echo "13. a row's 7th column is its timeout; --jobs N on a scratch lane hands each slot its own scratch"
printf '#!/bin/sh\n: "${MAME_BIN:-}"\nsleep 20\necho PASS\n' > "$FR/tests/g_long.sh"; chmod +x "$FR/tests/g_long.sh"
printf '#!/bin/sh\n: "${MAME_BIN:-}"\necho "scratch=${JTSIM_SCRATCH:-UNSET}"\nsleep 2\necho PASS\n' > "$FR/tests/g_slotA.sh"
cp "$FR/tests/g_slotA.sh" "$FR/tests/g_slotB.sh"; chmod +x "$FR/tests/g_slotA.sh" "$FR/tests/g_slotB.sh"
reg "$(rowc g_long mame release romset - 'a slow gate')	2" "$(row g_pass mame release - '')"
run --lane mame --timeout 60 --log "$T/l13a" >/dev/null 2>&1 || true
[ "$(awk -F'\t' '$1=="g_long"{print $4}' "$T/l13a/results.tsv")" = TIMEOUT ] && ok "a 2-second 7th column killed a 20-second gate under a 60-second --timeout" || fail "per-row timeout not applied"
[ "$(awk -F'\t' '$1=="g_pass"{print $4}' "$T/l13a/results.tsv")" = PASS ] && ok "a 6-column row still runs under the global --timeout" || fail "6-column row"
reg "$(rowc g_slotA mister release romset - 'slot a')" "$(rowc g_slotB mister release romset - 'slot b')"
(cd "$FR" && ROMDIR="$T/roms" JTSIM_SCRATCH="$T/scratch" "$BBH_HOME/bin/bbh-run-sweep" --config bbh.toml --lane mister --jobs 2 --log "$T/l13b" > "$T/o13b" 2>&1) || true
sA="$(grep -h '^scratch=' "$T/l13b/g_slotA.log" 2>/dev/null)"; sB="$(grep -h '^scratch=' "$T/l13b/g_slotB.log" 2>/dev/null)"
[ "$sA" = "scratch=$T/scratch" ] && [ "$sB" = "scratch=$T/scratch-slot1" ] && ok "--jobs 2 on the scratch lane: slot 0 keeps the base scratch, slot 1 gets <base>-slot1" || fail "per-slot scratch: A='$sA' B='$sB'"
grep -q "^  scratch    $T/scratch (mister slot 0), $T/scratch-slot1 (slots 1..1)" "$T/o13b" 2>/dev/null || grep -q "^  scratch    $T/scratch (mister slot 0), $T/scratch-slotN (slots 1..1)" "$T/o13b" \
    && ok "…and the banner names the scratch layout" || fail "scratch banner: $(grep scratch "$T/o13b")"
(cd "$FR" && ROMDIR="$T/roms" JTSIM_SCRATCH="$T/scratch" "$BBH_HOME/bin/bbh-run-sweep" --config bbh.toml --lane mister --jobs 1 --log "$T/l13c" >/dev/null 2>&1) || true
[ "$(grep -h '^scratch=' "$T/l13c/g_slotB.log" 2>/dev/null)" = "scratch=$T/scratch" ] && ok "--jobs 1: every gate keeps the caller's scratch" || fail "serial scratch changed"
(cd "$FR" && ROMDIR="$T/roms" "$BBH_HOME/bin/bbh-run-sweep" --config bbh.toml --lane mister --jobs 2 --log "$T/l13d" >/dev/null 2>&1) || true
[ "$(grep -h '^scratch=' "$T/l13d/g_slotA.log" 2>/dev/null)" = "scratch=${TMPDIR:-/tmp}/fake-jtsim" ] && ok "the scratch variable unset: slot 0 gets \${TMPDIR:-/tmp}/<scratch_default>" || fail "scratch default: $(grep -h '^scratch=' "$T/l13d/g_slotA.log" 2>/dev/null)"
rm -f "$FR/tests/g_long.sh" "$FR/tests/g_slotA.sh" "$FR/tests/g_slotB.sh"

echo "14. the precondition hook and the input demand"
printf '#!/usr/bin/env python3\nimport sys; sys.exit(1)\n' > "$FR/tools/audit_roms.py"
reg "$(row g_pass mame release - '')"
out14="$(run --log "$T/l14" || true)"
printf '%s\n' "$out14" | grep -q "^ROM audit FAILED — stop$" && ! printf '%s\n' "$out14" | grep -q "g_pass" && ok "a failing precondition stops the run before any gate, with the consumer's text" || fail "precondition: $(printf '%s\n' "$out14" | head -2)"
printf '#!/usr/bin/env python3\nimport sys\n' > "$FR/tools/audit_roms.py"
out14b="$(cd "$FR" && "$BBH_HOME/bin/bbh-run-sweep" --config bbh.toml --log "$T/l14b" 2>&1)" && fail "no ROMDIR was accepted" || { printf '%s\n' "$out14b" | grep -q "set ROMDIR — every gate here reads the reference input" && ok "the input variable is demanded (after --list, which needs none)" || fail "input demand: $out14b"; }
out14c="$(cd "$FR" && "$BBH_HOME/bin/bbh-run-sweep" --config bbh.toml --list 2>&1)" && printf '%s\n' "$out14c" | grep -q "^lanes=prereq fbneo mame scope=release cadence=all only=\*  (1 gates)$" && ok "--list needs no input and prints the lineage's summary line" || fail "--list: $out14c"

echo "15. the shipped example sweeps GREEN, --scope all"
oe="$(cd "$BBH_HOME/example" && FAKE_ROOT=. "$BBH_HOME/bin/bbh" run-sweep --scope all --strict --log "$T/lex" 2>&1)" && se=0 || se=$?
[ "$se" = 0 ] && printf '%s\n' "$oe" | grep -q "^GREEN" && printf '%s\n' "$oe" | grep -q "ok: every driver-tier gate has exactly one registry row" && ok "example/: prereq + fake lanes GREEN under --strict, registry complete both ways" || { fail "the example sweep is not green:"; printf '%s\n' "$oe" | tail -12 | sed 's/^/        /'; }

echo
[ "$rc" = 0 ] && echo "PASS: bbh-run-sweep classifies every ground-truth case correctly" || { echo "FAIL: see above"; exit 1; }
