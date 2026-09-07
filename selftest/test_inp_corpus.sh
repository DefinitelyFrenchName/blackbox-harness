#!/bin/sh
# test_inp_corpus.sh — ground truth for bin/bbh-inp-corpus, ROM-FREE: a STUB
# emulator answers each recording of a fabricated corpus with a canned
# playback, so every verdict line the corpus gate can print is exercised —
# clean, a crash with its NOTE, a DEFECT declared and matching (OPEN), a
# DEFECT that no longer matches (the capture rotted), a dead run, a
# recording without its .inp, --only, an empty corpus — plus the liveness
# controls the tool runs on itself. The lineage's verdict texts, verbatim.
# ~3 s.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
unset BUILD ONLY MAME_BIN MAX_FRAMES BBH_PROFILE 2>/dev/null || true

# the stub: the recording name selects a canned (stdout, log) pair
cat > "$T/stub" <<'EOF'
#!/bin/sh
name=""; i=0; for a in "$@"; do i=$((i+1)); [ "$a" = "-playback" ] && name="$(eval echo \${$((i+1))})"; done
name="${name%.inp}"
[ -f "$STUB_DIR/$name.log" ] && cp "$STUB_DIR/$name.log" "$CHECKSUM_OUT"
[ -f "$STUB_DIR/$name.out" ] && cat "$STUB_DIR/$name.out"
exit 0
EOF
chmod +x "$T/stub"; export STUB_DIR="$T/canned"; mkdir -p "$STUB_DIR"
canned() {  # canned <name> <frames> [crash-line]
    printf 'ALIVE 600 match=00040000 p1=13 p2=10\n' > "$STUB_DIR/$1.log"
    [ -n "${3:-}" ] && printf '%s\nREGS D0=0\nEND 700 crashes=1 filtered_writes=3\n' "$3" >> "$STUB_DIR/$1.log"
    printf 'Total playback frames: %s\n' "$2" > "$STUB_DIR/$1.out"
}
rec() {  # rec <name> <note>
    mkdir -p "$T/root/tests/inp/$1/nvram"; : > "$T/root/tests/inp/$1/$1.inp"; printf '%s\n' "$2" > "$T/root/tests/inp/$1/NOTE"
}
mkdir -p "$T/root/build/m1/rompath" "$T/ref"; : > "$T/root/build/m1/rompath/fake.zip"
cat > "$T/root/bbh.toml" <<EOF
[suite]
input_env = "FAKE_ROOT"
[inp]
corpus_dir = "tests/inp"
set = "fake"
build = "build/m1"
rompath_suffix = "/rompath"
profile = "cps2w"
mame_bin_default = "$T/stub"
max_frames = 6000
stop_after = 5
EOF
export FAKE_ROOT="$T/ref"
C="$BBH_HOME/bin/bbh inp-corpus --config $T/root/bbh.toml"

echo "== 1. an all-clean corpus =="
rec clean-m1-01 "a clean run"; canned clean-m1-01 5000
rec clean-m1-02 "another"; canned clean-m1-02 4000
$C > "$T/o" 2>&1 && ok "exit 0" || { fail "exit $? on a clean corpus"; cat "$T/o"; }
grep -q "^  ok: clean-m1-01 plays through clean (a clean run)$" "$T/o" && grep -q "^  ok: clean-m1-02 plays through clean (another)$" "$T/o" && ok "'ok: <name> plays through clean (<NOTE>)'" || fail "$(cat "$T/o")"
grep -q "^  ok liveness controls fired (3 dead rejected, 1 live accepted)$" "$T/o" && ok "the liveness controls run on every invocation" || fail "controls line"
grep -q "^PASS: 2 recording(s) replayed on build/m1, no exception (0 declared-open)$" "$T/o" && ok "the PASS line, the lineage's text" || fail "$(tail -1 "$T/o")"

