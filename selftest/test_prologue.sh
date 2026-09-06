#!/bin/sh
# test_prologue.sh — ground truth for lib/sh/prologue.sh, the gate-author
# helpers: bbh_demand exits 1 AFTER a trap (the whole point), bbh_skip and
# bbh_fail print the contract's markers, bbh_work cleans up, bbh_absolutise
# resolves. ROM-free, ~1 s.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT INT TERM
P="$BBH_HOME/lib/sh/prologue.sh"

echo "== 1. bbh_demand after a trap exits 1 with a FAIL line =="
printf '#!/bin/sh\nset -eu\n. "%s"\nbbh_work\nbbh_demand NOPE_UNSET "set NOPE_UNSET"\necho unreachable\n' "$P" > "$W/d.sh"
out="$(sh "$W/d.sh" 2>&1)" && st=0 || st=$?
[ "$st" = 1 ] && [ "$out" = "FAIL: set NOPE_UNSET" ] && ok "exit 1, 'FAIL: set NOPE_UNSET'" || fail "bbh_demand: exit $st, out '$out'"
out="$(NOPE_UNSET=1 sh "$W/d.sh" 2>&1)" && st=0 || st=$?
[ "$st" = 0 ] && [ "$out" = unreachable ] && ok "…and passes through when the variable is set" || fail "bbh_demand with the var set: exit $st '$out'"

echo "== 2. bbh_skip / bbh_fail =="
printf '#!/bin/sh\nset -eu\n. "%s"\nbbh_skip no input at all\n' "$P" > "$W/s.sh"
out="$(sh "$W/s.sh")" && st=0 || st=$?
[ "$st" = 0 ] && [ "$out" = "SKIP: no input at all" ] && ok "bbh_skip: 'SKIP: …' + exit 0 (the runner's skip shape)" || fail "bbh_skip: $st '$out'"
printf '#!/bin/sh\nset -eu\n. "%s"\nbbh_fail it broke\n' "$P" > "$W/f.sh"
out="$(sh "$W/f.sh")" && st=0 || st=$?
[ "$st" = 1 ] && [ "$out" = "FAIL: it broke" ] && ok "bbh_fail: 'FAIL: …' + exit 1" || fail "bbh_fail: $st '$out'"

echo "== 3. bbh_work creates and removes W =="
printf '#!/bin/sh\nset -eu\n. "%s"\nbbh_work\necho "$W"\n[ -d "$W" ] || exit 9\n' "$P" > "$W/w.sh"
d="$(sh "$W/w.sh")"; [ -n "$d" ] && [ ! -d "$d" ] && ok "W existed during the gate and is gone after" || fail "bbh_work: '$d' still exists or was empty"

echo "== 4. bbh_absolutise =="
mkdir -p "$W/rel/sub"
printf '#!/bin/sh\nset -eu\n. "%s"\ncd "%s"\nX=rel/sub\nbbh_absolutise X\necho "$X"\n' "$P" "$W" > "$W/a.sh"
out="$(sh "$W/a.sh")"; [ "$out" = "$W/rel/sub" ] && ok "a relative path becomes absolute" || fail "absolutise: '$out'"
printf '#!/bin/sh\nset -eu\n. "%s"\nX=/no/such/dir\nbbh_absolutise X\n' "$P" > "$W/b.sh"
sh "$W/b.sh" >/dev/null 2>&1 && fail "an unresolvable path was accepted" || ok "an unresolvable path exits non-zero"

echo
[ "$rc" = 0 ] && echo "PASS" || { echo "FAIL"; exit 1; }
