#!/bin/sh
# test_check_dumps.sh — ground truth for lib/py/bbh/check_dumps.py: a
# per-frame dump directory is COMPLETE, or the comparison must not run.
# ROM-free, ~1 s.
#
# The lineage had no ground truth for this (it ran inside two MiSTer
# gates). Fabricated directories, every verdict: complete under
# --first/--last and under --contiguous; a MISSING frame; a dump OUTSIDE
# the range; a HOLE; a wrong --size; mixed sizes with no --size; a wrong
# --addr; not a directory; no dump files; --quiet; the driver-prefixed
# name (`<out>.dump_…`) matched by the default regex; and the MUST-FIRE on
# config — another [fields].dump_regex accepts another shape, and the
# advice lines are [fields].integrity_hint.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
python3 - "$T" <<'EOF'
import os, sys
T = sys.argv[1]
def mk(name, frames, size=16, addr="ff8000", prefix="", sizes=None):
    d = f"{T}/{name}"; os.makedirs(d, exist_ok=True)
    for i, f in enumerate(frames):
        n = (sizes or [size])[i % len(sizes or [size])]
        open(f"{d}/{prefix}dump_{f}_{addr}.bin", "wb").write(bytes(n))
mk("ok", range(10, 20))
mk("hole", [f for f in range(10, 20) if f != 15])
mk("extra", list(range(10, 20)) + [25])
mk("mixed", range(10, 20), sizes=[16, 8])
mk("fbneo", range(10, 20), prefix="out.")
mk("other", [], )
d = f"{T}/custom"; os.makedirs(d)
for f in range(1, 4): open(f"{d}/frame{f}_00ff00.raw", "wb").write(bytes(4))
os.makedirs(f"{T}/empty"); open(f"{T}/empty/notes.txt", "w").write("x")
EOF
CD="python3 -m bbh.check_dumps"
run() { $CD "$@" > "$T/out" 2> "$T/err" && echo 0 || echo $?; }
line() { grep -qF "$2" "$T/$1" && ok "$3" || fail "$3 — $1: $(cat "$T/$1" | head -3 | tr '\n' '|')"; }

echo "== 1. complete =="
[ "$(run "$T/ok" --first 10 --last 19 --size 16 --addr 0xFF8000)" = 0 ] && line out 'dump integrity OK: 10 frames 10..19, 16 bytes each addr $FF8000' "--first/--last/--size/--addr: OK, the lineage's line"
[ "$(run "$T/ok" --contiguous)" = 0 ] && line out 'dump integrity OK: 10 frames 10..19, 16 bytes each addr $FF8000' "--contiguous, no size given: the size is read from the files"
[ "$(run "$T/ok" --contiguous --quiet)" = 0 ] && [ ! -s "$T/out" ] && ok "--quiet prints nothing on success" || fail "--quiet"
[ "$(run "$T/fbneo" --first 10 --last 19)" = 0 ] && ok "the driver-prefixed name (out.dump_…) is matched by the default regex" || fail "prefixed names: $(cat "$T/err")"

echo "== 2. every failure, with its line =="
[ "$(run "$T/hole" --first 10 --last 19)" = 1 ] && line err '  1 MISSING frame(s) of 10: 15' "a missing frame under --first/--last"
[ "$(run "$T/hole" --contiguous)" = 1 ] && line err '  1 HOLE(s) in 10..19: 15' "a hole under --contiguous"
[ "$(run "$T/extra" --first 10 --last 19)" = 1 ] && line err '  1 dump(s) OUTSIDE [10,19]: 25' "a dump outside the range"
[ "$(run "$T/ok" --first 10 --last 19 --size 32)" = 1 ] && line err '  10 dump(s) not 32 bytes: 10, 11, 12, 13, 14, 15, 16, 17, 18, 19' "a wrong --size names every frame"
[ "$(run "$T/mixed" --contiguous)" = 1 ] && line err '  dumps have 2 different sizes: 8, 16' "mixed sizes with no --size"
[ "$(run "$T/ok" --first 10 --last 19 --addr 0xFF9000)" = 1 ] && line err '  file names carry address(es) $FF8000, expected $FF9000' "a wrong --addr"
line err 'DUMP INTEGRITY FAILED for' "…under the FAILED header"
line err '  frame set. Do not compare this run — see docs/platform/gotchas.md.' "…and the lineage's advice lines"
[ "$(run "$T/nowhere" --contiguous)" = 1 ] && line err 'is not a directory — the run produced no dumps at all' "not a directory"
[ "$(run "$T/empty" --contiguous)" = 1 ] && line err 'no dump_<frame>_<addr>.bin in' "a directory with no dump files"

echo "== 3. MUST-FIRE on the config =="
printf '[fields]\ndump_regex = %s\nintegrity_hint = ["CUSTOM ADVICE"]\n' "'^frame(\d+)_([0-9a-f]{6})\.raw$'" > "$T/bbh.toml"
[ "$(run "$T/custom" --config "$T/bbh.toml" --contiguous)" = 0 ] && line out 'dump integrity OK: 3 frames 1..3, 4 bytes each addr $00FF00' "another dump_regex accepts another file shape"
[ "$(run "$T/ok" --config "$T/bbh.toml" --contiguous)" = 1 ] && ok "…and under it the default shape is no longer a dump (no files)" || fail "custom regex still matched dump_…"
rm "$T/custom/frame2_00ff00.raw"
[ "$(run "$T/custom" --config "$T/bbh.toml" --contiguous)" = 1 ] && line err '  CUSTOM ADVICE' "the advice lines are [fields].integrity_hint"

echo
[ "$rc" = 0 ] && echo "PASS: an incomplete dump set is refused before it can move an anchor" || { echo "FAIL: see above"; exit 1; }
