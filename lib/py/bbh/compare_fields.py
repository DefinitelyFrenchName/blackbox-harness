"""compare_fields.py — compare MAPPED FIELDS between two replay runs from
their per-frame RAM dumps, at SYNC ANCHORS (bbh compare-fields).

THE PROTOCOL (lineage: VampireSaved CLAUDE.md §4, the dual-implementation
agreement). Two implementations of one machine traverse identical states on
slightly DIFFERENT frame indices after boot (measured there, session 2), so
frame-exact whole-RAM equality between them is unachievable and a
fixed-frame comparison is invalid. What is comparable is the MAPPED state —
identities, HP, positions, a timer, a meter — at anchors both sides can
find on their own: the rising edge of a predicate on the dumped RAM
([fields].anchor: `[address, width, value]` clauses, all true), DEBOUNCED
([fields].stable frames: the predicate flickers true transiently during a
round intro, so an edge counts only if it holds). The i-th anchor of side A
is compared to the i-th anchor of side B, at the anchor and at each
--follow offset after it. A bug would still have to manifest identically in
two unrelated implementations to slip through.

The two sides are directories of dump files — `dump_<frame>_<addr>.bin`
([fields].dump_regex; group 1 the frame, group 2 the hex address) — in the
machine's logical byte order, inclusive address ranges, produced by any
driver honouring `DUMPS` (drivers/README.md). Both are directly comparable.

Two modes:
  * --anchor (default), described above.
  * --exact: frame-for-frame comparison of all common dumped frames, for
    SAME-implementation runs, where frame indices align deterministically.

FIELDS come from a TSV ([fields].table): name/base/addr/width[/phase[/note]],
base `abs` or one of [fields].bases (a name -> the address added to addr;
the lineage's p1/p2 player blocks). The TSV may carry its own bases as
`# base <name>=<addr>` header lines, which override the config. Phase:
  stable  — compared at every follow offset (identities, stats)
  settled — compared only at offsets >= --settle ([fields].settle): valid
            once the state has settled (positions during an intro are
            mid-animation and legitimately differ by a few frames of slip)
  phase   — cursor-derived; compared only in --exact mode

Usage:
    python3 -m bbh.compare_fields <dir_a> <dir_b> --fields <tsv>
        [--config bbh.toml] [--exact] [--follow 0,1,5,30] [--settle N]
        [--label-a A] [--label-b B] [--skip-fields f1,f2]
    python3 -m bbh.compare_fields <dir_a> --list-anchors

Exit 0 = all compared fields agree; 3 = mismatch; 1 = usage/data error.
Every printed line is the lineage's.
"""
import argparse
import os
import re
import sys
from pathlib import Path

from . import config as C


class Settings:
    def __init__(self, cfg, root):
        g = lambda k: C.get(cfg, "fields." + k)
        self.root = root
        self.table = g("table")
        self.dump_re = re.compile(g("dump_regex"))
        self.bases = {k: int(v) for k, v in dict(g("bases")).items()}
        self.anchor = [(int(a[0]), int(a[1]), int(a[2])) for a in g("anchor")]
        self.anchor_hint = g("anchor_hint")
        self.stable = int(g("stable"))
        self.settle = int(g("settle"))


def load_side(d, s):
    """dir -> {frame: [(start, bytes), ...]}"""
    frames = {}
    d = Path(d)
    if not d.is_dir():
        sys.exit(f"not a directory: {d}")
    for p in d.iterdir():
        m = s.dump_re.search(p.name)
        if m:
            frames.setdefault(int(m.group(1)), []).append(
                (int(m.group(2), 16), p.read_bytes()))
    if not frames:
        sys.exit(f"no dump_<frame>_<addr>.bin files in {d}")
    return frames


def read_at(ranges, addr, width):
    """Big-endian value at addr from [(start, bytes)] ranges; None if absent."""
    for start, blob in ranges:
        if start <= addr and addr + width <= start + len(blob):
            v = 0
            for i in range(width):
                v = (v << 8) | blob[addr - start + i]
            return v
    return None


def predicate(ranges, s):
    for addr, width, want in s.anchor:
        v = read_at(ranges, addr, width)
        if v is None:
            sys.exit(f"anchor predicate field ${addr:06X} not covered by dumps "
                     f"({s.anchor_hint})")
        if v != want:
            return False
    return True


def find_anchors(frames, s):
    """Debounced rising-edge frames of the anchor predicate. A window whose
    FIRST frame already satisfies the predicate is ambiguous (the real anchor
    may lie before the window) and is NOT counted — widen the window. A
    rising edge counts only if every sampled frame in (edge, edge+STABLE]
    also satisfies the predicate, with coverage at least past edge+STABLE/2."""
    keys = sorted(frames)
    pred = {fr: predicate(frames[fr], s) for fr in keys}
    anchors, prev = [], None
    for i, fr in enumerate(keys):
        cur = pred[fr]
        if prev is None and cur:
            print(f"WARNING: predicate already true at window start (frame {fr}) "
                  "— anchor may precede the dumped window", file=sys.stderr)
        if prev is False and cur:
            later = [k for k in keys[i + 1:] if k <= fr + s.stable]
            if later and later[-1] >= fr + s.stable // 2 and all(pred[k] for k in later):
                anchors.append(fr)
            else:
                print(f"NOTE: transient/uncovered predicate edge at frame {fr} "
                      "ignored (debounce)", file=sys.stderr)
        prev = cur
    return anchors


