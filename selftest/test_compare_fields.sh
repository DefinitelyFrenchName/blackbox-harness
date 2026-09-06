#!/bin/sh
# test_compare_fields.sh — ground truth for lib/py/bbh/compare_fields.py, the
# dual-implementation field comparator, on the FAKE machine: its verdicts
# are trusted only after it agrees on known-good content and disagrees on
# known-different content (the verdict-logic doctrine). ROM-free, ~3 s.
#
# The lineage's two controls (VampireSaved test_compare_fields_selfcheck.sh,
# which needs two emulators): a POSITIVE control — two runs whose anchors
# sit on DIFFERENT frames (a 7-frame skew, the cross-implementation shape)
# agree on every stable field at the anchor and after it; a NEGATIVE
# control — different content FAILS with exit 3. Then what the lineage could
# not assert ROM-free: the §4 shape itself (a hooked build agrees with the
# base at anchors and differs frame-exact on its phase field), settled
# fields joining at --settle, --skip-fields, the debounce (a transient edge
# is a NOTE, a window starting true is a WARNING), a frame missing at a
# follow offset, the `# base` TSV headers overriding [fields].bases (the
# config MUST-FIRE: wrong bases read the wrong address), the anchor hint,
# and the TSV's own error texts.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
cd "$BBH_HOME/example"
cat > "$T/bbh.toml" <<'EOF'
[fields]
table = "fields.tsv"
bases = { p1 = 0x400, p2 = 0x402 }
anchor = [[0x100, 1, 2], [0x400, 1, 100], [0x402, 1, 100]]
anchor_hint = "dump 0100-0110 and 0400-0404"
stable = 30
settle = 60
EOF
printf 'mode\tabs\t0x100\t1\tstable\tthe machine mode (2 = match)\ntimer\tabs\t0x102\t2\tstable\nsp\tabs\t0x104\t1\tstable\tcredits\np1_hp\tp1\t0x0\t1\tstable\np2_hp\tp2\t0x0\t1\tstable\np1_port\tabs\t0x58\t2\tsettled\nlate\tabs\t0x700\t1\tphase\tthe hook writes it a frame late\n' > "$T/fields.tsv"
printf '100 sys=C1\n200 sys=S1\n450 p1=1\n600 wait\n' > "$T/a.rpl"          # the mode byte reads 2 from frame 401; P1 presses at +49
printf '100 sys=C1\n207 sys=S1\n457 p1=1\n607 wait\n' > "$T/b.rpl"          # the same, skewed 7 frames: the anchor at 408
printf '100 sys=C1\n200 sys=S1\n450 p2=1\n600 wait\n' > "$T/c.rpl"          # different content: P2 presses instead
spec() { python3 -c "print(';'.join(f'{f}:0100-0110;{f}:0400-0404;{f}:0058-005e;{f}:0700-0702' for f in range($1, $2 + 1)))"; }
run() {  # run <dir> <rpl> <build> [first last]
    mkdir -p "$T/$1"
    DUMPS="$(spec "${4:-380}" "${5:-520}")" FAKE_ROMPATH="roms/$3" "$BBH_HOME/drivers/fake.sh" fake "$2" "$T/$1/out.log" "$T/$1/box" > /dev/null
}
run A "$T/a.rpl" base; run B "$T/b.rpl" base; run C "$T/c.rpl" base; run D "$T/a.rpl" build-a
CF="python3 -m bbh.compare_fields --config $T/bbh.toml"

echo "== 1. anchors =="
[ "$($CF "$T/A" --list-anchors 2>/dev/null)" = 401 ] && ok "A's anchor is the match start, frame 401 (the mode byte is written before the transition, so the first frame that READS 2)" || fail "A anchors: $($CF "$T/A" --list-anchors 2>&1)"
[ "$($CF "$T/B" --list-anchors 2>/dev/null)" = 408 ] && ok "B's anchor is 408: the same state on a different frame index" || fail "B anchors: $($CF "$T/B" --list-anchors 2>&1)"

