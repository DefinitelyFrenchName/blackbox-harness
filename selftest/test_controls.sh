#!/bin/sh
# test_controls.sh — ground truth for THE MUST-FIRE CONTRACT'S READER,
# lib/sh/controls.sh: the four regexes of the grammar, the leading comment
# block as the header (a bare `#` continues it, a non-comment line ends it),
# the declared-vs-fired readback the classifier turns into FAIL, the
# `CONTROL=<name>` mode with its REFUSED exit, the `none` declaration, and
# the executable verdicts (bbh-classify --control). ROM-free, ~1 s.
#
# MUST-FIRE: known-bad: dead-control-log — a synthetic gate that declares a control and prints `CONTROL DEAD:` for it must classify FAIL through the shipped classifier, or a dead control would keep its gate green
# MUST-FIRE: known-bad: undeclared-firing — a synthetic log printing `CONTROL FIRED:` for a name no header declares must classify FAIL, or a control nobody can review would count
#
# WHY. Verdict logic is itself tested (docs/doctrine.md). This reader is what
# every runner trusts to say whether a gate's controls fired; a reader that
# missed a declaration would silently turn the doctrine back into prose.
# Lineage: VampireSaved's tests/test_controls_contract.sh — the same cases,
# so the two copies cannot drift apart unnoticed.
set -u
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
. "$BBH_HOME/lib/sh/controls.sh"
bbh_ctl_mode "$0"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
rc=0; ok() { printf '  ok    %s\n' "$*"; }; bad() { printf '  FAIL  %s\n' "$*"; rc=1; }

mkgate() {  # mkgate <path> <header lines...>  — a stub whose header is the argument list
    _p="$1"; shift
    { echo "#!/bin/sh"; for l in "$@"; do echo "$l"; done; echo 'echo "PASS"'; echo "exit 0"; } > "$_p"
    chmod +x "$_p"
}

echo "== 1. the header is the LEADING COMMENT BLOCK; a bare # continues it =="
mkgate "$T/g1.sh" "# g1.sh — a gate" "#" "# MUST-FIRE: perturbed-copy: alpha — one byte flipped must fail" \
    "# prose" "#" "# MUST-FIRE: shadow-tool: beta-2 — a stripped tool must fail"
got="$(bbh_ctl_declared "$T/g1.sh" | tr '\n' ' ')"
[ "$got" = "alpha beta-2 " ] && ok "two declarations read across a bare # ($got)" || bad "declared read '$got', expected 'alpha beta-2 '"
{ echo "#!/bin/sh"; echo "# g2.sh — a gate"; echo "set -u"; echo "# MUST-FIRE: known-bad: late — not a header line"; echo "exit 0"; } > "$T/g2.sh"
[ -z "$(bbh_ctl_declared "$T/g2.sh")" ] && ok "a MUST-FIRE line below the first code line is NOT a declaration" || bad "a line outside the leading block was read as a declaration"
mkgate "$T/g3.sh" "# MUST-FIRE: synthetic: x — wrong shape" "# MUST-FIRE: known-bad: Bad_Name — bad name" "# MUST-FIRE: known-bad: ok-name - hyphen not em dash"
[ -z "$(bbh_ctl_declared "$T/g3.sh")" ] && ok "a wrong shape, a bad name and a hyphen separator are all rejected" || bad "the grammar accepted a malformed line: $(bbh_ctl_declared "$T/g3.sh")"

echo "== 2. the none declaration =="
mkgate "$T/g4.sh" "# g4.sh — lists things" "# MUST-FIRE: none — a registry lister asserts no property"
[ "$(bbh_ctl_none "$T/g4.sh")" = "a registry lister asserts no property" ] && ok "none reason read" || bad "none reason not read"
: > "$T/g4.log"; bbh_ctl_read "$T/g4.sh" "$T/g4.log"
[ "$BBH_CTL_VERDICT" = NONE ] && ok "a none-declaring gate reads NONE" || bad "expected NONE, got $BBH_CTL_VERDICT"

