"""header_defaults.py — A GATE'S HEADER MUST STATE THE DEFAULT THE CODE
ACTUALLY USES (bbh header-defaults).

    python3 -m bbh.header_defaults [--config bbh.toml] [--root DIR]   report every mismatch
    python3 -m bbh.header_defaults ... --fix                          rewrite the header lines

WHY THIS EXISTS (lineage: VampireSaved 14z-128). Its reference-rot gate
(bbh ref-rot) closed the class where a gate's CODE default points at a
build dir that has been pruned; the freeze ritual's re-point sweep kept
those honest. The HEADERS were another matter: 37 lines across 37 gates
told the reader to run

    ROMDIR=... [BUILD=build/m3b_merged11] tests/audit_don_grab_pose.sh

while the code said `BUILD="${BUILD:-build/m3b_merged23}"`. The dir named
in the header had been pruned three freezes earlier. Nothing breaks — the
code default is right — but a gate's WHY lives in its header, and the gate
index is generated FROM those headers: a header naming a dead dir is a
documented instruction that cannot be followed, in the one place a reader
looks before running the gate.

THE RULE, deliberately narrow so it is mechanical and cannot be argued
with: every path token ([header_defaults].token_regex) on a header line
presenting itself as an INVOCATION or a DEFAULT (claim_line_regex: a
`Usage:` line, or a line saying "default(s)") must be one of the defaults
the code actually sets. Any other mention is left alone: a header may cite
the build a measurement was taken on, and that build being pruned does not
make the citation wrong. That distinction is the whole reason this is not
simply "no dead dirs in comments".

CODE DEFAULTS are the `${VAR:-<token>}` and `${1:-<token>}` forms, with or
without the root prefix (root_prefix_regex), read from non-comment lines.

TWO EXEMPTIONS, each paid for on the lineage's first sweep: a BACKTICKED
token is code being DISCUSSED (its rot gate quotes `${1:-build/pyron22}`
while explaining the class), and a block opened by verbatim_regex
(`(verbatim; …)`) is an ARCHIVE until the next bare `#` line — rewriting a
default inside one falsifies the quote. A token followed by `<` is a
TEMPLATE (`build/emu_sweep_<stamp>`), not a dir.

WHAT IT DOES NOT CHECK: whether the code default itself still exists —
that is bbh ref-rot's job, and duplicating it here would put two checks on
one claim.
"""
import argparse
import re
import sys
from pathlib import Path

from . import config as C
from . import gate_header as GH

BACKTICKED = re.compile(r"`[^`]*`")


class Settings:
    def __init__(self, cfg):
        g = lambda k: C.get(cfg, "header_defaults." + k)
        self.token = g("token_regex")
        self.dir_re = re.compile(self.token)
        self.claim_re = re.compile(g("claim_line_regex"), re.I)
        self.verbatim_re = re.compile(g("verbatim_regex"), re.I)
        self.code_default_re = re.compile(
            r'\$\{(?:\d|[A-Za-z_][A-Za-z0-9_]*):-\s*"?' + g("root_prefix_regex") + "(" + self.token + ")")
        self.gates_dir = C.get(cfg, "project.gates_dir")
        self.gate_glob = C.get(cfg, "project.gate_glob")


def code_defaults(path, s):
    body = "\n".join(l for l in path.read_text(encoding="utf-8", errors="replace").splitlines()
                     if not l.lstrip().startswith("#"))
    return set(s.code_default_re.findall(body))


def audit(root, s):
    problems = []
    for p in sorted((root / s.gates_dir).glob(s.gate_glob)):
        defaults = code_defaults(p, s)
        in_verbatim = False
        for i, line in enumerate(GH.header_lines(p)):
            if s.verbatim_re.search(line):
                in_verbatim = True
            elif line.strip() == "#":
                in_verbatim = False
            if in_verbatim:
                continue
            if not s.claim_re.search(line):
                continue
            quoted = [(m.start(), m.end()) for m in BACKTICKED.finditer(line)]
            for m in s.dir_re.finditer(line):
                if any(a <= m.start() < b for a, b in quoted):
                    continue
                # a TEMPLATE, not a dir: `build/emu_sweep_<stamp>`. The test
                # cannot live in the regex — `[A-Za-z0-9_]+(?!<)` backtracks
                # off the trailing `_` and matches anyway.
                if line[m.end():m.end() + 1] == "<":
                    continue
                if m.group(0) not in defaults:
                    problems.append((p, i, m.group(0), line.rstrip(), sorted(defaults)))
    return problems


def fix(problems):
    """Rewrite each offending line, substituting the code's own default.

    Only acts when the code has EXACTLY ONE default: with several, which one a
    given header line means is a judgement, and a tool that guesses at that
    writes a confident wrong sentence into the place a reader trusts.
    """
    by_file = {}
    for p, i, dead, line, defaults in problems:
        by_file.setdefault(p, []).append((i, dead, defaults))
    fixed = skipped = 0
    for p, items in by_file.items():
        lines = p.read_text(encoding="utf-8").splitlines(keepends=True)
        touched = False
        for i, dead, defaults in items:
            if len(defaults) != 1:
                skipped += 1
                continue
            lines[i + 1] = lines[i + 1].replace(dead, defaults[0])
            fixed += 1
            touched = True
        if touched:                      # never rewrite a file we did not change
            p.write_text("".join(lines), encoding="utf-8")
    return fixed, skipped


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=None)
    ap.add_argument("--root", default=None)
    ap.add_argument("--fix", action="store_true")
    a = ap.parse_args(argv)
    cfg, root = C.consumer(a.config, a.root)
    root = Path(root)
    s = Settings(cfg)
    problems = audit(root, s)
    if a.fix:
        n, skipped = fix(problems)
        print(f"rewrote {n} header line(s); {skipped} left for a human "
              f"(the gate has more than one code default)")
        problems = audit(root, s)
    if not problems:
        print("ok    every header Usage/default line names a current code default")
        return 0
    print(f"{len(problems)} header line(s) name a build dir the code does not default to:")
    seen = set()
    for p, i, dead, line, defaults in problems:
        rel = p.relative_to(root)
        if rel not in seen:
            print(f"\n  {rel}   code defaults: {', '.join(defaults) or '(none)'}")
            seen.add(rel)
        print(f"      header line {i + 2}: {line.strip()[:96]}")
        print(f"      names {dead}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
