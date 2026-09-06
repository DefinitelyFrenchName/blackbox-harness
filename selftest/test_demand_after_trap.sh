#!/bin/sh
# test_demand_after_trap.sh — ground truth for lib/py/bbh/demand_after_trap.py
# and the measurement behind it. ROM-free, ~1 s.
#
# MUST-FIRE CONTROL: a synthetic script with a demand after its trap is
# reported; the same script with the demand before the trap, and one inside
# a heredoc, are not; the lib subdir is scanned; --skip is honoured. And the
# shipped example's gates scan clean.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT INT TERM
mkdir -p "$W/a/lib" "$W/b/lib" "$W/c/lib"
printf '#!/bin/sh\nset -eu\nW=$(mktemp -d); trap '"'"'rm -rf "$W"'"'"' EXIT\n: "${FOO:?set FOO}"\n' > "$W/a/g.sh"
printf '#!/bin/sh\nset -eu\n: "${FOO:?set FOO}"\nW=$(mktemp -d); trap '"'"'rm -rf "$W"'"'"' EXIT\ncat <<EOS\nstub ${BAR:?} in a heredoc is fine\nEOS\n' > "$W/b/g.sh"
cp "$W/b/g.sh" "$W/c/g.sh"; cp "$W/a/g.sh" "$W/c/lib/l.sh"

echo "== 1. the controls =="
if python3 -m bbh.demand_after_trap "$W/a" >/dev/null; then fail "control: a demand AFTER the trap was not reported"; else ok "control fires: a demand after the trap is reported"; fi
if python3 -m bbh.demand_after_trap "$W/b" >/dev/null; then ok "a demand BEFORE the trap, and one inside a heredoc, are allowed"; else fail "the allowed shapes were reported"; fi
out="$(python3 -m bbh.demand_after_trap "$W/c" || true)"
printf '%s' "$out" | grep -q "^lib/l.sh:4:" && ok "the lib subdir is scanned (lib/l.sh:4 reported)" || fail "lib subdir not scanned: '$out'"
if python3 -m bbh.demand_after_trap "$W/c" --skip l.sh >/dev/null; then ok "--skip exempts a named file" || true; else fail "--skip ignored"; fi

echo "== 2. the measurement the rule rests on (this host's sh) =="
printf '#!/bin/sh\nset -eu\nW=$(mktemp -d); trap '"'"'rm -rf "$W"'"'"' EXIT\n: "${NOPE_UNSET_VAR:?set it}"\necho unreachable\n' > "$W/m.sh"
sh "$W/m.sh" >/dev/null 2>&1 && st=0 || st=$?
if [ "$st" = 0 ]; then ok "this sh EXITS 0 for a demand after an armed trap (the macOS bash 3.2 behaviour the rule exists for)"
else ok "this sh exits $st for a demand after a trap (correct here; the rule still holds on macOS bash 3.2)"; fi

echo "== 3. the shipped example scans clean =="
if python3 -m bbh.demand_after_trap "$BBH_HOME/example/tests" >/dev/null; then ok "example/tests: no demand after a trap"; else fail "example/tests carries a demand after a trap"; fi

echo
[ "$rc" = 0 ] && echo "PASS" || { echo "FAIL"; exit 1; }