echo "== 3. declared vs fired, through bbh_ctl_read =="
printf 'CONTROL FIRED: alpha — the byte was caught\nCONTROL FIRED: beta-2 — the tool failed\n' > "$T/ok.log"
bbh_ctl_read "$T/g1.sh" "$T/ok.log"
[ "$BBH_CTL_VERDICT" = OK ] && [ "$BBH_CTL_FIRED" = 2 ] && ok "both fired -> OK, fired 2 / declared $BBH_CTL_DECLARED" || bad "OK case: verdict $BBH_CTL_VERDICT fired $BBH_CTL_FIRED"
printf 'CONTROL FIRED: alpha — the byte was caught\n' > "$T/miss.log"
bbh_ctl_read "$T/g1.sh" "$T/miss.log"
[ "$BBH_CTL_VERDICT" = RED ] && ok "a declared control that did not fire -> RED ($BBH_CTL_DETAIL)" || bad "not-fired case: verdict $BBH_CTL_VERDICT"
printf '  CONTROL FIRED: alpha — indented is prose\nCONTROL FIRED: beta-2 — ok\n' > "$T/indent.log"
bbh_ctl_read "$T/g1.sh" "$T/indent.log"
[ "$BBH_CTL_VERDICT" = RED ] && ok "an INDENTED FIRED line is prose, not a firing (alpha still not fired)" || bad "an indented line counted as a firing"
: > "$T/empty.log"; mkgate "$T/g5.sh" "# g5.sh — no declaration at all"
bbh_ctl_read "$T/g5.sh" "$T/empty.log"
[ "$BBH_CTL_VERDICT" = UNDECLARED ] && ok "no declaration, no firing -> UNDECLARED (counted, never failed)" || bad "expected UNDECLARED, got $BBH_CTL_VERDICT"

echo "== 4. the classifier turns a red block into plain FAIL (and leaves the rest alone) =="
. "$BBH_HOME/lib/sh/classify.sh"
printf 'PASS: fine\nCONTROL FIRED: alpha — x\nCONTROL DEAD: beta-2 — the copy passed\n' > "$T/dead.log"
bbh_classify 0 "$T/dead.log" 90 "$T/g1.sh"
if [ "$BBH_VERDICT" = FAIL ]; then bbh_ctl_fired dead-control-log "exit 0 + a CONTROL DEAD line classifies FAIL: $BBH_DETAIL"
else bbh_ctl_dead dead-control-log "exit 0 + a CONTROL DEAD line classified $BBH_VERDICT"; rc=1; fi
printf 'PASS: fine\nCONTROL FIRED: ghost — nobody declared me\n' > "$T/ghost.log"
bbh_classify 0 "$T/ghost.log" 90 "$T/g5.sh"
if [ "$BBH_VERDICT" = FAIL ]; then bbh_ctl_fired undeclared-firing "a FIRED line no header declares classifies FAIL: $BBH_DETAIL"
else bbh_ctl_dead undeclared-firing "an undeclared firing classified $BBH_VERDICT"; rc=1; fi
bbh_classify 0 "$T/ok.log" 90 "$T/g1.sh"
[ "$BBH_VERDICT" = PASS ] && ok "both fired -> the verdict stays PASS" || bad "a green controls block changed the verdict to $BBH_VERDICT"
bbh_classify 0 "$T/empty.log" 90 "$T/g5.sh"
[ "$BBH_VERDICT" = PASS ] && ok "an undeclared gate is left PASS (identity for gates that predate the grammar)" || bad "an undeclared gate was failed: $BBH_VERDICT"
printf 'SKIP: no build\n' > "$T/skip.log"
bbh_classify 0 "$T/skip.log" 90 "$T/g1.sh"
[ "$BBH_VERDICT" = SKIP ] && ok "a SKIP stays SKIP — a skipped gate ran nothing, so no control is owed" || bad "a SKIP was changed to $BBH_VERDICT"
bbh_classify 1 "$T/ok.log" 90 "$T/g1.sh"
[ "$BBH_VERDICT" = FAIL ] && ok "a FAIL stays FAIL whatever the controls say" || bad "exit 1 became $BBH_VERDICT"
bbh_classify 0 "$T/dead.log" 90
[ "$BBH_VERDICT" = PASS ] && ok "without a gate script the classifier does not read controls (the 3-argument contract, byte for byte)" || bad "the 3-argument form changed its verdict to $BBH_VERDICT"
v="$("$BBH_HOME/bin/bbh-classify" 0 "$T/dead.log" --gate "$T/g1.sh" | cut -f1)"
[ "$v" = FAIL ] && ok "bbh-classify --gate reads the same block (FAIL)" || bad "bbh-classify --gate: $v"

