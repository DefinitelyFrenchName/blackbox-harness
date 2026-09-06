#!/bin/sh
# test_classify.sh — ground truth for lib/sh/classify.sh: every verdict case
# both runners depend on, plus a MUST-FIRE control that the [classify] config
# actually reaches the classifier. ROM-free, ~1 s.
#
# Lineage: VampireSaved's test_static_runner.sh §1 and test_emulator_runner.sh
# §12 — the SKIP-in-prose case, the SKIP-and-exit-2 case, the exit-0-after-a-
# shell-error case and its benign segfault look-alike were each paid for.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT INT TERM

case_() {  # case_ <label> <exit> <expected-verdict> <log lines...>
    _l="$1"; _st="$2"; _exp="$3"; shift 3
    : > "$W/log"; for line in "$@"; do printf '%s\n' "$line" >> "$W/log"; done
    _got="$("$BBH_HOME/bin/bbh-classify" "$_st" "$W/log" | cut -f1)"
    [ "$_got" = "$_exp" ] && ok "$_l -> $_exp" || fail "$_l: got $_got, expected $_exp"
}
echo "== 1. the verdict cases =="
case_ "exit 0, PASS line"                 0 PASS "all good" "PASS: fine"
case_ "exit 1, FAIL line"                 1 FAIL "something broke" "FAIL: nope"
case_ "exit 0, SKIP marker"               0 SKIP "SKIP: no build at build/nope"
case_ "exit 0, indented SKIP marker"      0 SKIP "  SKIP: indented"
case_ "exit 0, SKIP only in prose"        0 PASS "checked 3 things, none had to be skipped" "PASS: prose only"
case_ "SKIP marker AND exit 2"            2 FAIL "  SKIPPED: no reference binary" "PARTIAL: the invariant was NOT run"
case_ "exit 124 (timeout)"              124 TIMEOUT "partial output"
case_ "exit 137 (timeout -k)"           137 TIMEOUT ""
case_ "exit 0 after a shell error"        0 FAIL "tests/g.sh: line 3: FOO: set FOO to a dir OUTSIDE the repo"
case_ "exit 0, benign teardown segfault"  0 PASS "PASS: the summary line" "tests/g.sh: line 64:  2444 Segmentation fault: 11  REPLAY=x"
case_ "exit 0, empty log"                 0 PASS

echo "== 2. the detail line =="
printf 'SKIP: reason one\nSKIP: reason two\n' > "$W/log"
d="$("$BBH_HOME/bin/bbh-classify" 0 "$W/log" | cut -f2)"
[ "$d" = "SKIP: reason one" ] && ok "SKIP detail is the FIRST marker line" || fail "SKIP detail '$d'"
printf 'x\nFAIL: the real reason\n' > "$W/log"
d="$("$BBH_HOME/bin/bbh-classify" 1 "$W/log" | cut -f2)"
[ "$d" = "exit 1: FAIL: the real reason" ] && ok "FAIL detail carries the exit and the last FAIL line" || fail "FAIL detail '$d'"
printf 'SKIP: %s\n' "$(printf 'x%.0s' $(seq 1 120))" > "$W/log"
d="$("$BBH_HOME/bin/bbh-classify" 0 "$W/log" --width 20 | cut -f2)"
[ "${#d}" = 20 ] && ok "--width cuts the detail (20 chars)" || fail "--width ignored: ${#d} chars"

echo "== 3. MUST-FIRE: the config reaches the classifier =="
mkdir -p "$W/c/tests"
printf '[classify]\nskip_regex = "^SKIPPED"\ntimeout_exits = [99]\n' > "$W/c/bbh.toml"
printf 'SKIP: the default marker\n' > "$W/log"
v="$("$BBH_HOME/bin/bbh-classify" 0 "$W/log" --config "$W/c/bbh.toml" | cut -f1)"
[ "$v" = PASS ] && ok "a consumer skip_regex replaces the default (SKIP: is no longer a marker)" || fail "config skip_regex not applied: $v"
printf 'SKIPPED: theirs\n' > "$W/log"
v="$("$BBH_HOME/bin/bbh-classify" 0 "$W/log" --config "$W/c/bbh.toml" | cut -f1)"
[ "$v" = SKIP ] && ok "…and the consumer's own marker is read" || fail "consumer marker not read: $v"
v="$("$BBH_HOME/bin/bbh-classify" 99 "$W/log" --config "$W/c/bbh.toml" | cut -f1)"
[ "$v" = TIMEOUT ] && ok "a consumer timeout_exits list is read (99 -> TIMEOUT)" || fail "timeout_exits not applied: $v"
v="$("$BBH_HOME/bin/bbh-classify" 124 "$W/log" --config "$W/c/bbh.toml" | cut -f1)"
[ "$v" = FAIL ] && ok "…and REPLACES the default (124 is FAIL under that config)" || fail "default timeout list leaked: $v"

echo
[ "$rc" = 0 ] && echo "PASS: the classifier's verdicts mean what they say" || { echo "FAIL: see above"; exit 1; }
