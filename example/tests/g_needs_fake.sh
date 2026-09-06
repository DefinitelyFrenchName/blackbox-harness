#!/bin/sh
# g_needs_fake.sh — reaches the driver ONLY through a sourced lib, so the
# tier classifier must follow the source line to see it. It is in NEITHER
# plain registry and must not be reported as unregistered. ~1 s.
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO"
. "$REPO/tests/lib/needs_fake.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT INT TERM
fake_replay roms/base replays/01_idle.rpl "$W/out.log" > /dev/null
tail -1 "$W/out.log" | grep -q "^END 420$" || { echo "FAIL: expected END 420, got $(tail -1 "$W/out.log")"; exit 1; }
echo "PASS: 300 scripted frames + 120 tail through the driver = END 420"
