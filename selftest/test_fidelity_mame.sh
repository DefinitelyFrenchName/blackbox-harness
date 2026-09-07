#!/bin/sh
# test_fidelity_mame.sh — FIDELITY F8: the MAME Lua layer, the MAME / FBNeo
# drivers and the recording tools against the lineage's, on the REAL
# emulators and ROMs (harness_scope.md §5 F8). OPT-IN: runs only with
# BBH_MAME_FIDELITY=1, ROMDIR set and the lineage tree beside this one;
# SKIPs otherwise. ~8 min (BBH_FIDELITY_F8=all: every tracked recording,
# ~+7 min).
#
#   F8a  one short replay through tools/run_replay_mame.sh and
#        drivers/mame.sh (BBH_PROFILE=cps2): logs `cmp`'d, unmasked and
#        under the lineage's default mask.
#   F8b  VIDEO_OUT / INPUT_OUT / DUMPS / POKES / SNAP_FRAMES parity: every
#        artifact byte-identical (the snapshot PNGs too).
#   F8c  INPUT_INJECT_TEST: both drivers exit 1 with the same
#        INPUT-VIOLATION line — the assertion's must-fire, on both sides.
#   F8d  the guard, cheap mode, on the lineage's crash-guard negative control
#        (02_demitri_vs_cpu with CODE_RANGES + GUARD_MATCH): logs identical
#        AND equal to the frozen .sha1 — the harness driver reproduces a
#        frozen expectation of the lineage.
#   F8e  the guard, authoritative mode, on test_crash_guard's POSITIVE
#        control (a planted ILLEGAL opcode, built with the lineage's own
#        patch tools): both exit 2, CRASH / REGS / STACK / END-CRASH lines
#        identical.
#   F8f  the .rpl grammar under MAME's own interpreter: rpl_dump.lua over
#        EVERY lineage replay == `bbh rpl dump` (the equality selftest that
#        SKIPs without a standalone lua, run on the production one).
#   F8g  a recording: tools/run_inp_guarded.sh vs bbh inp-play on the
#        shortest tracked recording (inp_guard.log identical: ALIVE lines,
#        PLAYBACK, END), then tests/test_inp_corpus.sh vs bbh inp-corpus on
#        it (verdict lines identical).
#   F8h  FBNeo: tools/run_replay_fbneo.sh vs drivers/fbneo.sh on the same
#        replay: logs, DUMPS files and the video log identical.
#
# MAME_BIN defaults to the lineage's pinned WIDE build (it knows vsavj too);
# both sides run the SAME binary, so the comparison measures the drivers and
# the Lua, never the instrument.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
[ "${BBH_MAME_FIDELITY:-0}" = 1 ] || { echo "SKIP: set BBH_MAME_FIDELITY=1 (with ROMDIR and the pinned MAME) to run F8 — ~8 min on the real emulators"; exit 0; }
CFG="$BBH_HOME/example/consumers/bbh.vampire.toml"
V="$(python3 -m bbh.config "$CFG" root 2>/dev/null || true)"
[ -n "$V" ] && [ -x "$V/tools/run_replay_mame.sh" ] || { echo "SKIP: the lineage tree is not at $V"; exit 0; }
[ -n "${ROMDIR:-}" ] && [ -d "$ROMDIR" ] || { echo "SKIP: ROMDIR is not set to the reference-set directory"; exit 0; }
ROMDIR="$(cd "$ROMDIR" && pwd)"; export ROMDIR
MAME_BIN="${MAME_BIN:-$HOME/.cache/vampire-saved/mame/cps2}"; export MAME_BIN
[ -x "$MAME_BIN" ] || { echo "SKIP: MAME_BIN is not executable: $MAME_BIN"; exit 0; }
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
unset MASK_RANGES DUMPS POKES SNAP_FRAMES VIDEO_OUT INPUT_OUT TAIL_FRAMES INPUT_INJECT_TEST NO_INPUT_CHECK GUARD_DEBUG CRASH_VECTORS CODE_RANGES GUARD_MATCH MAME_ROMPATH 2>/dev/null || true
LIN="$V/tools/run_replay_mame.sh"; LING="$V/tools/run_replay_guarded.sh"
BBH="$BBH_HOME/drivers/mame.sh"; BBHG="$BBH_HOME/drivers/mame_guarded.sh"
export BBH_PROFILE=cps2
RPL="$V/tests/replays/107_four_directions.rpl"     # 400 scripted frames — the shortest replay
t0=$(date +%s)

