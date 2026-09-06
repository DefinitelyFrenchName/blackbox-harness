#!/bin/sh
# test_driver_contract.sh — ground truth for drivers/README.md against
# drivers/fake.sh: the four-argument form and its path handling, the log
# grammar (one line per frame, END last), determinism, every variable of the
# replay family (MASK_RANGES DUMPS POKES SNAP_FRAMES VIDEO_OUT INPUT_OUT
# TAIL_FRAMES INPUT_INJECT_TEST NO_INPUT_CHECK), the REFUSAL of a variable
# the driver cannot honour, the guarded exit, the stale-artifact rule, and
# the fake machine's own knobs. ~4 s.
#
# MUST-FIRE controls: INPUT_INJECT_TEST must produce an INPUT-VIOLATION and
# a discarded run; the mask must be what makes two builds compare equal
# (unmasked they differ); a poke must move the hash at its frame.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
D="$BBH_HOME/drivers/fake.sh"; EX="$BBH_HOME/example"
R="$EX/roms/base"; RPL="$EX/replays/03_press.rpl"
export FAKE_ROMPATH="$R"
unset MASK_RANGES DUMPS POKES SNAP_FRAMES VIDEO_OUT INPUT_OUT TAIL_FRAMES INPUT_INJECT_TEST NO_INPUT_CHECK FAKE_BUILD FAKE_NONDET FAKE_CRASH_AT GUARD_DEBUG CRASH_VECTORS 2>/dev/null || true

echo "== 1. the invocation and the grammar =="
"$D" fake "$RPL" "$T/a.log" > "$T/o" && ok "<set> <replay> <out>: exit 0" || fail "basic run failed: $(cat "$T/o")"
[ "$(tail -1 "$T/a.log")" = "END 420" ] && ok "END <n> last: 300 scripted + 120 tail = END 420" || fail "last line: $(tail -1 "$T/a.log")"
[ "$(wc -l < "$T/a.log" | tr -d ' ')" = 421 ] && ok "one line per frame + END" || fail "$(wc -l < "$T/a.log") lines"
head -1 "$T/a.log" | grep -Eq '^1 [0-9a-f]{16}$' && ok "'<frame> <hash>', 16 hex characters, frame 1 first" || fail "first line: $(head -1 "$T/a.log")"
(cd "$T" && "$D" fake "$RPL" rel.log > /dev/null) && [ -f "$T/rel.log" ] && ok "a relative out path is made absolute" || fail "relative out"
(cd "$EX" && FAKE_ROMPATH=roms/base "$D" fake replays/03_press.rpl "$T/b.log" > /dev/null) && cmp -s "$T/a.log" "$T/b.log" && ok "a relative search path and replay resolve from the caller's directory" || fail "relative inputs"
(env -u FAKE_ROMPATH FAKE_ROOT="$R" "$D" fake "$RPL" "$T/c.log" > /dev/null) && cmp -s "$T/a.log" "$T/c.log" && ok "FAKE_ROOT is the fallback search path" || fail "FAKE_ROOT fallback"
env -u FAKE_ROMPATH "$D" fake "$RPL" "$T/d.log" > "$T/o" 2>&1 && fail "no search path was accepted" || { grep -q "set FAKE_ROMPATH" "$T/o" && ok "no search path: exit 1 and the variable named" || fail "no-path message: $(cat "$T/o")"; }
"$D" fake "$RPL" "$T/e.log" "$T/sb" > /dev/null && [ -f "$T/sb/fake_replay.log" ] && ok "the sandbox holds the machine's own log" || fail "sandbox"
(cd "$T" && "$D" fake "$RPL" f.log sbrel > /dev/null) && [ -d "$T/sbrel" ] && ok "a relative sandbox is made absolute" || fail "relative sandbox"

echo "== 2. determinism and the stale-artifact rule =="
"$D" fake "$RPL" "$T/g.log" > /dev/null; cmp -s "$T/a.log" "$T/g.log" && ok "two runs are bit-identical" || fail "nondeterministic"
FAKE_NONDET=1 "$D" fake "$RPL" "$T/n1.log" > /dev/null; FAKE_NONDET=1 "$D" fake "$RPL" "$T/n2.log" > /dev/null
cmp -s "$T/n1.log" "$T/n2.log" && fail "FAKE_NONDET=1 runs were identical" || ok "FAKE_NONDET=1: the nondeterministic path differs between runs"
printf 'END 999\n' > "$T/stale.log"
"$D" nosuch "$RPL" "$T/stale.log" > "$T/o" 2>&1 && fail "a missing set ran" || { [ ! -f "$T/stale.log" ] && ok "a failed run leaves NO artifact (the stale log was removed first)" || fail "stale log survived: $(cat "$T/stale.log")"; }

