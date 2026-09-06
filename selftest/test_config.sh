#!/bin/sh
# test_config.sh — ground truth for the TOML-subset reader and `bbh config`:
# every accepted shape, every REFUSED shape (each a must-fire control), the
# CLI's list/table/default/missing semantics, [project].root, and — on a
# host that has tomllib — agreement with it on every accepted example.
# ROM-free, ~1 s.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT INT TERM

cat > "$W/ok.toml" <<'EOF'
# a comment
[project]
root = "."                # trailing comment
name = 'literal # not a comment'
[tier]
patterns = ['a\.sh', "b", 'c']
multi = [
  'one',   # per-line comment
  "two",
]
nested = [ ['x', 'y'], ['z'] ]
depth = 2
hex = 0x7f
flag = true
[sweep]
tbl = { env = 'X', default = 'build/y', n = 3 }
empty = []
EOF

echo "== 1. accepted shapes parse to the expected values =="
py() { python3 -m bbh.config "$W/ok.toml" get "$1" ${2+--default "$2"}; }
[ "$(py project.name)" = 'literal # not a comment' ] && ok "literal string keeps '#'" || fail "literal: $(py project.name)"
[ "$(py tier.patterns | tr '\n' ' ')" = 'a\.sh b c ' ] && ok "array -> one item per line, backslash intact" || fail "patterns: $(py tier.patterns | tr '\n' ' ')"
[ "$(py tier.multi | tr '\n' ' ')" = 'one two ' ] && ok "multi-line array with trailing comma and comments" || fail "multi: $(py tier.multi | tr '\n' ' ')"
[ "$(py tier.nested | head -1)" = "$(printf 'x\ty')" ] && ok "nested array -> tab-joined fields" || fail "nested: $(py tier.nested | head -1)"
[ "$(py tier.depth)" = 2 ] && [ "$(py tier.hex)" = 127 ] && [ "$(py tier.flag)" = true ] && ok "int, hex, bool" || fail "scalars: $(py tier.depth) $(py tier.hex) $(py tier.flag)"
[ "$(py sweep.tbl | tr '\n' ' ')" = 'env=X default=build/y n=3 ' ] && ok "inline table -> key=value lines" || fail "tbl: $(py sweep.tbl | tr '\n' ' ')"
[ -z "$(py sweep.empty)" ] && ok "empty array -> nothing" || fail "empty array printed something"

echo "== 2. defaults and missing keys =="
[ "$(py project.gates_dir)" = tests ] && ok "an absent key falls back to DEFAULTS (project.gates_dir = tests)" || fail "default: $(py project.gates_dir)"
[ "$(py nosuch.key mine)" = mine ] && ok "--default supplies a value for an unknown key" || fail "--default ignored"
if python3 -m bbh.config "$W/ok.toml" get nosuch.key >/dev/null 2>&1; then fail "a missing key with no default did not fail"; else
    st=$?; [ "$st" = 3 ] && ok "a missing key with no default exits 3 (a runner never runs on an empty value silently)" || fail "missing key exit $st, expected 3"; fi

echo "== 3. MUST-FIRE: every refused shape is refused =="
refuse() {  # refuse <label> <toml-text>
    printf '%s\n' "$2" > "$W/bad.toml"
    if python3 -m bbh.config "$W/bad.toml" dump >/dev/null 2>&1; then fail "ACCEPTED: $1"; else ok "refused: $1"; fi
}
refuse "dotted key"              'a.b = 1'
refuse "dotted table header"     '[a.b]'
refuse "array of tables"         '[[x]]'
refuse "duplicate key"           'a = 1
a = 2'
refuse "signed hex"              'a = -0x10'
refuse "escape in basic string"  'a = "x\ty"'
refuse "nested inline table"     'a = { b = { c = 1 } }'
refuse "array of inline tables"  'a = [ { b = 1 } ]'
refuse "float"                   'a = 1.5'
refuse "unterminated array"      'a = [1, 2'
refuse "trailing garbage"        'a = 1 2'
refuse "table declared twice"    '[x]
a = 1
[x]
b = 2'
refuse "triple-nested array"     'a = [[[1]]]'

echo "== 4. [project].root moves the consumer root =="
mkdir -p "$W/elsewhere/cfg" "$W/elsewhere/tree/tests"
printf '[project]\nroot = "../tree"\n' > "$W/elsewhere/cfg/bbh.toml"
r="$(python3 -m bbh.config "$W/elsewhere/cfg/bbh.toml" root)"
[ "$r" = "$W/elsewhere/tree" ] && ok "root resolves relative to the config file" || fail "root: $r"

echo "== 5. agreement with tomllib on every accepted example =="
if python3 -c 'import tomllib' 2>/dev/null; then
    python3 - "$W/ok.toml" <<'EOF'
import sys, tomllib
from bbh import toml_subset
text = open(sys.argv[1]).read()
a = tomllib.loads(text); b = toml_subset.loads(text)
sys.exit(0 if a == b else 1)
EOF
    [ $? = 0 ] && ok "tomllib and the subset parser agree on ok.toml" || fail "tomllib and the subset parser DISAGREE on ok.toml"
else
    # not the SKIP marker: sections 1-4 ran and passed; only this section is
    # missing its instrument. A whole-gate SKIP would hide four verdicts.
    echo "  not run: no tomllib on this host (python < 3.11) — the agreement section needs one"
fi

echo
[ "$rc" = 0 ] && echo "PASS" || { echo "FAIL"; exit 1; }
