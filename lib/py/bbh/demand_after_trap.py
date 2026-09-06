"""demand_after_trap.py — no gate may carry a `${VAR:?msg}` DEMAND after its
EXIT trap.

    python3 -m bbh.demand_after_trap <gates-dir> [--lib <subdir>] [--skip <name>]…

WHY. On macOS bash 3.2 — /bin/sh AND /bin/bash — a parameter-expansion abort
(`${VAR:?}` on an unset VAR) exits the shell with status 0 once an EXIT trap
is armed; without the trap it exits 1, and a trap written to preserve `$?`
still returns 0 because `$?` is already 0 when the trap runs. VampireSaved's
M16 release run recorded a 65-minute simulator gate as `PASS 0s`: it died at
a demand eight lines after `trap 'rm -rf "$W"' EXIT`, and the runner's
exit-status-first classifier read the 0. The classifier now also fails an
exit-0 log carrying the shell's own `<script>.sh: line N: NAME: message`
(lib/sh/classify.sh); this scanner removes the CAUSE: once a trap is armed a
demand is written as an explicit test —
    [ -n "${X:-}" ] || { echo "FAIL: set X"; exit 1; }
Demands BEFORE the trap (the usual top-of-file `${ROMDIR:?set ROMDIR}`) exit
1 correctly and are allowed.

SCOPE: every *.sh in the gates dir and in its lib subdir. A `${VAR:?…}`
inside a heredoc that writes a STUB SCRIPT runs in the stub's own shell (no
trap) and is allowed — heredoc bodies are skipped. Prints `file:line: text`
per hit; exit 1 if any.
"""
import pathlib
import re
import sys

TRAP = re.compile(r"(^|[;&|]\s*)trap\b.*\bEXIT\b")
DEMAND = re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*:\?")
HEREDOC = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?")


def scan(root, lib="lib", skip=()):
    root = pathlib.Path(root)
    files = sorted(list(root.glob("*.sh")) + list((root / lib).glob("*.sh")))
    hits = []
    for f in files:
        if f.name in skip:
            continue
        trap_line = None
        heredoc_end = None
        for n, line in enumerate(f.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if heredoc_end is not None:
                if line.strip() == heredoc_end:
                    heredoc_end = None
                continue
            m = HEREDOC.search(line)
            if m and not line.lstrip().startswith("#"):
                heredoc_end = m.group(1)
            if trap_line is None and TRAP.search(line) and not line.lstrip().startswith("#"):
                trap_line = n
                continue
            if trap_line is not None and DEMAND.search(line) and not line.lstrip().startswith("#"):
                hits.append(f"{f.relative_to(root)}:{n}: {line.strip()[:100]}")
    return hits


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    root = argv[0]
    lib = "lib"
    skip = []
    i = 1
    while i < len(argv):
        if argv[i] == "--lib" and i + 1 < len(argv):
            lib = argv[i + 1]
            i += 2
        elif argv[i] == "--skip" and i + 1 < len(argv):
            skip.append(argv[i + 1])
            i += 2
        else:
            print(f"bbh demand_after_trap: bad argument {argv[i]!r}", file=sys.stderr)
            return 2
    hits = scan(root, lib, skip)
    for h in hits:
        print(h)
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
