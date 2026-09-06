#!/bin/sh
# test_provenance.sh — ground truth for lib/py/bbh/provenance.py: the
# register is complete both ways and every row names a defined evidence
# class. ROM-free, ~1 s.
#
# The lineage's two controls (VampireSaved test_expectation_provenance.sh:
# a deleted row is caught as an unprovenanced file; a row naming a missing
# file is caught) plus: a class outside the vocabulary; a second scope dir
# with its row prefix; dotfiles, subdirectories and the excluded files are
# not expectations; a missing page; --page overrides; and the shipped
# example is green.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
R="$T/r"; mkdir -p "$R/expected/a-set" "$R/expect"
cat > "$R/bbh.toml" <<'EOF'
[provenance]
page = "expected/PROVENANCE.md"
scope = [["expected", ""], ["expect", "expect/"]]
exclude = ["PROVENANCE.md", "README.md"]
evidence_classes = ["measured", "static"]
rests_on_column = 4
EOF
: > "$R/expected/a.txt"; : > "$R/expected/b.txt"; : > "$R/expected/README.md"; : > "$R/expected/.hidden"; : > "$R/expected/a-set/x.sha1"; : > "$R/expect/c.txt"
page() {  # page <rows...>
    { echo "# P"; echo; echo "| file | owner | subject | rests on | re-freeze | since |"; echo "|---|---|---|---|---|---|"
      for r in "$@"; do echo "$r"; done; } > "$R/expected/PROVENANCE.md"
}
PV="python3 -m bbh.provenance --config $R/bbh.toml"
page '| `a.txt` | g | s | measured | f | 1 |' '| `b.txt` | g | s | static (the tree) | f | 1 |' '| `expect/c.txt` | g | s | measured | f | 1 |'

echo "== 1. the clean case =="
o="$($PV)" && ok "exit 0" || fail "exit non-zero on a complete page"
printf '%s\n' "$o" | grep -q '^  ok: 3 expectation files, 3 rows, complete both ways$' && ok "three files across two scope dirs, README/dotfile/subdir ignored, the lineage's ok line" || fail "$(printf '%s\n' "$o" | sed -n 2p)"
printf '%s\n' "$o" | grep -q "^  ok: every row's evidence class is one the page defines$" && ok "a class matched as a substring of the cell" || fail "class line"
printf '%s\n' "$o" | sed -n 1p | grep -q '^== 1\. every expectation file has a row, every row an existing file$' && ok "the section headers are the lineage gate's" || fail "header"

echo "== 2. MUST-FIRE controls =="
page '| `a.txt` | g | s | measured | f | 1 |' '| `expect/c.txt` | g | s | measured | f | 1 |'
o="$($PV 2>&1)" && fail "A: a deleted row was NOT caught" \
    || { printf '%s\n' "$o" | grep -q '^  FAIL: 1 expectation file(s) with NO provenance row:$' && printf '%s\n' "$o" | grep -q '^      b.txt$' && printf '%s\n' "$o" | grep -q '^      Add a row to expected/PROVENANCE.md saying what the$' \
         && ok "A: a deleted row is caught as an unprovenanced file, and the advice names the configured page" || fail "A: $(printf '%s\n' "$o" | head -3)"; }
page '| `a.txt` | g | s | measured | f | 1 |' '| `b.txt` | g | s | static | f | 1 |' '| `expect/c.txt` | g | s | measured | f | 1 |' '| `no_such.txt` | g | s | measured | f | 1 |'
o="$($PV 2>&1)" && fail "B: a dead row was NOT caught" \
    || { printf '%s\n' "$o" | grep -q '^  FAIL: 1 provenance row(s) naming a file that is gone:$' && printf '%s\n' "$o" | grep -q '^      no_such.txt$' && ok "B: a row naming a missing file is caught" || fail "B: $(printf '%s\n' "$o" | head -3)"; }
page '| `a.txt` | g | s | measured | f | 1 |' '| `b.txt` | g | s | a guess | f | 1 |' '| `expect/c.txt` | g | s | measured | f | 1 |'
o="$($PV 2>&1)" && fail "C: an undefined class passed" \
    || { printf '%s\n' "$o" | grep -q "^  FAIL: 1 row(s) whose 'rests on' names no defined class:$" && printf '%s\n' "$o" | grep -q "^      b.txt: 'a guess'$" && printf '%s\n' "$o" | grep -q '^      Defined classes: measured, static$' \
         && ok "C: a class outside the vocabulary is refused, the vocabulary printed" || fail "C: $(printf '%s\n' "$o" | tail -3)"; }
page '| `a.txt` | g | s | measured | f | 1 |' '| `b.txt` | g | s | static | f | 1 |'
o="$($PV 2>&1)" && fail "D: a file in the second scope dir without a row passed" \
    || { printf '%s\n' "$o" | grep -q '^      expect/c.txt$' && ok "D: the second scope dir's file is named with its row prefix" || fail "D: $o"; }
rm "$R/expected/PROVENANCE.md"
o="$($PV 2>&1)" && fail "E: a missing page passed" || { [ "$o" = "FAIL: expected/PROVENANCE.md is missing" ] && ok "E: a missing page is the lineage's one-line FAIL" || fail "E: $o"; }
page '| `a.txt` | g | s | measured | f | 1 |' '| `b.txt` | g | s | static | f | 1 |' '| `expect/c.txt` | g | s | measured | f | 1 |'
cp "$R/expected/PROVENANCE.md" "$T/alt.md"; sed -i.bak '/b.txt/d' "$T/alt.md"
$PV --page "$T/alt.md" >/dev/null 2>&1 && fail "F: --page did not override" || ok "F: --page names another register (the controls' shape)"

echo "== 3. the shipped example =="
"$BBH_HOME/bin/bbh" provenance --config "$BBH_HOME/example/bbh.toml" >/dev/null && ok "example/expected/PROVENANCE.md is complete" || fail "the example's page"

echo
[ "$rc" = 0 ] && echo "PASS: every frozen expectation says where its numbers came from" || { echo "FAIL: see above"; exit 1; }
