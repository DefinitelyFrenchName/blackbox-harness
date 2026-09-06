#!/bin/sh
# test_suite_dispatch.sh — ground truth for bin/bbh-run-suite over the fake
# driver: THE DISPATCH LOOP'S FIRST ROM-FREE GROUND TRUTH (the lineage could
# only prove its loop by running MAME). On a COPY of example/: every verdict
# line — SKIP, PENDING, NO-EXPECTATION, PASS, FAIL expected/got, the five
# masked classes, the .diverge kind, NONDETERMINISTIC, RUN-FAIL, the
# baseset/mask guard, the unregistered build — plus --freeze (writes .sha1 +
# logs, leaves authored .masked alone, RETIRES a .diverge), SUITE_ONLY, the
# hermetic scrub, the driver by name and by path, the input demand and the
# search-path fallback. ~40 s (python start-up dominated: ~20 suite runs).
#
# MUST-FIRE: a perturbed .sha1, a perturbed .masked spec and a perturbed
# .diverge frame must each turn the suite RED with the expected text; a
# POKES in the environment must NOT reach the driver through the suite
# while it demonstrably reaches it directly.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
FR="$T/ex"; cp -R "$BBH_HOME/example" "$FR"
export FAKE_ROOT="$FR"
unset FAKE_ROMPATH MASK_RANGES DUMPS POKES SNAP_FRAMES VIDEO_OUT INPUT_OUT TAIL_FRAMES INPUT_INJECT_TEST NO_INPUT_CHECK FAKE_BUILD FAKE_NONDET FAKE_CRASH_AT SUITE_ONLY 2>/dev/null || true
suite() { FAKE_ROMPATH="$FR/roms/$1" "$BBH_HOME/bin/bbh" run-suite --config "$FR/bbh.toml" "$@" 2>&1; }
# suite <image> [args...] -- runs the suite with roms/<image> fronted
suite_() { img="$1"; shift; FAKE_ROMPATH="$FR/roms/$img" "$BBH_HOME/bin/bbh" run-suite --config "$FR/bbh.toml" "$@" 2>&1; }
has() { printf '%s\n' "$1" | grep -q -- "$2"; }

echo "== 1. the four registered images are GREEN, each verdict in its own words =="
o=$(suite_ base) && s=0 || s=$?
[ "$s" = 0 ] && has "$o" "^SUITE GREEN$" && [ "$(printf '%s\n' "$o" | grep -c ' PASS$')" = 6 ] && ok "base: 6 x 'PASS' (.sha1), SUITE GREEN, exit 0" || fail "base: rc=$s $(printf '%s' "$o" | tail -3)"
has "$o" "^build fingerprint -> expectation set 'base'$" && ok "the resolved set is announced" || fail "no fingerprint line"
o=$(suite_ attract) && s=0 || s=$?
[ "$s" = 0 ] && has "$o" "^05_attract .*PASS (diverges from base at exactly 900)$" && ok "attract: the .diverge KIND — 'PASS (diverges from base at exactly 900)'" || fail "attract: rc=$s $(printf '%s' "$o" | grep 05_)"
o=$(suite_ build-a) && s=0 || s=$?
[ "$s" = 0 ] && has "$o" "^per-set mask: ff00-10000$" && ok "build-a: exit 0, the per-set mask announced" || fail "build-a rc=$s"
for want in "^01_idle .*PASS masked-exact$" \
            "^02_coin_start .*PASS masked-window (divergent frames 100, runs 1, window 260..359, 261 identical after)$" \
            "^03_press .*PASS masked-flicker (FLICKER 2 100,250 — frozen inventory)$" \
            "^04_both .*PASS masked-composite (divergent frames 101 in 2 run(s): flicker 220, windows 260-359, 261 identical after)$" \
            "^05_attract .*PASS (diverges from base/masked at exactly 900)$" \
            "^06_other_set .*SKIP (targets the other image; covered by its own suite)$"; do
    has "$o" "$want" && ok "$(printf '%s' "$want" | sed 's/^\^//; s/ \.\*/: /; s/\$$//' | cut -c1-90)" || fail "missing: $want"
