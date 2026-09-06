#!/bin/sh
# g_needs_fake.sh — reaches the driver ONLY through a sourced lib, so the
# tier classifier must follow the source line to see it. It is in NEITHER
# plain registry and must not be reported as unregistered. ~0 s.
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO"
. "$REPO/tests/lib/needs_fake.sh"
fake_frames 3
echo "PASS: 3 frames through the driver"
