"""check_dumps.py — assert a per-frame RAM dump directory is COMPLETE
(bbh check-dumps).

WHY THIS EXISTS (lineage: VampireSaved 14z-107 (7)). The field comparator
GLOBS a directory: it compares whatever dump files it finds. So a dump that
is never written, or written short, does not make a comparison fail — it
silently changes WHICH frames exist. On an anchor search across two
implementations that is indistinguishable from the two disagreeing about
when the match starts, which is the one verdict the gate exists to give. A
glob is a fine consumer contract only if someone upstream of it asserts the
set. The PRODUCER is the only place that knows what the set should be, so a
driver's caller runs this immediately after collecting, and a gate runs it
on any dump directory it did not produce itself.

Usage:
    python3 -m bbh.check_dumps <dir> --first F --last L [--size N] [--addr A]
    python3 -m bbh.check_dumps <dir> --contiguous [--size N]
        [--config bbh.toml] [--quiet]

  --first/--last   the ABSOLUTE frame range that must be present, complete.
  --size           every dump must be exactly this many bytes (accepts 0x...).
  --addr           the logical address the files must name (0x...).
  --contiguous     no explicit range: assert the frames present form one
                   unbroken run (a directory whose extent is not known in
                   advance).

The file shape is [fields].dump_regex (group 1 the frame, group 2 the hex
address); the advice under a failure is [fields].integrity_hint.
Exit 0 = complete; 1 = a hole, a short file, a stray frame, or no files.
Every printed line is the lineage's.
"""
import argparse
import pathlib
import re
import sys

from . import config as C


def brief(v, n=12):
    return ", ".join(str(x) for x in v[:n]) + (" ..." if len(v) > n else "")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--config", default=None)
    ap.add_argument("--first", type=lambda s: int(s, 0))
    ap.add_argument("--last", type=lambda s: int(s, 0))
    ap.add_argument("--size", type=lambda s: int(s, 0))
    ap.add_argument("--addr", type=lambda s: int(s, 0))
    ap.add_argument("--contiguous", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args(argv)
    if (a.first is None) != (a.last is None):
        ap.error("--first and --last go together")
    if a.first is None and not a.contiguous:
        ap.error("give --first/--last or --contiguous")
    cfg, _root = C.consumer(a.config)
    dump_re = re.compile(C.get(cfg, "fields.dump_regex"))
    hint = list(C.get(cfg, "fields.integrity_hint"))

    d = pathlib.Path(a.dir)
    if not d.is_dir():
        print(f"DUMP INTEGRITY FAILED: {d} is not a directory — the run "
              "produced no dumps at all", file=sys.stderr)
        return 1
    have, addrs = {}, set()
    for p in sorted(d.iterdir()):
        m = dump_re.search(p.name)
        if m:
            have[int(m.group(1))] = p.stat().st_size
            addrs.add(int(m.group(2), 16))
    if not have:
        print(f"DUMP INTEGRITY FAILED: no dump_<frame>_<addr>.bin in {d}",
              file=sys.stderr)
        return 1

    bad = []
    frames = sorted(have)
    if a.first is not None:
        want = range(a.first, a.last + 1)
        missing = [f for f in want if f not in have]
        extra = [f for f in frames if not a.first <= f <= a.last]
        if missing:
            bad.append(f"{len(missing)} MISSING frame(s) of {len(want)}: {brief(missing)}")
        if extra:
            bad.append(f"{len(extra)} dump(s) OUTSIDE [{a.first},{a.last}]: {brief(extra)}")
    else:
        holes = [f for f in range(frames[0], frames[-1] + 1) if f not in have]
        if holes:
            bad.append(f"{len(holes)} HOLE(s) in {frames[0]}..{frames[-1]}: {brief(holes)}")
    if a.size is not None:
        wrong = [f for f in frames if have[f] != a.size]
        if wrong:
            bad.append(f"{len(wrong)} dump(s) not {a.size} bytes: {brief(wrong)}")
    else:
        sizes = sorted(set(have.values()))
        if len(sizes) > 1:
            bad.append(f"dumps have {len(sizes)} different sizes: {brief(sizes)}")
    if a.addr is not None and addrs != {a.addr}:
        bad.append("file names carry address(es) "
                   + ", ".join(f"${x:06X}" for x in sorted(addrs))
                   + f", expected ${a.addr:06X}")

    if bad:
        print(f"DUMP INTEGRITY FAILED for {d}", file=sys.stderr)
        for b in bad:
            print(f"  {b}", file=sys.stderr)
        for line in hint:
            print(f"  {line}", file=sys.stderr)
        return 1
    if not a.quiet:
        span = (f"{a.first}..{a.last}" if a.first is not None
                else f"{frames[0]}..{frames[-1]}")
        size = a.size if a.size is not None else sorted(set(have.values()))[0]
        addr = f" addr ${sorted(addrs)[0]:06X}" if len(addrs) == 1 else ""
        print(f"dump integrity OK: {len(have)} frames {span}, "
              f"{size} bytes each{addr}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