done
o=$(suite_ build-b) && s=0 || s=$?
[ "$s" = 0 ] && has "$o" "set 'build-b'" && ok "build-b: the dual-key twin resolves to ITS OWN set (whole-set key) and is GREEN" || fail "build-b rc=$s"

echo "== 2. the unregistered image =="
o=$(suite_ hook) && s=0 || s=$?
[ "$s" = 1 ] && has "$o" "^UNREGISTERED build: whole-set" && has "$o" "^unregistered build fingerprint — see message above$" && ok "roms/hook: exit 1, UNREGISTERED named, the suite's own line" || fail "hook: rc=$s $o"

echo "== 3. MUST-FIRE: perturbed expectations turn the suite RED with the expected text =="
old=$(cat "$FR/expected/base/01_idle.sha1"); printf '%s\n' "0000000000000000000000000000000000000000" > "$FR/expected/base/01_idle.sha1"
o=$(suite_ base) && s=0 || s=$?
[ "$s" = 1 ] && has "$o" "^01_idle .*FAIL expected 0000000000000000000000000000000000000000 got $old$" && has "$o" "^SUITE RED$" && ok ".sha1: 'FAIL expected <frozen> got <measured>', SUITE RED, exit 1" || fail "sha1 perturbation: rc=$s $(printf '%s' "$o" | grep 01_idle)"
printf '%s\n' "$old" > "$FR/expected/base/01_idle.sha1"
printf 'flicker base/masked 2 100,251\n' > "$FR/expected/build-a/03_press.masked"
o=$(suite_ build-a) && s=0 || s=$?
[ "$s" = 1 ] && has "$o" "^03_press .*FAIL masked-flicker: got 'FLICKER 2 100,250' expected 'FLICKER 2 100,251' (frozen; drift either way is loud" && ok ".masked flicker: a moved inventory is a loud FAIL" || fail "flicker perturbation: $(printf '%s' "$o" | grep 03_press)"
printf 'flicker base/masked 2 100,250\n' > "$FR/expected/build-a/03_press.masked"
printf 'window base/masked 261 359\n' > "$FR/expected/build-a/02_coin_start.masked"
o=$(suite_ build-a) || true
has "$o" "^02_coin_start .*FAIL masked-window:" && ok ".masked window: an onset off by one is a FAIL" || fail "window perturbation: $(printf '%s' "$o" | grep 02_coin)"
printf 'window base/masked 260 359\n' > "$FR/expected/build-a/02_coin_start.masked"
printf 'base 901' > "$FR/expected/attract/05_attract.diverge"
o=$(suite_ attract) && s=0 || s=$?
[ "$s" = 1 ] && has "$o" "^05_attract .*FAIL first divergence at 900 (expected exactly 901 vs base)$" && ok ".diverge: a frame off by one is a FAIL" || fail "diverge perturbation: $(printf '%s' "$o" | grep 05_)"
printf 'base 900' > "$FR/expected/attract/05_attract.diverge"

echo "== 4. NO-EXPECTATION, PENDING, the mask guard =="
mv "$FR/expected/base/06_other_set.sha1" "$T/keep.sha1"
o=$(suite_ base) && s=0 || s=$?
[ "$s" = 1 ] && has "$o" "^06_other_set .*NO-EXPECTATION (freeze after review, as a STATE.md decision)$" && ok "no expectation file: NO-EXPECTATION, a failure" || fail "no-expectation: $(printf '%s' "$o" | grep 06_)"
mv "$T/keep.sha1" "$FR/expected/base/06_other_set.sha1"
printf 'measured: flicker 2 100,250 — awaiting ratification\n' > "$FR/expected/build-a/03_press.pending"
o=$(suite_ build-a) && s=0 || s=$?
[ "$s" = 1 ] && has "$o" "^03_press .*PENDING — not validated$" && has "$o" "^ *measured: flicker 2 100,250 — awaiting ratification$" && ok ".pending: 'PENDING — not validated' + the reason, a FAILURE (never green)" || fail "pending: $(printf '%s' "$o" | grep -A1 03_press)"
rm "$FR/expected/build-a/03_press.pending"
printf 'ff00-ff80' > "$FR/expected/build-a/mask"
o=$(suite_ build-a) && s=0 || s=$?
[ "$s" = 1 ] && has "$o" "^01_idle .*FAIL mask mismatch: this set runs$" && has "$o" "but base/masked was frozen under" && ok "a set mask differing from the basis's MASK record: 'FAIL mask mismatch' (masked bytes are skipped, so the logs are not comparable)" || fail "mask guard: $(printf '%s' "$o" | grep -A3 01_idle | head -4)"
printf 'ff00-10000' > "$FR/expected/build-a/mask"
mv "$FR/expected/base/masked/MASK" "$T/MASK"
o=$(suite_ build-a) || true
has "$o" "FAIL mask mismatch: base/masked has no MASK record (it predates them)" && ok "a record-less basis cited by a set with its own mask is refused" || fail "record-less basis: $(printf '%s' "$o" | grep 01_idle)"
mv "$T/MASK" "$FR/expected/base/masked/MASK"

