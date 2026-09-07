#!/bin/sh
# test_rpl.sh — ground truth for lib/py/bbh/rpl.py, the .rpl grammar: every
# example replay parses; each malformed shape is rejected with the lineage's
# reason and the line number; a consumer vocabulary via --sides; and, when
# the lineage tree is beside this one, EVERY replay it carries parses
# (top level and subdirectories). ~2 s. Slice H6 adds the Lua twin and the
# equality selftest.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
R="python3 -m bbh.rpl"

echo "== 1. the example's replays =="
for f in "$BBH_HOME"/example/replays/*.rpl; do
    o=$($R "$f") && ok "$(basename "$f"): $o" || fail "$(basename "$f"): $o"
done
o=$($R "$BBH_HOME/example/replays/03_press.rpl"); [ "$o" = "ok: 3 lines, last frame 300, 2 held frames" ] && ok "counts: 3 non-comment lines, last frame 300, 2 held frames" || fail "counts: $o"

echo "== 2. malformed shapes, each with the lineage's reason and the line =="
bad() {  # bad <line-content> <expected-substring>
    printf '# a comment\n\n%s\n' "$1" > "$T/b.rpl"
    o=$($R "$T/b.rpl") && fail "accepted: '$1'" || { printf '%s' "$o" | grep -q "b.rpl:3: $2" && ok "'$1' -> $2" || fail "'$1' -> '$o'"; }
}
bad "abc p1=1"      "bad frame range 'abc'"
bad "10-5 p1=1"     "bad range"
bad "0 wait"        "bad range"
bad "100 p3=1"      "unknown side 'p3'"
bad "100 p1=Z"      "unknown token 'Z' for p1"
bad "100 sys=S"     "unknown token 'S' for sys"
bad "100 sys=S1C"   "unknown token 'C' for sys"
bad "100"           "expected '<frame>\[-<end>\] who=tokens'"
bad "100 p1"        "unknown side 'nil'"

echo "== 3. semantics =="
printf '10-12 p1=U1 p2=D\n11 sys=S1C1\n20 wait\n' > "$T/s.rpl"
python3 - "$T/s.rpl" <<'EOF' && ok "ranges expand, tokens split by width, lines OR together, wait extends" || { fail "semantics"; }
import sys; sys.path.insert(0, __import__("os").environ["PYTHONPATH"])
from bbh import rpl
held, last = rpl.parse(sys.argv[1])
assert last == 20, last
assert sorted(held[10]) == [("p1", "1"), ("p1", "U"), ("p2", "D")], held[10]
assert sorted(held[11]) == [("p1", "1"), ("p1", "U"), ("p2", "D"), ("sys", "C1"), ("sys", "S1")], held[11]
assert 20 not in held
EOF
printf '5 j1=AB\n' > "$T/c.rpl"
o=$($R "$T/c.rpl" --sides j1:2:ABCD) && [ "$o" = "ok: 1 lines, last frame 5, 1 held frames" ] && ok "--sides: a consumer vocabulary (side j1, width 2, tokens AB/CD)" || fail "--sides: $o"
$R "$T/c.rpl" >/dev/null 2>&1 && fail "the default vocabulary accepted side j1" || ok "…which the default vocabulary rejects"

echo "== 4. the lineage's replays, when present =="
CFG="$BBH_HOME/example/consumers/bbh.vampire.toml"
V="$(python3 -m bbh.config "$CFG" root 2>/dev/null || true)"
if [ -n "$V" ] && [ -d "$V/tests/replays" ]; then
    n=0; badn=0
    for f in "$V"/tests/replays/*.rpl "$V"/tests/replays/*/*.rpl; do
        [ -f "$f" ] || continue
        n=$((n + 1)); $R "$f" > /dev/null 2>&1 || { badn=$((badn + 1)); echo "        rejected: $f"; }
    done
    [ "$badn" = 0 ] && ok "every lineage replay parses ($n files, top level and subdirectories)" || fail "$badn of $n lineage replays rejected"
else
    echo "  (the lineage tree is not beside this one — its replays not parsed)"
fi

echo
[ "$rc" = 0 ] && echo "PASS: the .rpl grammar" || { echo "FAIL: see above"; exit 1; }