echo "== 5. the CONTROL=<name> mode =="
cat > "$T/g6.sh" <<'EOG'
#!/bin/sh
# g6.sh — honours one mode
# MUST-FIRE: perturbed-copy: flip — the flipped input must fail
. "$LIB"
bbh_ctl_mode "$0"
if bbh_ctl_is flip; then echo "FAIL: flipped"; exit 1; fi
echo "PASS"; exit 0
EOG
chmod +x "$T/g6.sh"
LIB="$BBH_HOME/lib/sh/controls.sh" sh "$T/g6.sh" > "$T/o1" 2>&1 && s1=0 || s1=$?
[ "$s1" = 0 ] && grep -q '^PASS' "$T/o1" && ok "no CONTROL: the gate runs normally (exit 0)" || bad "plain run: exit $s1: $(cat "$T/o1")"
LIB="$BBH_HOME/lib/sh/controls.sh" CONTROL=flip sh "$T/g6.sh" > "$T/o2" 2>&1 && s2=0 || s2=$?
[ "$s2" = 1 ] && grep -q '^CONTROL MODE: flip' "$T/o2" && grep -q '^FAIL' "$T/o2" && ok "CONTROL=flip: the mode is announced and the gate reaches its own FAIL (exit 1)" || bad "mode run: exit $s2: $(cat "$T/o2")"
LIB="$BBH_HOME/lib/sh/controls.sh" CONTROL=nope sh "$T/g6.sh" > "$T/o3" 2>&1 && s3=0 || s3=$?
[ "$s3" = 3 ] && grep -q '^REFUSED: CONTROL=nope is not a mode of this gate' "$T/o3" && ok "an undeclared name is REFUSED with exit 3" || bad "undeclared mode: exit $s3: $(cat "$T/o3")"

echo "== 6. the executable verdicts (bbh_classify_control / bbh-classify --control) =="
xv() {  # xv <label> <exit> <expected> <log lines...>
    _l="$1"; _st="$2"; _exp="$3"; shift 3
    : > "$T/x.log"; for line in "$@"; do printf '%s\n' "$line" >> "$T/x.log"; done
    _got="$("$BBH_HOME/bin/bbh-classify" "$_st" "$T/x.log" --control | cut -f1)"
    [ "$_got" = "$_exp" ] && ok "$_l -> $_exp" || bad "$_l: got $_got, expected $_exp"
}
xv "exit 1 with the gate's FAIL"            1 HONOURED "CONTROL MODE: flip — …" "FAIL: caught"
xv "exit 0 under the mode"                  0 LIES     "CONTROL MODE: flip — …" "PASS: nothing changed"
xv "a SKIP under the mode"                  0 LIES     "SKIP: no build"
xv "the REFUSED line"                       3 REFUSED  "REFUSED: CONTROL=flip is not a mode of this gate"
xv "exit 0 after a shell error"             0 DIED     "tests/g.sh: line 9: FOO: parameter not set"
xv "a traceback with a non-zero exit"       1 DIED     "Traceback (most recent call last):" "  File x" "ValueError: boom"
xv "exit 124 (the timeout wrapper)"       124 TIMEOUT  "partial"

echo "== 7. this gate declares what it prints (dogfood) =="
for n in $(bbh_ctl_declared "$0"); do
    grep -q "bbh_ctl_fired $n " "$0" && ok "declared control '$n' has a FIRED site in the code" || bad "declared control '$n' is never fired by this gate"
done

echo
[ "$rc" = 0 ] && echo "PASS: the must-fire contract's reader reads what the grammar says." \
             || echo "FAIL: see above."
exit $rc