BASE_HDR = re.compile(r"^#\s*base\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(0[xX][0-9a-fA-F]+|\d+)\s*$")


def parse_fields(path, s):
    bases = dict(s.bases)
    text = Path(path).read_text().splitlines()
    for line in text:                       # `# base p1=0x...` headers override the config
        m = BASE_HDR.match(line)
        if m:
            bases[m.group(1)] = int(m.group(2), 0)
    fields = []
    for lineno, line in enumerate(text, 1):
        line = line.split("#")[0].rstrip()
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 4:
            sys.exit(f"{path}:{lineno}: expected name/base/addr/width[/phase] TSV")
        name, base, addr, width = parts[0], parts[1], int(parts[2], 0), int(parts[3])
        phase = parts[4] if len(parts) > 4 and parts[4] else "stable"
        if base in bases:
            addr += bases[base]
        elif base != "abs":
            sys.exit(f"{path}:{lineno}: base must be abs|{'|'.join(bases)}")
        if width not in (1, 2, 4):
            sys.exit(f"{path}:{lineno}: width must be 1|2|4")
        if phase not in ("stable", "settled", "phase"):
            sys.exit(f"{path}:{lineno}: phase must be stable|settled|phase")
        fields.append((name, addr, width, phase))
    if not fields:
        sys.exit(f"{path}: no fields")
    return fields


def compare_frame(fields, a_ranges, b_ranges, tag, la, lb, skip):
    bad = 0
    for name, addr, width, _phase in fields:
        if name in skip:
            continue
        va = read_at(a_ranges, addr, width)
        vb = read_at(b_ranges, addr, width)
        if va is None or vb is None:
            side = la if va is None else lb
            print(f"MISSING {tag} {name} ${addr:06X}.{width} not dumped on {side}")
            bad += 1
        elif va != vb:
            print(f"MISMATCH {tag} {name} ${addr:06X}.{width} "
                  f"{la}={va:0{width*2}x} {lb}={vb:0{width*2}x}")
            bad += 1
    return bad


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("dir_a")
    ap.add_argument("dir_b", nargs="?")
    ap.add_argument("--config", default=None)
    ap.add_argument("--list-anchors", action="store_true",
                    help="print anchor frames of dir_a and exit")
    ap.add_argument("--fields", help="the fields TSV (default [fields].table under the consumer root)")
    ap.add_argument("--exact", action="store_true",
                    help="frame-exact comparison (same-implementation runs)")
    ap.add_argument("--follow", default="0",
                    help="comma list of frame offsets after each anchor")
    ap.add_argument("--settle", type=int, default=None,
                    help="offset at/after which 'settled' fields are compared ([fields].settle)")
    ap.add_argument("--label-a", default="A")
    ap.add_argument("--label-b", default="B")
    ap.add_argument("--skip-fields", default="",
                    help="comma list of field names to skip")
    args = ap.parse_args(argv)
    cfg, root = C.consumer(args.config)
    s = Settings(cfg, root)
    settle = s.settle if args.settle is None else args.settle

    if args.list_anchors:
        for fr in find_anchors(load_side(args.dir_a, s), s):
            print(fr)
        return 0
    table = args.fields or (os.path.join(root, s.table) if s.table else None)
    if not args.dir_b or not table:
        ap.error("dir_b and --fields are required unless --list-anchors")

    fields = parse_fields(table, s)
    skip = set(x for x in args.skip_fields.split(",") if x)
    a = load_side(args.dir_a, s)
    b = load_side(args.dir_b, s)
    la, lb = args.label_a, args.label_b
    bad = 0

    if args.exact:
        common = sorted(set(a) & set(b))
        if not common:
            sys.exit("no common dumped frames")
        for fr in common:
            bad += compare_frame(fields, a[fr], b[fr], f"frame {fr}", la, lb, skip)
        print(f"exact mode: {len(common)} frames compared")
    else:
        # anchor mode is cross-implementation: cursor-derived ('phase') fields
        # are inherently unlocked across implementations, and 'settled' fields
        # are valid only once the state has settled
        def fields_for(k):
            return [f for f in fields
                    if f[3] == "stable" or (f[3] == "settled" and k >= settle)]
        aa, ab = find_anchors(a, s), find_anchors(b, s)
        print(f"anchors: {la}={aa} {lb}={ab}")
        if not aa or not ab:
            sys.exit(f"no anchor found ({la}: {len(aa)}, {lb}: {len(ab)}) — "
                     "widen the dump window")
        if len(aa) != len(ab):
            print(f"ANCHOR-COUNT MISMATCH {la}={len(aa)} {lb}={len(ab)}")
            bad += 1
        follows = [int(x) for x in args.follow.split(",")]
        for i, (fa, fb) in enumerate(zip(aa, ab)):
            for k in follows:
                if fa + k in a and fb + k in b:
                    bad += compare_frame(fields_for(k), a[fa + k], b[fb + k],
                                         f"anchor{i}+{k} ({la}:{fa + k}/{lb}:{fb + k})",
                                         la, lb, skip)
                else:
                    print(f"MISSING anchor{i}+{k}: frame not dumped "
                          f"({la}:{fa + k} in={fa + k in a}, {lb}:{fb + k} in={fb + k in b})")
                    bad += 1

    if bad:
        print(f"FAIL: {bad} disagreement(s)")
        sys.exit(3)
    print("OK: all compared fields agree")
    return 0


if __name__ == "__main__":
    sys.exit(main())
