#!/bin/sh
# g_driver_ok.sh — the INSTRUMENT check: drivers/fake.sh runs one replay to a
# clean END, twice, bit-identical. A prereq-lane gate: if this is red every
# later measurement was taken with a broken instrument. ~1 s.
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO"
BBH_HOME="${BBH_HOME:-$(cd "$REPO/.." && pwd)}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT INT TERM
FAKE_ROMPATH=roms/base "$BBH_HOME/drivers/fake.sh" fake replays/01_idle.rpl "$W/a.log" > /dev/null
FAKE_ROMPATH=roms/base "$BBH_HOME/drivers/fake.sh" fake replays/01_idle.rpl "$W/b.log" > /dev/null
grep -q "^END 420$" "$W/a.log" || { echo "FAIL: no clean END"; exit 1; }
cmp -s "$W/a.log" "$W/b.log" || { echo "FAIL: two runs differ"; exit 1; }
echo "PASS: the fake driver is deterministic to END 420"