echo "== 5. NONDETERMINISTIC and RUN-FAIL =="
o=$(FAKE_NONDET=1 suite_ base) && s=0 || s=$?
[ "$s" = 1 ] && has "$o" "^01_idle .*NONDETERMINISTIC (first divergent frame below)$" && has "$o" "^SUITE RED$" && ok "two differing runs: NONDETERMINISTIC (the diff's first lines follow), RED" || fail "nondet: $(printf '%s' "$o" | grep -A2 01_idle | head -3)"
o=$(FAKE_CRASH_AT=50 suite_ base) && s=0 || s=$?
[ "$s" = 1 ] && has "$o" "^01_idle .*GUARD TRIPPED:$" && has "$o" "^RUN-FAIL$" && ok "a driver that fails (the crash exit): its own lines, then RUN-FAIL" || fail "run-fail: $(printf '%s' "$o" | grep -A3 01_idle | head -4)"

echo "== 6. the hermetic scrub =="
o=$(POKES="50:1000:ff" suite_ base) && s=0 || s=$?
[ "$s" = 0 ] && ok "POKES in the caller's shell does not reach the driver through the suite (still GREEN)" || fail "hermetic: rc=$s"
FAKE_ROMPATH="$FR/roms/base" "$BBH_HOME/drivers/fake.sh" fake "$FR/replays/01_idle.rpl" "$T/h1.log" > /dev/null
FAKE_ROMPATH="$FR/roms/base" POKES="50:1000:ff" "$BBH_HOME/drivers/fake.sh" fake "$FR/replays/01_idle.rpl" "$T/h2.log" > /dev/null
cmp -s "$T/h1.log" "$T/h2.log" && fail "MUST-FIRE: the poke did not move the log even directly" || ok "MUST-FIRE: the same POKES DOES move the log when the driver is called directly"

echo "== 7. --freeze =="
# re-point build-b's whole-set row at an EMPTY set, so the freeze starts
# from nothing (the registry row is the build decision; the set is what
# --freeze fills)
sed -i.bak "s/	build-b	/	bb-fresh	/" "$FR/expected/registry.tsv"
o=$(suite_ build-b --freeze) && s=0 || s=$?
[ "$s" = 0 ] && [ "$(printf '%s\n' "$o" | grep -c ' frozen [0-9a-f]\{40\}$')" = 6 ] && [ -f "$FR/expected/bb-fresh/01_idle.sha1" ] && [ -f "$FR/expected/bb-fresh/logs/01_idle.log" ] \
    && ok "--freeze on an empty set: 6 x 'frozen <sha>', .sha1 + logs/ written" || fail "freeze: rc=$s $(printf '%s' "$o" | tail -3); $(ls "$FR/expected/bb-fresh" 2>/dev/null)"
