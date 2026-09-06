#!/bin/sh
# test_tier.sh — ground truth for lib/py/bbh/tier.py, the transitive
# "needs an instrument" classifier. ROM-free, ~1 s.
#
# The cases that matter, each paid for in the lineage: a gate that reaches
# the instrument ONLY through a sourced lib (two gates were reported static
# and one ran 208 s inside a chain advertised as emulator-free); a mention
# in a COMMENT is not a reach; the source chain is followed to the configured
# depth and no further (a control); runner prefixes and manual suffixes are
# excluded from the unregistered report.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
mkdir -p "$T/p/tests/lib"
cat > "$T/p/bbh.toml" <<'EOF'
[tier]
patterns = ['run_instrument\.sh', 'INSTR_BIN']
source_regex = '^\s*\.\s+"?\$(?:REPO|\{REPO\})"?/(tests/lib/[a-z0-9_]+\.sh)'
source_depth = 2
[registries]
portable = "tests/ci_portable.txt"
static = "tests/ci_static.txt"
EOF
g() { printf '#!/bin/sh\n%s\n' "$2" > "$T/p/tests/$1.sh"; chmod +x "$T/p/tests/$1.sh"; }
g direct   'INSTR_BIN=x tools/run_instrument.sh set'
g comment  '# this gate never calls run_instrument.sh, it only mentions it
echo PASS'
g via_lib  '. "$REPO/tests/lib/l1.sh"'
g via_two  '. "$REPO/tests/lib/l2a.sh"'
g via_three '. "$REPO/tests/lib/l3a.sh"'
g plain    'echo PASS'
g run_all  'echo I am a runner'
g long_soak 'echo I am manual'
printf '. "$REPO/tests/lib/deep.sh"\n' > "$T/p/tests/lib/l1.sh"; printf 'INSTR_BIN=x\n' > "$T/p/tests/lib/deep.sh"
printf '. "$REPO/tests/lib/l2b.sh"\n' > "$T/p/tests/lib/l2a.sh"; printf 'INSTR_BIN=x\n' > "$T/p/tests/lib/l2b.sh"
printf '. "$REPO/tests/lib/l3b.sh"\n' > "$T/p/tests/lib/l3a.sh"; printf '. "$REPO/tests/lib/l3c.sh"\n' > "$T/p/tests/lib/l3b.sh"; printf 'INSTR_BIN=x\n' > "$T/p/tests/lib/l3c.sh"
printf 'plain\n' > "$T/p/tests/ci_portable.txt"; : > "$T/p/tests/ci_static.txt"

echo "== 1. --list classifies each gate =="
lst="$(python3 -m bbh.tier "$T/p/bbh.toml" --list)"
want() { printf '%s\n' "$lst" | grep -q "^$1	$2	$3\$" && ok "$1 -> $2 ($3)" || fail "$1: $(printf '%s\n' "$lst" | grep "^$1	" || echo missing) expected $2 $3"; }
want direct    INSTRUMENT -
want comment   PLAIN -
want via_lib   INSTRUMENT -
want via_two   INSTRUMENT -
want via_three PLAIN -
want plain     PLAIN portable
want run_all   PLAIN -

echo "== 2. --unregistered names the right gates =="
un="$(python3 -m bbh.tier "$T/p/bbh.toml" --unregistered)"
printf '%s\n' "$un" | grep -q "      comment" && ok "the comment-only gate is unregistered (it is instrument-free)" || fail "comment-only gate not reported"
printf '%s\n' "$un" | grep -q "      via_three" && ok "the depth-3 chain is reported (the control: depth 2 does not reach it)" || fail "depth-3 chain not reported"
printf '%s\n' "$un" | grep -q "      via_lib\|      via_two\|      direct" && fail "an instrument gate was reported" || ok "no instrument gate is reported"
printf '%s\n' "$un" | grep -q "      run_all\|      long_soak" && fail "a runner or manual gate was reported" || ok "runner prefix and manual suffix are excluded"
printf '%s\n' "$un" | grep -q "      plain" && fail "a registered gate was reported" || ok "a registered gate is not reported"
printf '%s\n' "$un" | grep -q "^  2 emulator-free gate(s) in NEITHER registry:" && ok "the report's count line is the lineage's text" || fail "report text: $(printf '%s\n' "$un" | head -1)"

echo "== 3. MUST-FIRE: depth 3 reaches the third lib =="
sed 's/source_depth = 2/source_depth = 3/' "$T/p/bbh.toml" > "$T/p/bbh3.toml"
python3 -m bbh.tier "$T/p/bbh3.toml" --list | grep -q "^via_three	INSTRUMENT" && ok "source_depth = 3 classifies via_three INSTRUMENT" || fail "depth config not applied"

echo "== 4. the clean case =="
printf 'plain\ncomment\nvia_three\n' > "$T/p/tests/ci_portable.txt"
python3 -m bbh.tier "$T/p/bbh.toml" --unregistered | grep -q "ok: every emulator-free gate is registered" && ok "all registered -> the ok line" || fail "clean case not reported ok"

echo
[ "$rc" = 0 ] && echo "PASS: the tier classifier sees what the runners need it to see" || { echo "FAIL: see above"; exit 1; }
