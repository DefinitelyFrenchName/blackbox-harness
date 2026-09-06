#!/bin/sh
# g_skip.sh — the SKIP contract: a missing prerequisite prints `SKIP: reason`
# on its own line and exits 0. The runner counts it SEPARATELY from PASS.
# ROM-free, ~0 s.
set -eu
[ -n "${NEVER_SET_IN_THE_EXAMPLE:-}" ] || { echo "SKIP: NEVER_SET_IN_THE_EXAMPLE is unset"; exit 0; }
echo "PASS: unreachable in the example"
