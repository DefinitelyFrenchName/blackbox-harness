#!/usr/bin/env python3
"""compare_window.py — the "bounded re-convergent window" comparison class
(docs/method/oracle_classes.md v3).

For a screen the consumer's change deliberately alters. A replay qualifies
ONLY when all four hold, each frozen per replay:

  1. a single CONTIGUOUS divergent run  — not scattered flicker
  2. a fixed ONSET frame                — deterministic, not drifting
  3. full RE-CONVERGENCE                — bit-identical afterwards
  4. the end state UNTOUCHED             — the run ends before it

Deliberately STRICTER than compare_flicker (which tolerates scattered short
divergences) and than the frozen first-divergence constant (which never
re-converges at all). The point is that a screen we changed may differ, and
NOTHING else may. The checker also FAILS a bit-identical pair: this
expectation asserts the divergence EXISTS.

Usage:
  python3 -m bbh.compare_window <a.log> <b.log> --onset N --end N [--reconverge N]

Logs: "<frame> <hash>" per line, END last. Exit 0 only if every clause holds.
"""

import argparse
import sys

from . import logfmt
from .thresholds import RECONVERGE


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--onset", type=int, required=True,
                    help="frozen first divergent frame")
    ap.add_argument("--end", type=int, required=True,
                    help="frozen last divergent frame")
    ap.add_argument("--reconverge", type=int, default=RECONVERGE,
                    help="minimum identical frames required after the window")
    args = ap.parse_args()

    a, b = logfmt.frames(args.a), logfmt.frames(args.b)
    # Lineage 14z-90 (issue #3): min() silently compared a SHORT log against
    # a prefix of the basis, so a run that ended early was certified "fully
    # re-convergent, end state untouched" over frames that were never read.
    if len(a) != len(b):
        print(f"FAIL: length mismatch ({len(a)} vs {len(b)} frames) — a short "
              f"log cannot be compared against a prefix of the basis")
        return 1
    n = len(a)
    if n == 0:
        print("FAIL: empty log(s)")
        return 1
    diff = [i for i in range(n) if a[i] != b[i]]
    errs = []

    if not diff:
        print("note: the logs are bit-identical, so the expected window did "
              "not occur.")
        errs.append("expected a divergent window at frame %d, found none — "
                    "this expectation asserts the divergence EXISTS, so "
                    "identity means something changed" % args.onset)
    else:
        runs = 1
        for i in range(1, len(diff)):
            if diff[i] != diff[i - 1] + 1:
                runs += 1
        first, last = a[diff[0]][0], a[diff[-1]][0]
        tail = n - diff[-1] - 1
        print("divergent frames %d, runs %d, window %d..%d, %d identical after"
              % (len(diff), runs, first, last, tail))
        if runs != 1:
            errs.append("%d contiguous runs; the class permits exactly 1 "
                        "(scattered divergence is flicker, not a window)" % runs)
        if first != args.onset:
            errs.append("onset frame %d, frozen expectation %d"
                        % (first, args.onset))
        if last != args.end:
            errs.append("window ends %d, frozen expectation %d"
                        % (last, args.end))
        if tail < args.reconverge:
            errs.append("only %d identical frames after the window; the class "
                        "requires >= %d (re-convergence is the whole point, "
                        "and its absence would mean match state was touched)"
                        % (tail, args.reconverge))

    if errs:
        print("\nFAIL:")
        for e in errs:
            print("  " + e)
        return 1
    print("PASS: single contiguous window at the frozen onset, fully "
          "re-convergent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
