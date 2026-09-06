#!/bin/sh
# test_header_defaults.sh — ground truth for lib/py/bbh/header_defaults.py: a
# gate's HEADER states the default its CODE uses. ROM-free, ~1 s.
#
# The lineage's controls (VampireSaved test_header_defaults.sh, each paid
# for on its first sweep): a Usage line naming a non-default dir is CAUGHT;
# the same line agreeing with the code is not; a stale dir in ordinary prose
# is a citation, not an instruction; a dir inside a `(verbatim; …)` archive
# block is exempt; a backticked token is code being discussed; a template
# `<stamp>` is not a dir; --fix repairs the mechanical one and leaves the
# rest alone. Then the config MUST-FIRE: under a token regex for another
# path shape the build/ line is invisible and a roms/ line is caught.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
mkdir -p "$T/tests"
g() { printf '#!/bin/sh\n# %s.sh — a stub.\n%s\n%s\n' "$1" "$2" "$3" > "$T/tests/$1.sh"; }
g g_a '# Usage: ROMDIR=... [BUILD=build/old_dir] tests/g_a.sh'                         'BUILD="${BUILD:-build/new_dir}"'
g g_b '# Usage: ROMDIR=... [BUILD=build/new_dir] tests/g_b.sh'                         'BUILD="${BUILD:-build/new_dir}"'
g g_c '# MEASURED 14z-1 on build/old_dir: the beam draws.'                              'BUILD="${BUILD:-build/new_dir}"'
g g_d '# HANDOFF note, moved into this header (verbatim; the doc pass ruled it):
#   Defaults build/old_dir'                                                             'BUILD="${BUILD:-build/new_dir}"'
g g_e '# Every `${1:-build/old_dir}` default is a pointer with a shelf life.'          'BUILD="${BUILD:-build/new_dir}"'
g g_f '# Usage: tests/g_f.sh   (the log dir defaults to build/emu_sweep_<stamp>)'       'LOG="${LOG:-$REPO/build/emu_sweep_1}"'
g g_g '# Usage: tests/g_g.sh [BUILD=build/two_a]  defaults build/two_b'                'A="${A:-build/two_a}"; B="${1:-$REPO/build/two_b}"'
HD="python3 -m bbh.header_defaults --root $T"
out="$($HD 2>&1 || true)"

echo "== 1. the lineage's controls =="
check() {  # check <gate> <caught|clean> <why>
    if printf '%s\n' "$out" | grep -q "tests/$1.sh"; then got=caught; else got=clean; fi
    [ "$got" = "$2" ] && ok "$1 $2 — $3" || fail "$1 came out $got, expected $2 — $3"
}
check g_a caught "a Usage line naming a non-default dir"
check g_b clean  "the same line, agreeing with the code"
check g_c clean  "a stale dir cited in prose is a measurement, not an instruction"
check g_d clean  "a stale dir inside a (verbatim) archive block"
check g_e clean  "a stale dir inside backticks, i.e. code being discussed"
check g_f clean  "a <template> token is not a dir"
check g_g clean  "two code defaults, both named by the header (the \$REPO/ prefix stripped)"
printf '%s\n' "$out" | grep -q '^1 header line(s) name a build dir the code does not default to:$' && ok "the report's count line is the lineage's" || fail "report: $(printf '%s\n' "$out" | head -1)"
printf '%s\n' "$out" | grep -q '^  tests/g_a.sh   code defaults: build/new_dir$' && ok "the report names the code's defaults beside the gate" || fail "report body"

echo "== 2. --fix =="
$HD --fix >/dev/null 2>&1 || true
grep -q 'BUILD=build/new_dir' "$T/tests/g_a.sh" && ok "--fix rewrote the Usage line to the code's own default" || fail "--fix did not repair g_a"
grep -q 'build/old_dir' "$T/tests/g_c.sh" && grep -q 'build/old_dir' "$T/tests/g_d.sh" && grep -q 'build/old_dir' "$T/tests/g_e.sh" \
    && ok "--fix left the prose citation, the verbatim block and the backticked token untouched" || fail "--fix rewrote a line it must not touch"
$HD | grep -q '^ok    every header Usage/default line names a current code default$' && ok "after --fix the tree is clean, with the lineage's ok line" || fail "not clean after --fix"
g g_h '# Usage: tests/g_h.sh [X=build/old]' 'A="${A:-build/one}"; B="${B:-build/two}"'
$HD --fix 2>&1 | grep -q '^rewrote 0 header line(s); 1 left for a human (the gate has more than one code default)$' \
    && ok "--fix refuses to guess between two code defaults and says so" || fail "--fix guessed, or the count line differs"
rm -f "$T/tests/g_h.sh"

echo "== 3. MUST-FIRE on the config =="
mkdir -p "$T/r2/tests"
printf '[project]\nroot = "."\n[header_defaults]\ntoken_regex = %s\n' "'roms/[a-z-]+'" > "$T/r2/bbh.toml"
cp "$T/tests/g_a.sh" "$T/r2/tests/g_a.sh"; sed -i.bak 's/build\/new_dir/build\/old_dir/' "$T/r2/tests/g_a.sh"; sed -i.bak 's/old_dir}/other}/' "$T/r2/tests/g_a.sh"; rm -f "$T/r2/tests/g_a.sh.bak"
printf '#!/bin/sh\n# g_r.sh — a stub.\n# Usage: tests/g_r.sh [roms/old]\nIMG="${1:-roms/new}"\n' > "$T/r2/tests/g_r.sh"
o2="$(python3 -m bbh.header_defaults --config "$T/r2/bbh.toml" 2>&1 || true)"
printf '%s\n' "$o2" | grep -q "tests/g_r.sh" && ok "under token_regex roms/… a roms/ Usage line is caught" || fail "roms/ line not caught"
printf '%s\n' "$o2" | grep -q "tests/g_a.sh" && fail "under token_regex roms/… the build/ line was still caught" || ok "…and the build/ line is invisible: the token shape is the consumer's"

echo "== 4. the shipped example =="
"$BBH_HOME/bin/bbh" header-defaults --config "$BBH_HOME/example/bbh.toml" | grep -q '^ok ' && ok "example/: every header names its code default" || fail "the example is not clean"

echo
[ "$rc" = 0 ] && echo "PASS: a header states the default its code uses" || { echo "FAIL: see above"; exit 1; }
