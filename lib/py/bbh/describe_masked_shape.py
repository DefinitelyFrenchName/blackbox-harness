#!/usr/bin/env python3
"""describe_masked_shape.py — the measured shape of a masked divergence, and a
PROPOSED expectation line in the ratified vocabulary.

Thresholds come from bbh.thresholds — the SINGLE declaration shared with
compare_composite / compare_flicker / compare_window. Frames are read from
the log's FIRST COLUMN, which is compare_window's convention (onset/end are
frame numbers, end = last divergent frame, INCLUSIVE), so a proposed line
drops into a .masked spec verbatim.

This proposes; it never ratifies. A shape that does not re-converge is NOT
expressible in the vocabulary and is reported as such — that signature (a
legacy pairing losing a main-loop iteration, in the lineage) must be
root-caused, never absorbed into a widened tolerance.

Usage: python3 -m bbh.describe_masked_shape <base.log> <new.log> [--basis <set>/<basis>]
"""

import argparse
import sys

from . import logfmt
from .thresholds import FLICKER_MAX, RECONVERGE


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base")
    ap.add_argument("new")
    ap.add_argument("--basis", default="base/masked",
                    help="basis path fragment written into the proposed line")
    args = ap.parse_args()

    a, b = logfmt.frames(args.base), logfmt.frames(args.new)
    n = min(len(a), len(b))
    note = "" if len(a) == len(b) else " [LENGTH MISMATCH %d vs %d]" % (len(a), len(b))
    d = [i for i in range(n) if a[i] != b[i]]
    if not d:
        print("shape: bit-identical%s" % note)
        print("proposed: exact %s -" % args.basis)
        return 0

    runs, s, p = [], d[0], d[0]
    for i in d[1:]:
        if i != p + 1:
            runs.append((s, p))
            s = i
        p = i
    runs.append((s, p))
    tail = n - 1 - runs[-1][1]
    fr = lambda i: a[i][0]                       # index -> frame number
    flick = [r for r in runs if r[1] - r[0] + 1 <= FLICKER_MAX]
    wins = [r for r in runs if r[1] - r[0] + 1 > FLICKER_MAX]
    print("shape: %d/%d frames differ in %d run(s), first at frame %d, last ends "
          "frame %d, then %d identical%s" % (len(d), n, len(runs), fr(runs[0][0]),
                                             fr(runs[-1][1]), tail, note))
    print("runs: " + " ".join("%d-%d" % (fr(x), fr(y)) for x, y in runs))
    # Lineage 14z-90 (GitHub #53): was `tail <= RECONVERGE`, so the PROPOSER
    # refused a tail of exactly RECONVERGE while the ENFORCER accepts it.
    if tail < RECONVERGE:
        print("proposed: NONE — does not re-converge (>=%d identical tail "
              "required); this is not expressible in the ratified vocabulary "
              "and must be root-caused" % RECONVERGE)
    elif not wins:
        print("proposed: flicker %s %d %s"
              % (args.basis, len(d), ",".join(str(fr(i)) for i in d)))
    elif not flick:
        print("proposed: window %s %d %d" % (args.basis, fr(wins[0][0]), fr(wins[0][1]))
              if len(wins) == 1 else
              "proposed: composite %s - " % args.basis +
              ";".join("%d-%d" % (fr(x), fr(y)) for x, y in wins))
    else:
        print("proposed: composite %s %s %s"
              % (args.basis,
                 ",".join(str(fr(i)) for r in flick for i in range(r[0], r[1] + 1)),
                 ";".join("%d-%d" % (fr(x), fr(y)) for x, y in wins)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