echo "== F8a. one replay, both drivers, unmasked and masked =="
"$LIN" vsavj "$RPL" "$T/a1.log" "$T/sa1" > "$T/o1" 2>&1 || fail "lineage driver: $(cat "$T/o1")"
"$BBH" vsavj "$RPL" "$T/b1.log" "$T/sb1" > "$T/o2" 2>&1 || fail "harness driver: $(cat "$T/o2")"
cmp -s "$T/a1.log" "$T/b1.log" && ok "unmasked: logs byte-identical ($(wc -l < "$T/a1.log" | tr -d ' ') lines, $(tail -1 "$T/a1.log"))" || fail "unmasked logs differ: $(diff "$T/a1.log" "$T/b1.log" | head -3)"
MASK="043c-043d,4182-41a2,7f00-8000"
MASK_RANGES="$MASK" "$LIN" vsavj "$RPL" "$T/a2.log" > /dev/null 2>&1 || fail "lineage masked run"
MASK_RANGES="$MASK" "$BBH" vsavj "$RPL" "$T/b2.log" > /dev/null 2>&1 || fail "harness masked run"
cmp -s "$T/a2.log" "$T/b2.log" && ! cmp -s "$T/a1.log" "$T/a2.log" && ok "under the lineage's default mask: identical, and the mask changed the hashes (a mask is a basis)" || fail "masked logs differ or the mask was inert"

echo "== F8b. VIDEO_OUT / INPUT_OUT / DUMPS / POKES / SNAP_FRAMES parity =="
mkdir -p "$T/da" "$T/db"
EXTRA='DUMPS=300:ff8000-ff8100;350:ff8400-ff8500 POKES=200:ff8100:01;250:ff8102:0203 SNAP_FRAMES=300,350'
env $EXTRA VIDEO_OUT="$T/da/v.log" INPUT_OUT="$T/da/i.log" "$LIN" vsavj "$RPL" "$T/da/r.log" "$T/da/sb" > /dev/null 2>&1 || fail "lineage extras run"
env $EXTRA VIDEO_OUT="$T/db/v.log" INPUT_OUT="$T/db/i.log" "$BBH" vsavj "$RPL" "$T/db/r.log" "$T/db/sb" > /dev/null 2>&1 || fail "harness extras run"
for f in r.log v.log i.log dump_300_ff8000.bin dump_350_ff8400.bin; do cmp -s "$T/da/$f" "$T/db/$f" && ok "$f identical" || fail "$f differs"; done
cmp -s "$T/da/r.log" "$T/a1.log" && fail "the pokes did not move the RAM log" || ok "MUST-FIRE: the pokes moved the RAM log on both sides alike"
na="$(ls "$T/da/sb/snap/vsavj/"*.png 2>/dev/null | wc -l | tr -d ' ')"; nb="$(ls "$T/db/sb/snap/vsavj/"*.png 2>/dev/null | wc -l | tr -d ' ')"
[ "$na" = 2 ] && [ "$nb" = 2 ] && cmp -s "$T/da/sb/snap/vsavj/0000.png" "$T/db/sb/snap/vsavj/0000.png" && cmp -s "$T/da/sb/snap/vsavj/0001.png" "$T/db/sb/snap/vsavj/0001.png" && ok "SNAP_FRAMES: two PNGs each, byte-identical" || fail "snapshots: $na vs $nb, or differ"

echo "== F8c. INPUT_INJECT_TEST: the must-fire on both sides =="
INPUT_INJECT_TEST=200 "$LIN" vsavj "$RPL" "$T/ia.log" > "$T/oa" 2>&1 && fail "lineage accepted an injection" || ra=$?
INPUT_INJECT_TEST=200 "$BBH" vsavj "$RPL" "$T/ib.log" > "$T/ob" 2>&1 && fail "harness accepted an injection" || rb=$?
[ "${ra:-0}" = 1 ] && [ "${rb:-0}" = 1 ] && [ "$(grep '^INPUT-VIOLATION' "$T/ia.log")" = "$(grep '^INPUT-VIOLATION' "$T/ib.log")" ] && grep -q '^INPUT-VIOLATION 1 frame 200' "$T/ib.log" && ok "both exit 1 with the same INPUT-VIOLATION line: $(grep '^INPUT-VIOLATION' "$T/ib.log" | cut -c1-60)…" || fail "inject: rc $ra/$rb; $(grep INPUT-VIOLATION "$T/ia.log" "$T/ib.log")"

