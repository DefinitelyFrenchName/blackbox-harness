#!/usr/bin/env python3
"""check_diverge.py — verify a checksum log diverges from a frozen base log
at EXACTLY the expected frame (the suite's .diverge expectation kind; the
FROZEN FIRST-DIVERGENCE CONSTANT class).

A .diverge expectation ("<baseset> <frame>") encodes: this replay's log must
be line-identical to <expected_root>/<baseset>/logs/<name>.log through
frame-1, and its first divergence must be exactly at <frame>. Divergence
earlier, later, or absent is a FAIL — an invariant is never weakened, only
precisely specified. THE SPEC FILE'S NAME IS LOAD-BEARING: the base log is
derived from the spec's STEM.

Usage:
    python3 -m bbh.check_diverge <log> <spec.diverge> <expected_root>

Exit 0 with "PASS ..." on stdout, 1 with "FAIL ..."/"NO-BASE-LOG ...".
"""

import sys
from pathlib import Path

from . import logfmt


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    log, spec, exproot = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    baseset, want = spec.read_text().split()
    want = int(want)
    base = exproot / baseset / "logs" / (spec.stem + ".log")
    if not base.is_file():
        print(f"NO-BASE-LOG {base}")
        sys.exit(1)
    a = logfmt.frame_lines(base)
    b = logfmt.frame_lines(log)
    # Lineage 14z-90 (issue #3): a short log compared against a prefix of the
    # basis reports "no divergence" for a run that simply stopped.
    if len(a) != len(b):
        print(f"FAIL length mismatch ({len(a)} vs {len(b)} frames vs {baseset})")
        sys.exit(1)
    div = None
    for i in range(min(len(a), len(b))):
        if a[i] != b[i]:
            div = int(a[i].split()[0])
            break
    if div == want:
        print(f"PASS (diverges from {baseset} at exactly {want})")
        sys.exit(0)
    print(f"FAIL first divergence at {div} (expected exactly {want} vs {baseset})")
    sys.exit(1)


if __name__ == "__main__":
    main()
