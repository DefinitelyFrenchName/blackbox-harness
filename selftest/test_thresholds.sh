#!/bin/sh
# test_thresholds.sh — the comparison thresholds are declared ONCE and every
# consumer resolves to that one declaration; a consumer config overrides
# them and the override reaches EVERY tool (the proposer and the enforcers
# cannot disagree). ROM-free, ~1 s. Lineage: VampireSaved's
# tests/test_s4_thresholds.sh (GitHub #44 there: four declarations, a
# comment saying "must stay in step", nothing asserting it).
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
cd "$BBH_HOME"
fail=0
CONSUMERS="lib/py/bbh/describe_masked_shape.py lib/py/bbh/compare_composite.py lib/py/bbh/compare_flicker.py lib/py/bbh/compare_window.py"

echo "== 1: one declaration, and its defaults are the lineage's ratified pair =="
python3 - <<'PY' || fail=1
import sys
from bbh.thresholds import FLICKER_MAX, RECONVERGE, MAX_TOTAL
rc = 0
for name, val, want in (("FLICKER_MAX", FLICKER_MAX, 2), ("RECONVERGE", RECONVERGE, 60), ("MAX_TOTAL", MAX_TOTAL, 8)):
    if val == want: print(f"  ok {name} == {want}")
    else: print(f"  FAIL {name} == {val}, expected {want}"); rc = 1
sys.exit(rc)
PY

echo "== 2: every consumer resolves to that declaration =="
for f in $CONSUMERS; do
    if grep -Eq '^[[:space:]]*from \.thresholds import' "$f"; then echo "  ok $f imports the shared declaration"
    else echo "  FAIL $f does not import bbh.thresholds"; fail=1; fi
done

echo "== 3: NO consumer re-declares a threshold locally =="
for f in $CONSUMERS; do
    if grep -Eq '^[[:space:]]*(FLICKER_MAX|RECONVERGE|MAX_TOTAL)[[:space:]]*=' "$f"; then
        echo "  FAIL $f re-declares a threshold locally:"; grep -En '^[[:space:]]*(FLICKER_MAX|RECONVERGE|MAX_TOTAL)[[:space:]]*=' "$f" | sed 's/^/        /'; fail=1
    else echo "  ok $f declares none locally"; fi
done

echo "== 4: no consumer hard-codes the VALUES as argparse defaults =="
for f in $CONSUMERS; do
    hits="$(grep -En 'add_argument\("--(reconverge|max-stretch|min-converge|max-total)".*default=[0-9]' "$f" || true)"
    if [ -n "$hits" ]; then echo "  FAIL $f hard-codes a threshold default:"; printf '%s\n' "$hits" | sed 's/^/        /'; fail=1
    else echo "  ok $f takes its defaults from the shared declaration"; fi
done

echo "== 5: verdict control — a re-introduced literal IS caught, a comment is NOT =="
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
printf 'FLICKER_MAX = 3\n' > "$W/drifted.py"
grep -Eq '^[[:space:]]*(FLICKER_MAX|RECONVERGE|MAX_TOTAL)[[:space:]]*=' "$W/drifted.py" && echo "  ok control: a local literal is caught" || { echo "  FAIL control: a local literal is not seen"; fail=1; }
printf '# FLICKER_MAX is 2 (see thresholds)\n' > "$W/comment.py"
grep -Eq '^[[:space:]]*(FLICKER_MAX|RECONVERGE|MAX_TOTAL)[[:space:]]*=' "$W/comment.py" && { echo "  FAIL control: a comment is flagged"; fail=1; } || echo "  ok control: a comment is not flagged"

echo "== 6: MUST-FIRE — a consumer override reaches the proposer AND the enforcer alike =="
mkdir -p "$W/c"; printf '[thresholds]\nflicker_max = 3\nreconverge = 10\n' > "$W/c/bbh.toml"
python3 - "$W" <<'PY'
import sys
w = sys.argv[1]
N = 200
def write(p, d):
    open(f"{w}/{p}", "w").write("\n".join(f"{i} {'ffffffffffffffff' if i in d else '%016x' % i}" for i in range(1, N + 1)) + f"\nEND {N}\n")
write("base.log", set()); write("three.log", {100, 101, 102})
PY
prop="$(BBH_CONFIG="$W/c/bbh.toml" python3 -m bbh.describe_masked_shape "$W/base.log" "$W/three.log" --basis b | grep '^proposed:')"
enf="$(BBH_CONFIG="$W/c/bbh.toml" python3 -m bbh.compare_flicker "$W/base.log" "$W/three.log" || true)"
[ "$prop" = "proposed: flicker b 3 100,101,102" ] && echo "  ok the proposer under flicker_max=3 proposes a flicker" || { echo "  FAIL proposer: '$prop'"; fail=1; }
[ "$enf" = "FLICKER 3 100,101,102" ] && echo "  ok the enforcer under the same config accepts the proposal verbatim" || { echo "  FAIL enforcer: '$enf'"; fail=1; }
def="$(python3 -m bbh.describe_masked_shape "$W/base.log" "$W/three.log" --basis b | grep '^proposed:')"
case "$def" in "proposed: window b 100 102") echo "  ok without the config the same shape is a WINDOW (the default is the lineage's 2)";; *) echo "  FAIL default proposer: '$def'"; fail=1;; esac

echo "== 7: the consumers compile =="
for f in $CONSUMERS lib/py/bbh/check_diverge.py lib/py/bbh/logfmt.py; do
    python3 -m py_compile "$f" 2>/dev/null && echo "  ok $f" || { echo "  FAIL $f does not compile"; fail=1; }
done

echo
[ "$fail" = 0 ] && echo "PASS: the thresholds are declared once and cannot drift." || { echo "FAIL"; exit 1; }