echo "== 2. the positive control: skewed runs agree at anchors =="
o="$($CF "$T/A" "$T/B" --fields "$T/fields.tsv" --follow 0,30,60 --label-a A --label-b B 2>&1)" && ok "exit 0" || fail "positive control disagreed: $o"
printf '%s\n' "$o" | grep -q '^anchors: A=\[401\] B=\[408\]$' && ok "the anchors line names both sides' frames" || fail "anchors line: $(printf '%s\n' "$o" | head -1)"
printf '%s\n' "$o" | grep -q '^OK: all compared fields agree$' && ok "the lineage's OK line" || fail "no OK line"

echo "== 3. the negative control: different content FAILS =="
o="$($CF "$T/A" "$T/C" --fields "$T/fields.tsv" --follow 0,60 --label-a A --label-b C 2>&1)" && fail "different content agreed" || st=$?
[ "${st:-0}" = 3 ] && ok "exit 3" || fail "exit ${st:-0}, expected 3"
printf '%s\n' "$o" | grep -q '^MISMATCH anchor0+60 (A:461/C:461) p1_hp \$000400.1 A=64 C=63$' && ok "the MISMATCH line: tag, field, address.width, both values" || fail "mismatch line: $(printf '%s\n' "$o" | grep MISMATCH | head -1)"
printf '%s\n' "$o" | grep -q '^FAIL: 2 disagreement(s)$' && ok "two disagreements (p1_hp and p2_hp), none at +0 where the HPs still agree" || fail "count: $(printf '%s\n' "$o" | tail -1)"

echo "== 4. the §4 shape: a hooked build agrees at anchors and differs frame-exact =="
$CF "$T/A" "$T/D" --fields "$T/fields.tsv" --follow 0,30,60 >/dev/null 2>&1 && ok "base vs build-a at anchors: OK (the phase field is not compared cross-implementation)" || fail "base vs build-a disagreed at anchors"
o="$($CF "$T/A" "$T/D" --fields "$T/fields.tsv" --exact --label-a base --label-b hook 2>&1)" && fail "--exact agreed across the hook's late write" || true
printf '%s\n' "$o" | grep -q '^MISMATCH frame 450 late \$000700.1 base=' && printf '%s\n' "$o" | grep -q '^exact mode: 141 frames compared$' && ok "--exact: the late byte differs at the press frame; 141 common frames compared" || fail "exact: $(printf '%s\n' "$o" | head -2)"
$CF "$T/A" "$T/D" --fields "$T/fields.tsv" --exact --skip-fields late >/dev/null 2>&1 && ok "--skip-fields late: --exact then agrees" || fail "--skip-fields"

echo "== 5. settled fields join at --settle =="
o="$($CF "$T/A" "$T/C" --fields "$T/fields.tsv" --follow 0,49 --settle 49 2>&1 || true)"
printf '%s\n' "$o" | grep -q 'MISMATCH anchor0+49 (A:450/B:450) p1_port' && ok "at --settle 49 the port (settled) is compared at +49, the press frame, where the two replays press different players" || fail "settled: $(printf '%s\n' "$o" | grep p1_port || echo none)"
o="$($CF "$T/A" "$T/C" --fields "$T/fields.tsv" --follow 0,49 --settle 50 2>&1 || true)"
printf '%s\n' "$o" | grep -q 'p1_port' && fail "a settled field was compared before --settle" || ok "at --settle 50 it is not compared at +49"

echo "== 6. the debounce and a missing frame (fabricated dumps) =="
python3 - "$T" <<'EOF'
import os
T = os.environ.get("T") or __import__("sys").argv[1]
def side(name, frames, pred_at, hole=None):
    d = f"{T}/{name}"; os.makedirs(d, exist_ok=True)
    for f in frames:
        if f == hole: continue
        p = bytearray(0x10); p[0] = 2 if pred_at(f) else 1; p[2:4] = (5000).to_bytes(2, "big")
        open(f"{d}/dump_{f}_000100.bin", "wb").write(p)
        open(f"{d}/dump_{f}_000400.bin", "wb").write(bytes([100, 0, 100, 0]))
        open(f"{d}/dump_{f}_000058.bin", "wb").write(bytes(6)); open(f"{d}/dump_{f}_000700.bin", "wb").write(bytes(2))
