"""logfmt.py — the checksum-log grammar, parsed in ONE place.

A log is one `<frame> <hash>` line per frame and an `END <n>` line last —
what a replay driver writes (drivers/README.md). Two readers, because the
comparators need two views:

    frames(path)  -> [(frame:int, hash:str), ...]   END and blank lines dropped
    lines(path)   -> the raw lines (END included), for the tools whose
                     verdict text counts rows the way the lineage did

Lineage: the same `load()` was copied into compare_window.py,
compare_composite.py and describe_masked_shape.py, and compare_flicker.py /
check_diverge.py each carried a raw-line variant. One module, so the grammar
cannot drift between the tools that share it.
"""


def frames(path):
    out = []
    with open(path) as fh:
        for line in fh:
            f = line.split()
            if not f or f[0] == "END":
                continue
            if len(f) >= 2:
                out.append((int(f[0]), f[1]))
    return out


def lines(path):
    with open(path) as fh:
        return fh.read().splitlines()


def frame_lines(path):
    """Raw lines with END lines dropped (check_diverge's view)."""
    return [l for l in lines(path) if not l.startswith("END")]


def is_frame_row(line):
    f = line.split()
    return bool(f) and f[0].isdigit()
