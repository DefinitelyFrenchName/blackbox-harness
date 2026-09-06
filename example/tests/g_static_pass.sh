#!/bin/sh
# g_static_pass.sh — a STATIC-tier gate: it needs the reference input named
# by [registries].static_needs_env (FAKE_ROOT) and demands it BEFORE any
# trap, the one shape that exits non-zero on every shell. ROM-free, ~0 s.
set -eu
: "${FAKE_ROOT:?set FAKE_ROOT to the example reference dir}"
[ -d "$FAKE_ROOT" ] || { echo "FAIL: FAKE_ROOT is not a directory"; exit 1; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT INT TERM
echo "PASS: FAKE_ROOT=$FAKE_ROOT"
