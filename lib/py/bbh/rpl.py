"""rpl.py — the `.rpl` replay grammar, parsed in one place (python side).

    <frame>[-<endframe>] <who>=<tokens> [<who>=<tokens> ...]
    <frame> wait

`#` starts a comment; blank lines are ignored. `who` is a SIDE (the
lineage's p1 / p2 / sys); its tokens are concatenated and split by the
side's TOKEN WIDTH (one character for a player, two for `sys`). Lines OR
together: a token is held for every frame its ranges cover. Frame 1 is the
first emulated frame. `wait` holds nothing and only extends the replay.

The token → port mapping is the MACHINE PROFILE's (H6, one Lua table per
board); this module knows only the grammar and a profile's token
vocabulary, so it can lint a replay and drive a fake machine. Slice H6 adds
`lua/mame/rpl_parse.lua`, the same grammar for the MAME side, and a selftest
that the two agree on every replay when a standalone `lua` is present.

    python3 -m bbh.rpl <replay.rpl> [--sides p1:1:UDLR123456 ...]

prints `ok: <n> lines, last frame <m>, <k> held frames` or the error with
its line number (exit 1). Error texts follow the lineage's replay.lua
assertions so a replay rejected by one side is rejected by the other for
the same reason.
"""
import re
import sys

# The lineage's vocabulary, as the default profile for the lint and the fake
# machine: side -> (token width, the token set).
DEFAULT_SIDES = {
    "p1": (1, set("UDLR123456")),
    "p2": (1, set("UDLR123456")),
    "sys": (2, {"S1", "S2", "C1", "C2", "SV", "TS"}),
}


class RplError(Exception):
    pass


def split_tokens(width, s):
    return [s[i:i + width] for i in range(0, len(s), width)]


def parse(path, sides=None):
    """-> (held, last_frame): held[frame] = [(side, token), ...] in file
    order (duplicates kept, as the lineage keeps them; harmless)."""
    sides = sides or DEFAULT_SIDES
    held = {}
    last = 0
    with open(path) as fh:
        for lineno, line in enumerate(fh, 1):
            body = re.sub(r"#.*", "", line).strip()
            if not body:
                continue
            m = re.match(r"^(\S+)\s+(.*)$", body)
            if not m:
                raise RplError(f"{path}:{lineno}: expected '<frame>[-<end>] who=tokens'")
            rng, rest = m.group(1), m.group(2)
            r = re.match(r"^(\d+)-(\d+)$", rng)
            if r:
                a, b = int(r.group(1)), int(r.group(2))
            elif re.match(r"^\d+$", rng):
                a = b = int(rng)
            else:
                raise RplError(f"{path}:{lineno}: bad frame range '{rng}'")
            if not (a >= 1 and b >= a):
                raise RplError(f"{path}:{lineno}: bad range")
            for spec in rest.split():
                if spec == "wait":
                    continue
                s = re.match(r"^([A-Za-z]+\d?)=(\S+)$", spec)
                who = s.group(1) if s else None
                if who not in sides:
                    raise RplError(f"{path}:{lineno}: unknown side '{who}'")
                width, vocab = sides[who]
                for t in split_tokens(width, s.group(2)):
                    if t not in vocab:
                        raise RplError(f"{path}:{lineno}: unknown token '{t}' for {who}")
                    for fr in range(a, b + 1):
                        held.setdefault(fr, []).append((who, t))
            if b > last:
                last = b
    return held, last


def _sides_arg(specs):
    sides = {}
    for spec in specs:
        name, width, vocab = spec.split(":", 2)
        w = int(width)
        sides[name] = (w, set(split_tokens(w, vocab)))
    return sides


def main(argv):
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("replay")
    ap.add_argument("--sides", nargs="*", default=None,
                    help="side:width:tokens (default: the lineage's p1/p2/sys)")
    a = ap.parse_args(argv)
    sides = _sides_arg(a.sides) if a.sides else None
    try:
        held, last = parse(a.replay, sides)
    except RplError as e:
        print(f"FAIL: {e}")
        return 1
    n = sum(1 for l in open(a.replay) if re.sub(r"#.*", "", l).strip())
    print(f"ok: {n} lines, last frame {last}, {len(held)} held frames")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