echo "== F8d. the guard, cheap mode, on the crash guard's negative control =="
GRPL="$V/tests/replays/02_demitri_vs_cpu.rpl"
GUARD_DEBUG=0 CODE_RANGES="0-400000" GUARD_MATCH="3000-3100" "$LING" vsavj "$GRPL" "$T/ga.log" "$T/gsa" > "$T/o" 2>&1 || fail "lineage cheap guard: $(cat "$T/o")"
GUARD_DEBUG=0 CODE_RANGES="0-400000" GUARD_MATCH="3000-3100" "$BBHG" vsavj "$GRPL" "$T/gb.log" "$T/gsb" > "$T/o" 2>&1 || fail "harness cheap guard: $(cat "$T/o")"
cmp -s "$T/ga.log" "$T/gb.log" && ok "cheap-mode guard logs identical ($(tail -1 "$T/gb.log"))" || fail "cheap guard logs differ"
exp="$(cat "$V/tests/expected/vsavj/02_demitri_vs_cpu.sha1")"; got="$(shasum "$T/gb.log" | cut -d' ' -f1)"
[ "$got" = "$exp" ] && ok "…and equal to the lineage's FROZEN vsavj expectation ($exp)" || fail "frozen sha1 $exp, harness got $got"

echo "== F8e. the guard, authoritative mode, on the positive control (a planted ILLEGAL) =="
# The lineage guard's code window is the WIDE 6 MB one since 14z-138 (its two
# guards had disagreed), so this comparison runs under the cps2w profile.
export BBH_PROFILE=cps2w
cat > "$T/pick.rpl" <<'EOF'
300-305 sys=C1
800-803 sys=S1
1000-1002 p1=U
1040-1042 p1=U
1080-1082 p1=R
1700-1702 p1=1
3600 wait
EOF
python3 - "$T/ill.json" <<'PY'
import json, sys
ops = [{"op": "code", "addr": "0xBF800", "hex": "4afc"}]
for k in range(14):
    ops.append({"op": "poke32", "addr": hex(0x0BD0FA + k * 0x80 + 0x0F * 4), "val": "0x000BF800"})
json.dump({"ops": ops}, open(sys.argv[1], "w"))
PY
python3 "$V/tools/patch_prg.py" "$ROMDIR/vsavj.zip" "$T/ill_prg" --patch "$T/ill.json" > /dev/null
ROMDIR="$ROMDIR" "$V/tools/pack_build.sh" "$T/ill_prg" "$T/ill_rom" > /dev/null
MAME_ROMPATH="$T/ill_rom;$ROMDIR" "$LING" vsavj "$T/pick.rpl" "$T/ca.log" "$T/csa" > "$T/oa" 2>&1 && fail "lineage guard did not trip" || ra=$?
MAME_ROMPATH="$T/ill_rom;$ROMDIR" "$BBHG" vsavj "$T/pick.rpl" "$T/cb.log" "$T/csb" > "$T/ob" 2>&1 && fail "harness guard did not trip" || rb=$?
grep -E '^(CRASH|REGS|STACK|END-CRASH) ' "$T/ca.log" > "$T/ca.crash"; grep -E '^(CRASH|REGS|STACK|END-CRASH) ' "$T/cb.log" > "$T/cb.crash"
[ "${ra:-0}" = 2 ] && [ "${rb:-0}" = 2 ] && [ -s "$T/cb.crash" ] && cmp -s "$T/ca.crash" "$T/cb.crash" && ok "both exit 2; CRASH/REGS/STACK/END-CRASH identical: $(head -1 "$T/cb.crash")" || { fail "positive control: rc $ra/$rb"; diff "$T/ca.crash" "$T/cb.crash" | head -6 | sed 's/^/        /'; }
cmp -s "$T/ca.log" "$T/cb.log" && ok "…the whole -debug log too (deterministic on the same binary)" || fail "-debug logs differ"
[ -f "$T/csb/../cb.log" ] || true

export BBH_PROFILE=cps2
echo "== F8f. the .rpl grammar under MAME's interpreter =="
ls "$V"/tests/replays/*.rpl "$V"/tests/replays/*/*.rpl > "$T/files.txt"
python3 -m bbh.rpl dump $(cat "$T/files.txt") > "$T/py.txt"
RPL_DUMP_FILES="$(cat "$T/files.txt")" RPL_DUMP_OUT="$T/lua.txt" \
    "$MAME_BIN" vsavj -rompath "$ROMDIR" -video none -sound none -nothrottle -skip_gameinfo \
    -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none \
    -cfg_directory "$T/rd/cfg" -nvram_directory "$T/rd/nvram" -homepath "$T/rd" \
    -autoboot_script "$BBH_HOME/lua/mame/rpl_dump.lua" > "$T/rd.out" 2>&1 || true
