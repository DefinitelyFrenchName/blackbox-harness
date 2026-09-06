#!/bin/sh
# test_compare_flicker.sh — ground truth for the flicker comparator's verdict
# logic (classification code is validated before its verdicts are trusted).
# Synthetic logs, no emulator, ~1 s. Lineage: VampireSaved's
# tests/test_compare_flicker.sh, verbatim cases.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
CF() { python3 -m bbh.compare_flicker "$@"; }

mklog() { # mklog <path> <n> [flip_csv]
    python3 - "$@" <<'EOF'
import sys
path, n = sys.argv[1], int(sys.argv[2])
flips = set(int(x) for x in sys.argv[3].split(",")) if len(sys.argv) > 3 else set()
with open(path, "w") as f:
    for i in range(1, n + 1):
        h = f"{i:016x}" if i not in flips else f"{i:016x}DIVERGED"
        f.write(f"{i} {h}\n")
    f.write(f"END {n}\n")
EOF
}

fail=0
ok() { echo "  ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

mklog "$W/base.log" 500
mklog "$W/same.log" 500
out=$(CF "$W/base.log" "$W/same.log") && [ "$out" = "EXACT" ] \
    && ok "identical -> EXACT" || bad "identical logs: got '$out'"

mklog "$W/flick1.log" 500 100
out=$(CF "$W/base.log" "$W/flick1.log") \
    && case "$out" in FLICKER\ 1\ 100) ok "single-frame flicker -> FLICKER";; \
       *) bad "single flicker: got '$out'";; esac \
    || bad "single flicker: exit nonzero ('$out')"

mklog "$W/flick2.log" 500 100,101,300
out=$(CF "$W/base.log" "$W/flick2.log") \
    && case "$out" in FLICKER\ 3\ *) ok "2-frame stretch + isolated -> FLICKER";; \
       *) bad "multi flicker: got '$out'";; esac \
    || bad "multi flicker: exit nonzero ('$out')"

mklog "$W/stretch3.log" 500 100,101,102
out=$(CF "$W/base.log" "$W/stretch3.log") && bad "3-frame stretch accepted: '$out'" \
    || case "$out" in FAIL*stretch*) ok "3-frame stretch -> FAIL";; \
       *) bad "3-frame stretch wrong reason: '$out'";; esac

mklog "$W/close.log" 500 100,140
out=$(CF "$W/base.log" "$W/close.log") && bad "40-frame gap accepted: '$out'" \
    || case "$out" in FAIL*converge*) ok "insufficient re-convergence -> FAIL";; \
       *) bad "close flickers wrong reason: '$out'";; esac

mklog "$W/persist.log" 500 "$(seq 200 500 | tr '\n' ',' | sed 's/,$//')"
out=$(CF "$W/base.log" "$W/persist.log") && bad "persistent divergence accepted" \
    || case "$out" in FAIL*) ok "persistent divergence -> FAIL";; \
       *) bad "persistent wrong reason: '$out'";; esac

# THE TERMINAL-STRETCH EXEMPTION IS GONE (lineage GitHub #52): a divergence
# occupying the final frames is FAIL-SHORT, never FLICKER.
mklog "$W/tail.log" 500 499
out=$(CF "$W/base.log" "$W/tail.log") && bad "end-of-log flicker accepted: '$out'" \
    || case "$out" in FAIL-SHORT*) ok "end-of-log flicker -> FAIL-SHORT";; \
       *) bad "tail flicker wrong reason: '$out'";; esac

# The min-converge BOUNDARY, both sides. Frames run 1..500, so a flip at frame
# f leaves exactly 500-f frame rows after it.
mklog "$W/tail60.log" 500 440          # tail = 60, exactly min-converge
out=$(CF "$W/base.log" "$W/tail60.log") \
    && case "$out" in FLICKER\ 1\ 440) ok "tail == min-converge -> FLICKER";; \
       *) bad "tail==60: got '$out'";; esac \
    || bad "tail==60: exit nonzero ('$out')"

# THE `END` OFF-BY-ONE CONTROL: an implementation measuring to len(log)
# counts the END row and PASSES this case. It must FAIL.
mklog "$W/tail59.log" 500 441          # tail = 59, one short
out=$(CF "$W/base.log" "$W/tail59.log") && bad "tail of 59 accepted (END row counted?): '$out'" \
    || case "$out" in FAIL-SHORT*) ok "tail == min-converge-1 -> FAIL-SHORT (END row not counted)";; \
       *) bad "tail==59 wrong reason: '$out'";; esac

mklog "$W/short.log" 499
out=$(CF "$W/base.log" "$W/short.log") && bad "length mismatch accepted" \
    || case "$out" in FAIL*length*) ok "length mismatch -> FAIL";; \
       *) bad "length wrong reason: '$out'";; esac

printf 'END 0\n' > "$W/empty.log"; cp "$W/empty.log" "$W/empty2.log"
out=$(CF "$W/empty.log" "$W/empty2.log") && bad "two zero-frame logs read EXACT (#54)" \
    || case "$out" in FAIL*no\ frame*) ok "two zero-frame logs -> FAIL (nothing was compared)";; \
       *) bad "empty logs wrong reason: '$out'";; esac

# MUST-FIRE: the consumer's [thresholds] reach the comparator. Under
# flicker_max = 3 the 3-frame stretch is a FLICKER; under the default it is
# not (asserted above).
mkdir -p "$W/c"; printf '[thresholds]\nflicker_max = 3\n' > "$W/c/bbh.toml"
out=$(BBH_CONFIG="$W/c/bbh.toml" CF "$W/base.log" "$W/stretch3.log") \
    && case "$out" in FLICKER\ 3\ *) ok "config flicker_max = 3 makes a 3-frame stretch a FLICKER (the threshold is read from config)";; \
       *) bad "config threshold: got '$out'";; esac \
    || bad "config threshold not applied ('$out')"

[ "$fail" = 0 ] && echo "PASS: flicker comparator verdicts validated" \
    || { echo "FAIL: flicker comparator"; exit 1; }
