#!/bin/sh
# g_pass.sh — the plainest gate: one assertion, one verdict line, exit 0.
# ROM-free, ~0 s.
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO"
[ -f tests/ci_portable.txt ] || { echo "FAIL: no registry"; exit 1; }
echo "PASS: the registry exists"