echo "== 2. a crash, a declared defect, a rotted defect =="
rec crash-m1-01 "the field crash"; canned crash-m1-01 3000 "CRASH 650 vec4 PC 422bac SP 00ff7f00 ADDR - HANDLER 0000c8"
$C > "$T/o" 2>&1 && fail "a crash passed" || ok "a crashing recording: exit 1"
grep -q "^  FAIL: crash-m1-01 — CRASH 650 vec4 PC 422bac" "$T/o" && grep -q "^        the field crash$" "$T/o" && ok "'FAIL: <name> — <CRASH line>' then the NOTE" || fail "$(cat "$T/o")"
grep -q "^FAIL: inp corpus$" "$T/o" && ok "'FAIL: inp corpus'" || fail "final line: $(tail -1 "$T/o")"
printf 'vec4 PC 422bac' > "$T/root/tests/inp/crash-m1-01/DEFECT"
$C > "$T/o" 2>&1 && ok "a DEFECT-declared crash that matches: exit 0" || { fail "declared defect failed"; cat "$T/o"; }
grep -q "^  OPEN (as frozen): crash-m1-01 — CRASH 650 vec4 PC 422bac" "$T/o" && grep -q "no exception (1 declared-open)" "$T/o" && ok "'OPEN (as frozen)' and the PASS line counts it" || fail "$(cat "$T/o")"
printf 'vec3 PC 000000' > "$T/root/tests/inp/crash-m1-01/DEFECT"
$C > "$T/o" 2>&1 && fail "a rotted DEFECT passed" || { grep -q "declared DEFECT 'vec3 PC 000000' but got 'CRASH 650 vec4" "$T/o" && grep -q "the capture rotted or the defect moved" "$T/o" && ok "MUST-FIRE: a DEFECT that no longer matches FAILS — the capture rotted or the defect moved" || fail "$(cat "$T/o")"; }
canned crash-m1-01 3000; $C > "$T/o" 2>&1 && fail "a DEFECT with no crash passed" || { grep -q "but got 'none'" "$T/o" && ok "…and a declared DEFECT that no longer crashes at all FAILS ('got none')" || fail "$(cat "$T/o")"; }
rm "$T/root/tests/inp/crash-m1-01/DEFECT"

echo "== 3. a dead run, a broken recording, --only, an empty corpus, a missing build =="
canned crash-m1-01 0
$C > "$T/o" 2>&1 && fail "a zero-frame run passed" || { grep -q "^  FAIL: crash-m1-01 — dead run (no END line)$" "$T/o" && ok "MUST-FIRE: a zero-frame playback is a DEAD RUN, not a clean one" || fail "$(cat "$T/o")"; }
canned crash-m1-01 3000
rm "$T/root/tests/inp/crash-m1-01/crash-m1-01.inp"
$C > "$T/o" 2>&1 && fail "a recording without its .inp passed" || { grep -q "has no crash-m1-01.inp" "$T/o" && ok "a recording dir without <name>.inp FAILS" || fail "$(cat "$T/o")"; }
rm -r "$T/root/tests/inp/crash-m1-01"
$C --only clean-m1-02 > "$T/o" 2>&1 && grep -q "^PASS: 1 recording(s)" "$T/o" && ! grep -q "clean-m1-01" "$T/o" && ok "--only runs one recording" || fail "--only: $(cat "$T/o")"
ONLY=clean-m1-01 $C > "$T/o" 2>&1 && grep -q "^PASS: 1 recording(s)" "$T/o" && grep -q "clean-m1-01" "$T/o" && ok "ONLY in the environment too (the lineage's variable)" || fail "ONLY: $(cat "$T/o")"
$C --only nosuch > "$T/o" 2>&1 && fail "an empty selection passed" || { grep -q "^FAIL: no recordings under tests/inp/$" "$T/o" && ok "no recordings selected: 'FAIL: no recordings under <corpus>/'" || fail "$(cat "$T/o")"; }
$C --build build/nosuch > "$T/o" 2>&1 && fail "a missing build passed" || { grep -q "^FAIL: no fake build at build/nosuch$" "$T/o" && ok "a missing build: 'FAIL: no <set> build at <dir>'" || fail "$(cat "$T/o")"; }
BUILD=build/nosuch $C > "$T/o" 2>&1 && fail "BUILD env ignored" || { grep -q "no fake build at build/nosuch" "$T/o" && ok "BUILD in the environment names the build (the lineage's variable)" || fail "$(cat "$T/o")"; }
env -u FAKE_ROOT "$BBH_HOME/bin/bbh" inp-corpus --config "$T/root/bbh.toml" > "$T/o" 2>&1 && fail "ran without the input variable" || { grep -q "^FAIL: set FAKE_ROOT$" "$T/o" && ok "the reference-input variable is demanded" || fail "$(cat "$T/o")"; }

echo
[ "$rc" = 0 ] && echo "PASS: bbh inp-corpus, every verdict" || { echo "FAIL: see above"; exit 1; }