cmp -s "$T/py.txt" "$T/lua.txt" && ok "rpl_parse.lua == rpl.py over $(wc -l < "$T/files.txt" | tr -d ' ') lineage replays, under MAME's Lua ($(wc -l < "$T/lua.txt" | tr -d ' ') lines)" || { fail "grammar parses differ"; diff "$T/py.txt" "$T/lua.txt" | head -6 | sed 's/^/        /'; }

echo "== F8g. a recording: the playback tool and the corpus gate =="
REC="crash-merged-m8-01"; [ "${BBH_FIDELITY_F8:-}" = all ] && REC=""
BUILD="$(python3 -m bbh.config "$CFG" get inp.build)"
export BBH_PROFILE=cps2w
mkdir -p "$T/h/.cache/vampire-saved/inp"
for d in "$V"/tests/inp/*/; do
    n="$(basename "$d")"; [ -z "$REC" ] || [ "$n" = "$REC" ] || continue
    cp -R "$d" "$T/h/.cache/vampire-saved/inp/$n"
    (cd "$V" && HOME="$T/h" STOP_AFTER=5 MAX_FRAMES=6000 tools/run_inp_guarded.sh "$BUILD" "$n" "$T/ga_$n" > "$T/oa_$n" 2>&1) || true
    STOP_AFTER=5 MAX_FRAMES=6000 "$BBH_HOME/bin/bbh-inp-play" --set vsavjw --rompath "$V/$BUILD/rompath;$ROMDIR" --inp "$d" --out "$T/gb_$n" > "$T/ob_$n" 2>&1 || true
    if cmp -s "$T/ga_$n/inp_guard.log" "$T/gb_$n/inp_guard.log"; then ok "$n: inp_guard.log identical ($(grep -c '^ALIVE' "$T/gb_$n/inp_guard.log") ALIVE lines, $(grep '^END' "$T/gb_$n/inp_guard.log"))"
    else fail "$n: inp_guard.log differs"; diff "$T/ga_$n/inp_guard.log" "$T/gb_$n/inp_guard.log" | head -4 | sed 's/^/        /'; fi
done
(cd "$V" && ONLY="$REC" sh tests/test_inp_corpus.sh > "$T/ca.txt" 2>&1; echo "exit=$?" >> "$T/ca.txt") || true
(cd "$V" && ONLY="$REC" "$BBH_HOME/bin/bbh" inp-corpus --config "$CFG" > "$T/cb.txt" 2>&1; echo "exit=$?" >> "$T/cb.txt") || true
cmp -s "$T/ca.txt" "$T/cb.txt" && ok "the corpus gate: verdict lines and exit identical ($(grep -c '^  ok:' "$T/cb.txt") clean, $(tail -2 "$T/cb.txt" | head -1))" || { fail "corpus verdicts differ"; diff "$T/ca.txt" "$T/cb.txt" | head -6 | sed 's/^/        /'; }
export BBH_PROFILE=cps2

echo "== F8h. FBNeo: both drivers on the same replay =="
FBNEO_BIN="$V/emu/fbneo/fbneo"; export FBNEO_BIN
if [ -x "$FBNEO_BIN" ]; then
    mkdir -p "$T/fa" "$T/fb"
    FBNEO_DUMPS="300:ff8000-ff8100" FBNEO_HVIDEO="$T/fa/v.log" "$V/tools/run_replay_fbneo.sh" vsavj "$RPL" "$T/fa/r.log" "$T/fa/sb" > "$T/o" 2>&1 || fail "lineage fbneo: $(tail -3 "$T/o")"
    DUMPS="300:ff8000-ff8100" VIDEO_OUT="$T/fb/v.log" "$BBH_HOME/drivers/fbneo.sh" vsavj "$RPL" "$T/fb/r.log" "$T/fb/sb" > "$T/o" 2>&1 || fail "harness fbneo: $(tail -3 "$T/o")"
    for f in r.log v.log r.log.dump_300_ff8000.bin; do cmp -s "$T/fa/$f" "$T/fb/$f" && ok "fbneo $f identical" || fail "fbneo $f differs"; done
    cmp -s "$T/fb/r.log" "$T/b1.log" && ok "…and the FBNeo RAM log equals the MAME one on this replay (the two implementations agree frame-exact here)" || echo "  note  the FBNeo and MAME logs differ on this replay (expected in general: two implementations, compared at anchors)"
else
    echo "  (no FBNeo binary at $FBNEO_BIN — F8h not run)"
fi

echo
echo "  ($(( $(date +%s) - t0 )) s)"
[ "$rc" = 0 ] && echo "PASS: F8 — the MAME Lua layer, the drivers and the recording tools reproduce the lineage's" || { echo "FAIL: see above"; exit 1; }
