#!/bin/sh
# g_segv_prose.sh — the BENIGN look-alike of a shell error: a driver
# segfaulting at teardown AFTER the summary line. Digits sit where a shell
# error carries a NAME, so the classifier leaves it PASS. ROM-free, ~0 s.
set -eu
echo "PASS: the summary line"
echo "tests/g_segv_prose.sh: line 64:  2444 Segmentation fault: 11  REPLAY=x"
exit 0
