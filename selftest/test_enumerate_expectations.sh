#!/bin/sh
# test_enumerate_expectations.sh — ground truth for
# lib/sh/enumerate_expectations.sh: every kind is named, a `.pending` and an
# unknown kind make it non-zero, a file whose stem is not a replay is ignored,
# and the replays dir comes from the argument or BBH_REPLAYS_DIR. ~1 s.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
. "$BBH_HOME/lib/sh/enumerate_expectations.sh"
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/root/tests/replays" "$W/root/rpl2" "$W/exp"
for r in a b c d e; do : > "$W/root/tests/replays/$r.rpl"; done
: > "$W/root/rpl2/z.rpl"
echo "exact basis -" > "$W/exp/a.masked"; : > "$W/exp/b.skip"; : > "$W/exp/c.sha1"; : > "$W/exp/notareplay.masked"
echo "basis 42" > "$W/exp/d.diverge"

out="$(enumerate_expectations "$W/exp" "$W/root")" && rc=0 || rc=$?
[ "$rc" = 0 ] && ok "four known kinds, no pending -> exit 0" || bad "exit $rc on a clean dir"
[ "$out" = "$(printf 'a|masked|EVAL\nb|skip|SKIP\nc|sha1|N/A\nd|diverge|EVAL')" ] && ok "one line per expectation, kind and disposition named (incl. .diverge, H3)" || bad "output: $(printf '%s' "$out" | tr '\n' ';')"
printf '%s' "$out" | grep -q notareplay && bad "a file whose stem is not a replay was listed" || ok "a non-replay stem is ignored"

rm "$W/exp/d.diverge"; echo "pending prose" > "$W/exp/d.pending"
enumerate_expectations "$W/exp" "$W/root" > "$W/o2" && bad "a .pending did not make it non-zero" || ok "a .pending makes it non-zero (NOT-EVALUATED, reported not included)"
grep -q "d|pending|NOT-EVALUATED" "$W/o2" && ok "…and it is named" || bad "pending not named"
rm "$W/exp/d.pending"; : > "$W/exp/e.weird"
enumerate_expectations "$W/exp" "$W/root" > "$W/o3" && bad "an unknown kind did not make it non-zero" || ok "an unknown kind makes it non-zero"
grep -q "e|weird|UNKNOWN-KIND" "$W/o3" && ok "…as UNKNOWN-KIND" || bad "unknown kind not named"
rm "$W/exp/e.weird"

echo "exact basis -" > "$W/exp/z.masked"
out="$(enumerate_expectations "$W/exp" "$W/root" rpl2)"
[ "$out" = "z|masked|EVAL" ] && ok "a third argument selects the replays dir" || bad "argument replays dir: '$out'"
out="$(BBH_REPLAYS_DIR=rpl2 enumerate_expectations "$W/exp" "$W/root")"
[ "$out" = "z|masked|EVAL" ] && ok "BBH_REPLAYS_DIR selects it too" || bad "env replays dir: '$out'"

echo
[ "$fail" = 0 ] && echo "PASS" || { echo "FAIL"; exit 1; }
