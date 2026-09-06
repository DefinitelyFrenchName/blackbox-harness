#!/usr/bin/env python3
"""compare_composite.py — the CONJUNCTION of two already-ratified comparison
classes, for replays whose masked comparison shows both
(docs/method/oracle_classes.md v4).

WHY IT EXISTS. On a build with a hook AND a deliberately altered screen a
replay measures as: the frozen hook-flicker inventory (isolated <=FLICKER_MAX
frame divergences) + ONE bounded, fully re-convergent window per screen
ENTRY. Both halves are ratified classes (flicker, window) but no single
class can express their conjunction, so those replays could not be frozen
without either a new class or a fudge.

This class is STRICTER than either component alone — FOUR clauses:
every divergent run must be accounted for by name, the flicker set must
match exactly, the window list must match exactly, and the run must fully
re-converge. An earlier lineage sentence read "it tolerates nothing that
flicker and window do not each tolerate" — RETRACTED there (GitHub #4):
that property is not satisfiable by any member of the class (flicker's
8-frame cap rejects every window run; window rejects every multi-run log).

Whether the >=RECONVERGE non-propagation window applies BETWEEN flicker
runs, and not merely after the last one, is a consumer POLICY question
(the lineage ruled it INTRA-mechanism, v5): `--min-converge-flicker` exists,
is OFF by default, and no frozen spec opts in.

Usage:
  python3 -m bbh.compare_composite <base.log> <new.log> --flicker 829,2093 \\
      --windows 890-1802 [--reconverge 60]

  --flicker '-'  for none; --windows '-' for none (then use the plain class).
Exit 0 only if every clause holds.
"""

import argparse
import sys

from . import logfmt
from .thresholds import FLICKER_MAX, RECONVERGE, MAX_TOTAL


def parse_windows(spec):
    if spec in ("-", ""):
        return []
    out = []
    for part in spec.split(";"):
        lo, hi = part.split("-")
        out.append((int(lo), int(hi)))
    return out


def parse_flicker(spec):
    if spec in ("-", ""):
        return []
    return [int(x) for x in spec.split(",")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--flicker", required=True,
                    help="frozen flicker frames, comma separated, or '-'")
    ap.add_argument("--windows", required=True,
                    help="frozen windows 'onset-end[;onset-end...]', or '-'")
    ap.add_argument("--reconverge", type=int, default=RECONVERGE,
                    help="minimum identical frames after the last run")
    # The cap applies to the FLICKER INVENTORY ONLY, never to window runs: a
    # window is legitimately hundreds of frames, so capping total divergence
    # would be a category error. (Lineage 14z-90, GitHub #4: measured free
    # across all 121 frozen composite specs, the largest inventory being 3.)
    ap.add_argument("--max-total", type=int, default=MAX_TOTAL,
                    help="maximum frames in the flicker inventory (the v2 "
                         "cap; window runs are exempt by construction)")
    ap.add_argument("--min-converge-flicker", type=int, default=0,
                    help="if >0, require this many identical frames between "
                         "consecutive FLICKER runs (off by default; v5)")
    args = ap.parse_args()

    want_flicker = parse_flicker(args.flicker)
    want_windows = parse_windows(args.windows)
    a, b = logfmt.frames(args.a), logfmt.frames(args.b)
    # Lineage 14z-90 (issue #3): see compare_window — min() certified a
    # truncated run as fully re-convergent over frames it never compared.
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
        print("note: the logs are bit-identical, so the expected shape did "
              "not occur.")
        print("\nFAIL:\n  expected %d flicker frame(s) and %d window(s), found "
              "no divergence at all — this expectation asserts they EXIST, so "
              "identity means something changed"
              % (len(want_flicker), len(want_windows)))
        return 1

    # split into contiguous runs, then classify each by LENGTH only — the
    # frozen lists decide whether the right ones are in the right places.
    runs, start = [], diff[0]
    for i in range(1, len(diff)):
        if diff[i] != diff[i - 1] + 1:
            runs.append((start, diff[i - 1]))
            start = diff[i]
    runs.append((start, diff[-1]))

    got_flicker, got_windows = [], []
    for lo, hi in runs:
        if hi - lo + 1 <= FLICKER_MAX:
            got_flicker.extend(a[i][0] for i in range(lo, hi + 1))
        else:
            got_windows.append((a[lo][0], a[hi][0]))

    tail = n - diff[-1] - 1
    print("divergent frames %d in %d run(s): flicker %s, windows %s, "
          "%d identical after"
          % (len(diff), len(runs),
             ",".join(str(f) for f in got_flicker) or "-",
             ";".join("%d-%d" % w for w in got_windows) or "-", tail))

    if got_flicker != want_flicker:
        errs.append("flicker frames %s, frozen expectation %s"
                    % (got_flicker or "-", want_flicker or "-"))
    if got_windows != want_windows:
        errs.append("windows %s, frozen expectation %s"
                    % (["%d-%d" % w for w in got_windows] or "-",
                       ["%d-%d" % w for w in want_windows] or "-"))
    if len(got_flicker) > args.max_total:
        errs.append("flicker inventory has %d frames, the class caps it at %d "
                    "(§4 v2's max-total; a growing inventory is the standing "
                    "watch's case, not tolerance headroom)"
                    % (len(got_flicker), args.max_total))
    if args.min_converge_flicker > 0:
        fl_runs = [(lo, hi) for lo, hi in runs if hi - lo + 1 <= FLICKER_MAX]
        for (p_lo, p_hi), (n_lo, n_hi) in zip(fl_runs, fl_runs[1:]):
            gap = n_lo - p_hi - 1
            if gap < args.min_converge_flicker:
                errs.append("only %d identical frames between flicker runs "
                            "ending %d and starting %d; --min-converge-flicker "
                            "requires >= %d"
                            % (gap, a[p_hi][0], a[n_lo][0],
                               args.min_converge_flicker))
    if tail < args.reconverge:
        errs.append("only %d identical frames after the last run; the class "
                    "requires >= %d (re-convergence is the point, and its "
                    "absence would mean match state was touched)"
                    % (tail, args.reconverge))

    if errs:
        print("\nFAIL:")
        for e in errs:
            print("  " + e)
        return 1
    print("PASS: frozen flicker inventory + frozen window list, nothing else, "
          "fully re-convergent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
