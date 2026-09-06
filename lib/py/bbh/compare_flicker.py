#!/usr/bin/env python3
"""compare_flicker.py — checksum-log comparison with bounded flicker tolerance
(the FLICKER-TOLERATED class; docs/method/oracle_classes.md v2).

Cycle-skew from engine hooks can capture a state transition one frame apart
at input-accept/spawn boundaries, producing an ISOLATED divergent frame (or
two) after which the logs re-converge exactly. A real behaviour divergence
in a deterministic engine propagates and never re-converges to bit-identical
whole-state, so bounded re-converging flickers are a timing-phase signature,
not a bug signature. (Lineage: measured in VampireSaved session 7 — single
frames, full re-convergence, the live bytes transition-latched state.)

Verdicts (stdout, exit 0/1):
  EXACT                 logs identical
  FLICKER <n> <frames>  divergent stretches within tolerance, else identical
  FAIL <reason>         tolerance exceeded / persistent divergence / length
  FAIL-SHORT <reason>   the log ENDS before re-convergence can be proved --
                        a replay-length problem, not a behavioural divergence,
                        and a different bug report (lineage GitHub #52)

Tolerance (from bbh.thresholds, deliberately tight):
  --max-stretch  FLICKER_MAX   max consecutive divergent frames per stretch
  --min-converge RECONVERGE    frames that must match after a stretch (NO
                               end-of-log exemption — see #52 below)
  --max-total    MAX_TOTAL     max divergent frames overall
"""

import argparse
import sys

from . import logfmt
from .thresholds import FLICKER_MAX, RECONVERGE, MAX_TOTAL


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log_a")
    ap.add_argument("log_b")
    ap.add_argument("--max-stretch", type=int, default=FLICKER_MAX)
    ap.add_argument("--min-converge", type=int, default=RECONVERGE)
    ap.add_argument("--max-total", type=int, default=MAX_TOTAL)
    args = ap.parse_args()

    a = logfmt.lines(args.log_a)
    b = logfmt.lines(args.log_b)
    if len(a) != len(b):
        print(f"FAIL length mismatch ({len(a)} vs {len(b)} lines)")
        return 1

    # Lineage 14z-90 (GitHub #54): two zero-frame logs are equal-length and
    # produce no differing rows, so this printed EXACT and returned 0 having
    # compared NOTHING.
    if not any(logfmt.is_frame_row(l) for l in a):
        print("FAIL no frame rows compared — the log has no data")
        return 1

    bad = [i for i, (x, y) in enumerate(zip(a, b)) if x != y]
    if not bad:
        print("EXACT")
        return 0

    stretches = []
    for i in bad:
        if stretches and i == stretches[-1][1] + 1:
            stretches[-1][1] = i
        else:
            stretches.append([i, i])

    frames = [a[i].split()[0] for i in bad if a[i].split()]
    if len(bad) > args.max_total:
        print(f"FAIL {len(bad)} divergent frames > max-total {args.max_total} "
              f"(first at frame {frames[0]})")
        return 1
    for s, e in stretches:
        if e - s + 1 > args.max_stretch:
            print(f"FAIL stretch of {e - s + 1} frames at frame "
                  f"{a[s].split()[0]} > max-stretch {args.max_stretch}")
            return 1
    # Lineage 14z-95 (GitHub #52): the LAST stretch used to be exempt from
    # the re-convergence requirement entirely — a PERMANENT divergence whose
    # replay simply ends before it can propagate was indistinguishable from a
    # flicker. Two corrections:
    #   - the tail is measured to the last FRAME row, not to len(a); the
    #     trailing `END <n>` row would otherwise count as one converged frame.
    #   - a short tail is FAIL-SHORT, a distinct verdict: "the replay is too
    #     short to prove re-convergence" and "the build diverged" are
    #     different findings and want different fixes.
    end_of_frames = max(i for i, l in enumerate(a) if logfmt.is_frame_row(l)) + 1
    for (s, e), nxt in zip(stretches, stretches[1:] + [[end_of_frames] * 2]):
        conv = nxt[0] - e - 1
        if conv < args.min_converge:
            if nxt[0] == end_of_frames:
                print(f"FAIL-SHORT only {conv} frames of log after frame "
                      f"{a[e].split()[0]} < min-converge "
                      f"{args.min_converge} — the log ends too soon to prove "
                      f"re-convergence")
            else:
                print(f"FAIL only {conv} converged frames after frame "
                      f"{a[e].split()[0]} < min-converge {args.min_converge}")
            return 1

    print(f"FLICKER {len(bad)} {','.join(frames)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