o=$(suite_ build-b) && s=0 || s=$?
[ "$s" = 0 ] && has "$o" "^SUITE GREEN$" && ok "…and the frozen set is GREEN on the next plain run" || fail "post-freeze run: rc=$s"
printf 'ff00-10000' > "$FR/expected/bb-fresh/mask"; printf 'exact base/masked -\n' > "$FR/expected/bb-fresh/01_idle.masked"; rm "$FR/expected/bb-fresh/01_idle.sha1"
printf 'base 42' > "$FR/expected/bb-fresh/02_coin_start.diverge"
o=$(suite_ build-b --freeze) && s=0 || s=$?
has "$o" "^01_idle .*authored .masked expectation — not self-frozen$" && [ ! -f "$FR/expected/bb-fresh/01_idle.sha1" ] && ok "an authored .masked is left alone by --freeze (no .sha1 written)" || fail "freeze vs masked: $(printf '%s' "$o" | grep 01_idle)"
has "$o" "^02_coin_start .*RETIRED 02_coin_start.diverge (base 42)$" && has "$o" "^  -> kept as 02_coin_start.diverge.superseded; the new .sha1 now governs.$" && [ -f "$FR/expected/bb-fresh/02_coin_start.diverge.superseded" ] && [ ! -f "$FR/expected/bb-fresh/02_coin_start.diverge" ] \
    && ok "a self-frozen .diverge is RETIRED to .diverge.superseded (dispatch consults it first)" || fail "retire: $(printf '%s' "$o" | grep -A2 02_coin)"
mv "$FR/expected/registry.tsv.bak" "$FR/expected/registry.tsv"

echo "== 8. SUITE_ONLY, the driver by path, the input demand, the search-path fallback =="
o=$(SUITE_ONLY="01_idle 03_press" suite_ base) && s=0 || s=$?
has "$o" "^FILTERED RUN (SUITE_ONLY) — not a suite verdict$" && [ "$(printf '%s\n' "$o" | grep -c ' PASS$')" = 2 ] && ok "SUITE_ONLY: FILTERED announced, only the named replays run" || fail "SUITE_ONLY: $o"
cp "$BBH_HOME/drivers/fake.sh" "$FR/mydriver.sh"; chmod +x "$FR/mydriver.sh"
o=$(suite_ base --driver ./mydriver.sh) && s=0 || s=$?
[ "$s" = 0 ] && ok "--driver <path> (has a slash): a consumer's own driver, relative to its root" || fail "driver by relative path rc=$s $(printf '%s' "$o" | head -2)"
o=$(suite_ base --driver mydriver) && s=0 || s=$?
[ "$s" = 1 ] && has "$o" "drivers/mydriver.sh' is not executable" && ok "--driver <bare name>: a HARNESS driver (drivers/<name>.sh) — a name that is not one is refused" || fail "bare name rc=$s $o"
o=$(suite_ base --driver "$FR/mydriver.sh") && s=0 || s=$?
[ "$s" = 0 ] && ok "--driver </abs/path>" || fail "driver by absolute path rc=$s"
chmod -x "$FR/mydriver.sh"
o=$(suite_ base --driver ./mydriver.sh) && s=0 || s=$?
[ "$s" = 1 ] && has "$o" "^FAIL: driver .*mydriver.sh' is not executable" && ok "a driver that is not executable is refused at the entrance" || fail "non-exec driver rc=$s $o"
o=$(env -u FAKE_ROOT "$BBH_HOME/bin/bbh" run-suite --config "$FR/bbh.toml" 2>&1) && s=0 || s=$?
[ "$s" = 1 ] && [ "$o" = "FAIL: set FAKE_ROOT to the reference-input directory" ] && ok "the input variable is demanded: 'FAIL: set FAKE_ROOT …', exit 1" || fail "input demand: rc=$s '$o'"
o=$(env -u FAKE_ROMPATH FAKE_ROOT="$FR/roms/base" "$BBH_HOME/bin/bbh" run-suite --config "$FR/bbh.toml" 2>&1) && s=0 || s=$?
[ "$s" = 0 ] && has "$o" "set 'base'" && ok "no search-path variable: the input directory is the search path (base resolves)" || fail "rompath fallback rc=$s $(printf '%s' "$o" | head -2)"
o=$(suite_ base nosuch) && s=0 || s=$?
[ "$s" = 1 ] && has "$o" "nosuch.zip not found in rompath" && ok "a positional set name that resolves nowhere fails loudly" || fail "positional set rc=$s $o"

echo
[ "$rc" = 0 ] && echo "PASS: the suite's verdicts mean what they say, ROM-free" || { echo "FAIL: see above"; exit 1; }
