#!/bin/sh
# g_hygiene.sh — the four hygiene checks are GREEN on this consumer: every
# frozen expectation file has a provenance row, every header names the
# default its code uses, no path default has rotted, and the gate index is
# current. This is how a consumer RUNS them: one portable gate, four
# subcommands, any red is this gate's red. ROM-free, ~1 s.
#
# Usage: tests/g_hygiene.sh
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO"
BBH_HOME="${BBH_HOME:-$(cd "$REPO/.." && pwd)}"
rc=0
for c in provenance header-defaults ref-rot "gate-index --check"; do
    if out="$("$BBH_HOME/bin/bbh" $c --config "$REPO/bbh.toml" 2>&1)"; then
        echo "  ok    bbh $c"
    else
        printf '%s\n' "$out" | sed 's/^/        /'
        echo "  FAIL  bbh $c"; rc=1
    fi
done
[ "$rc" = 0 ] && echo "PASS: provenance, header defaults, reference rot and the gate index are current" \
              || { echo "FAIL: see above"; exit 1; }