side("W", range(100, 160), lambda f: True)                                  # true from the first frame
side("N", range(100, 200), lambda f: 120 <= f < 125 or f >= 150)            # a 5-frame flicker, then a real edge at 150
side("H", range(100, 200), lambda f: f >= 150, hole=180)                    # the real edge, a hole at +30
side("G", range(100, 200), lambda f: f >= 150)
EOF
o="$($CF "$T/W" --list-anchors 2>&1 >/dev/null)"
printf '%s\n' "$o" | grep -q '^WARNING: predicate already true at window start (frame 100) — anchor may precede the dumped window$' && ok "a window that starts true is a WARNING, not an anchor" || fail "warning: $o"
o="$($CF "$T/N" --list-anchors 2>&1)"
printf '%s\n' "$o" | grep -q '^NOTE: transient/uncovered predicate edge at frame 120 ignored (debounce)$' && printf '%s\n' "$o" | grep -q '^150$' && ok "a 5-frame flicker is a NOTE; the held edge at 150 is the anchor" || fail "debounce: $o"
o="$($CF "$T/G" "$T/H" --fields "$T/fields.tsv" --follow 0,30 2>&1 || true)"
printf '%s\n' "$o" | grep -q '^MISSING anchor0+30: frame not dumped (A:180 in=True, B:180 in=False)$' && ok "a frame missing at a follow offset is MISSING, with which side lacks it" || fail "missing frame: $(printf '%s\n' "$o" | grep MISSING || echo none)"

echo "== 7. MUST-FIRE on the config: bases =="
sed 's/p1 = 0x400/p1 = 0x500/' "$T/bbh.toml" > "$T/bad.toml"
o="$(python3 -m bbh.compare_fields --config "$T/bad.toml" "$T/A" "$T/B" --fields "$T/fields.tsv" 2>&1 || true)"
printf '%s\n' "$o" | grep -q '^MISSING anchor0+0 (A:401/B:408) p1_hp \$000500.1 not dumped on A$' && ok "a wrong p1 base reads an address nobody dumped: MISSING" || fail "bad base: $(printf '%s\n' "$o" | grep p1_hp || echo none)"
{ printf '# base p1=0x400\n# base p2=0x402\n'; cat "$T/fields.tsv"; } > "$T/fields_hdr.tsv"
python3 -m bbh.compare_fields --config "$T/bad.toml" "$T/A" "$T/B" --fields "$T/fields_hdr.tsv" >/dev/null 2>&1 && ok "the TSV's own '# base p1=…' headers override the config" || fail "TSV base headers not honoured"

echo "== 8. the error texts =="
mkdir -p "$T/P"; cp "$T/A"/dump_400_000100.bin "$T/A"/dump_401_000100.bin "$T/P/"
o="$($CF "$T/P" --list-anchors 2>&1 || true)"
[ "$o" = 'anchor predicate field $000400 not covered by dumps (dump 0100-0110 and 0400-0404)' ] && ok "a predicate field outside the dumps names the address and the consumer's hint" || fail "hint: $o"
printf 'x\tp3\t0x0\t1\n' > "$T/bad.tsv"
o="$($CF "$T/A" "$T/B" --fields "$T/bad.tsv" 2>&1 || true)"
[ "$o" = "$T/bad.tsv:1: base must be abs|p1|p2" ] && ok "an unknown base names the vocabulary (abs + the configured bases)" || fail "base error: $o"
printf 'x\tabs\t0x0\t3\n' > "$T/bad2.tsv"
o="$($CF "$T/A" "$T/B" --fields "$T/bad2.tsv" 2>&1 || true)"
[ "$o" = "$T/bad2.tsv:1: width must be 1|2|4" ] && ok "the width error" || fail "width error: $o"

echo
[ "$rc" = 0 ] && echo "PASS: field-comparator verdicts validated against ground truth" || { echo "FAIL: see above"; exit 1; }