echo "== 3. MASK_RANGES: a mask is a basis =="
MASK_RANGES=ff00-10000 "$D" fake "$RPL" "$T/m.log" > /dev/null
cmp -s "$T/a.log" "$T/m.log" && fail "a mask did not change the hashes" || ok "masked hashes differ from unmasked (the mask skips bytes)"
FAKE_ROMPATH="$EX/roms/build-a" "$D" fake "$EX/replays/01_idle.rpl" "$T/ua.log" > /dev/null; "$D" fake "$EX/replays/01_idle.rpl" "$T/ub.log" > /dev/null
cmp -s "$T/ua.log" "$T/ub.log" && fail "MUST-FIRE: unmasked, the hooked build equalled base" || ok "MUST-FIRE: unmasked, a hooked build differs from base on every frame (its stack noise)"
FAKE_ROMPATH="$EX/roms/build-a" MASK_RANGES=ff00-10000 "$D" fake "$EX/replays/01_idle.rpl" "$T/ma.log" > /dev/null; MASK_RANGES=ff00-10000 "$D" fake "$EX/replays/01_idle.rpl" "$T/mb.log" > /dev/null
cmp -s "$T/ma.log" "$T/mb.log" && ok "under the mask the same pair is bit-identical" || fail "masked pair differs"
for bad in "ff00-fe00:inverted" "ff00-20000:runs past work RAM" "zz-yy:invalid"; do
    m="${bad%%:*}"; want="${bad#*:}"
    MASK_RANGES="$m" "$D" fake "$RPL" "$T/x.log" > "$T/o" 2>&1 && fail "bad mask '$m' accepted" || { grep -qi "$want\|MASK_RANGES\|invalid literal" "$T/o" && ok "bad mask '$m' refused ($want)" || fail "bad mask '$m': $(cat "$T/o")"; }
done

echo "== 4. DUMPS / POKES / SNAP_FRAMES / VIDEO_OUT / INPUT_OUT / TAIL_FRAMES =="
mkdir -p "$T/dd"; DUMPS="100:0000-0010;100:0058-005e" "$D" fake "$RPL" "$T/dd/d.log" > /dev/null
[ "$(wc -c < "$T/dd/dump_100_000000.bin" | tr -d ' ')" = 16 ] && [ "$(wc -c < "$T/dd/dump_100_000058.bin" | tr -d ' ')" = 6 ] && ok "DUMPS: dump_<frame>_<lo>.bin beside the log, the range's size" || fail "dumps: $(ls "$T/dd")"
python3 -c 'import sys; a=open(sys.argv[1],"rb").read(); b=open(sys.argv[2],"rb").read(); sys.exit(0 if a[:4]==(100).to_bytes(4,"big") and b[:2]==b"\x00\x10" else 1)' "$T/dd/dump_100_000000.bin" "$T/dd/dump_100_000058.bin" 2>/dev/null \
    && ok "…and the dump is the state at the END of frame 100 (counter 100, p1 button 1 in the mirror)" || fail "dump content"
POKES="50:1000:ff" "$D" fake "$RPL" "$T/p.log" > /dev/null
[ "$(sed -n 49p "$T/a.log")" = "$(sed -n 49p "$T/p.log")" ] && [ "$(sed -n 50p "$T/a.log")" != "$(sed -n 50p "$T/p.log")" ] && ok "POKES: frame 49 unchanged, frame 50's hash moved (MUST-FIRE)" || fail "poke did not land at 50"
SNAP_FRAMES=10,20 "$D" fake "$RPL" "$T/s.log" "$T/snapsb" > /dev/null
[ -f "$T/snapsb/snap_10.ppm" ] && [ -f "$T/snapsb/snap_20.ppm" ] && [ "$(head -c 2 "$T/snapsb/snap_10.ppm")" = "P6" ] && ok "SNAP_FRAMES: snap_<f>.ppm in the sandbox" || fail "snapshots: $(ls "$T/snapsb")"
VIDEO_OUT="$T/v.log" "$D" fake "$RPL" "$T/vr.log" > /dev/null
cmp -s "$T/a.log" "$T/vr.log" && [ "$(tail -1 "$T/v.log")" = "END 420" ] && [ "$(wc -l < "$T/v.log" | tr -d ' ')" = 421 ] && ok "VIDEO_OUT: a second log of the same grammar, the RAM log untouched" || fail "video out"
INPUT_OUT="$T/i.log" "$D" fake "$RPL" "$T/ir.log" > /dev/null
[ "$(sed -n 100p "$T/i.log")" = "100 0010 0000 0000" ] && [ "$(tail -1 "$T/i.log")" = "END 420" ] && ok "INPUT_OUT: '<frame> <p1> <p2> <sys>' — p1 button 1 = 0x0010 at frame 100" || fail "input out: $(sed -n 100p "$T/i.log")"
TAIL_FRAMES=5 "$D" fake "$RPL" "$T/t.log" > /dev/null; [ "$(tail -1 "$T/t.log")" = "END 305" ] && ok "TAIL_FRAMES=5: 300 + 5 = END 305" || fail "tail: $(tail -1 "$T/t.log")"

echo "== 5. the input-integrity assertion and its must-fire control =="
INPUT_INJECT_TEST=200 "$D" fake "$RPL" "$T/inj.log" > "$T/o" 2>&1 && fail "an injected violation was accepted" || st=$?
grep -q "^INPUT-VIOLATION 1 frame 200" "$T/inj.log" && grep -q "INPUT INTEGRITY VIOLATION" "$T/o" && [ "${st:-0}" = 1 ] && ok "MUST-FIRE: INPUT_INJECT_TEST=200 -> an INPUT-VIOLATION line before END, the driver exits 1 and discards the run" || fail "inject: rc=${st:-0} $(cat "$T/o")"
grep -q "^END 420" "$T/inj.log" && grep -n "INPUT-VIOLATION" "$T/inj.log" | grep -q "^421:" && ok "the violation line sits BEFORE END, where every consumer trips on it" || fail "violation placement"
NO_INPUT_CHECK=1 INPUT_INJECT_TEST=200 "$D" fake "$RPL" "$T/nic.log" > /dev/null && ! grep -q "INPUT-VIOLATION" "$T/nic.log" && ok "NO_INPUT_CHECK disables the assertion (the injection produces nothing)" || fail "NO_INPUT_CHECK"

echo "== 6. the guarded exit and the refusal =="
FAKE_CRASH_AT=77 "$D" fake "$RPL" "$T/cr.log" > "$T/o" 2>&1 && fail "a crash run exited 0" || st=$?
[ "$st" = 2 ] && grep -q "^GUARD TRIPPED:" "$T/o" && grep -q "^CRASH 77 vec4 PC" "$T/cr.log" && grep -q "^END-CRASH 77" "$T/cr.log" && ! grep -q "^END 4" "$T/cr.log" \
    && ok "FAKE_CRASH_AT=77: CRASH/REGS/STACK lines, END-CRASH instead of END, exit 2 with 'GUARD TRIPPED:'" || fail "crash: rc=$st $(cat "$T/o")"
GUARD_DEBUG=1 "$D" fake "$RPL" "$T/r.log" > "$T/o" 2>&1 && fail "GUARD_DEBUG was ignored" || st=$?
[ "$st" = 3 ] && grep -q "^REFUSED: drivers/fake.sh cannot honour GUARD_DEBUG" "$T/o" && [ ! -f "$T/r.log" ] && ok "a variable the driver cannot honour is REFUSED (exit 3), and no log is written" || fail "refusal: rc=$st $(cat "$T/o")"
CRASH_VECTORS=2,3 "$D" fake "$RPL" "$T/r2.log" > "$T/o" 2>&1 && fail "CRASH_VECTORS was ignored" || { grep -q "cannot honour CRASH_VECTORS" "$T/o" && ok "…every guard-family variable" || fail "CRASH_VECTORS: $(cat "$T/o")"; }

echo "== 7. the machine's own knobs =="
printf '100 p1=Z\n' > "$T/bad.rpl"
"$D" fake "$T/bad.rpl" "$T/bad.log" > "$T/o" 2>&1 && fail "a bad replay ran" || { grep -q "unknown token 'Z' for p1" "$T/o" && ok "a replay the grammar rejects fails with its line's reason" || fail "bad replay: $(cat "$T/o")"; }
FAKE_BUILD=both MASK_RANGES=ff00-10000 "$D" fake "$EX/replays/04_both.rpl" "$T/fb.log" > /dev/null
FAKE_ROMPATH="$EX/roms/build-a" MASK_RANGES=ff00-10000 "$D" fake "$EX/replays/04_both.rpl" "$T/fa.log" > /dev/null
cmp -s "$T/fb.log" "$T/fa.log" && ok "FAKE_BUILD=both on the base image == the build-a image (the ROM's features line, overridden)" || fail "FAKE_BUILD override"
FAKE_BUILD=nosuch "$D" fake "$RPL" "$T/ns.log" > "$T/o" 2>&1 && fail "an unknown feature ran" || { grep -q "unknown feature" "$T/o" && ok "an unknown feature is refused" || fail "$(cat "$T/o")"; }

echo
[ "$rc" = 0 ] && echo "PASS: drivers/fake.sh honours the contract, row by row" || { echo "FAIL: see above"; exit 1; }
