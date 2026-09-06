"""provenance.py — EVERY FROZEN EXPECTATION FILE SAYS WHERE ITS NUMBERS CAME
FROM (bbh provenance).

    python3 -m bbh.provenance [--config bbh.toml] [--root DIR] [--page FILE]

WHY (lineage: VampireSaved 14z-128). The rule for adjudicating a red gate:
"to know if we should fix the gate or what it caught, we must use data we
can trust, and that means measuring or relying on data that is known to be
true for it was vetted by measurements." A RED GATE IS A QUESTION, and its
first question is which side rests on a measurement. Measured there: 15 of
45 frozen expectation files declared their provenance nowhere a triage
would look — the FILE is what a triage opens.

THE REGISTER ([provenance].page) is the answer, kept beside the files: one
table row per file, the first cell its `backticked` name, and a `rests on`
cell naming one of a CLOSED vocabulary of evidence classes
([provenance].evidence_classes — the lineage's: in-emulator (reference),
in-emulator (ours), in-emulator (reference + ours), derived, static,
hash-lock, registry; `hash-lock` locks CURRENCY, never correctness). This
tool keeps it complete BOTH WAYS — a file with no row, or a row naming a
file that is gone, is the drift that makes the page worth less than nothing
(a register that is confidently incomplete is read as exhaustive) — and
refuses a row whose class is not in the vocabulary.

SCOPE: the FILES directly under each [provenance].scope dir, named with
that dir's row prefix (the lineage: `tests/expected/` bare, `tests/expect/`
as `expect/<name>`); [provenance].exclude names the files there that are
not expectations (the page itself). Directories are out of scope: in the
lineage they are per-build expectation sets whose provenance is the
registry plus a freeze tag, and two checks on one claim is one too many.

Exit 1 when either section fails. The lines are the lineage gate's own.
"""
import argparse
import os
import re
import sys

from . import config as C


class Settings:
    def __init__(self, cfg):
        g = lambda k: C.get(cfg, "provenance." + k)
        self.page = g("page")
        self.scope = [(d[0], d[1]) for d in g("scope")]
        self.exclude = set(g("exclude"))
        self.classes = tuple(g("evidence_classes"))
        self.column = int(g("rests_on_column"))


ROW = re.compile(r"^\|\s*`([^`]+)`\s*\|", re.M)


def rows_of(page_text):
    return set(ROW.findall(page_text))


def files_of(root, s):
    files = set()
    for d, prefix in s.scope:
        full = os.path.join(root, d)
        if not os.path.isdir(full):
            continue
        for f in os.listdir(full):
            if os.path.isfile(os.path.join(full, f)) and not f.startswith(".") and f not in s.exclude:
                files.add(prefix + f)
    return files


def check_complete(root, s, page_text, out=print):
    rows = rows_of(page_text)
    files = files_of(root, s)
    missing = sorted(files - rows)
    dead = sorted(r for r in rows if r not in files)
    ok = True
    if missing:
        ok = False
        out(f"  FAIL: {len(missing)} expectation file(s) with NO provenance row:")
        for m in missing:
            out(f"      {m}")
        out(f"      Add a row to {s.page} saying what the")
        out("      numbers describe, what evidence they rest on, and how to")
        out("      re-freeze them. If you cannot say, that is the finding.")
    if dead:
        ok = False
        out(f"  FAIL: {len(dead)} provenance row(s) naming a file that is gone:")
        for d in dead:
            out(f"      {d}")
    if ok:
        out(f"  ok: {len(files)} expectation files, {len(rows)} rows, complete both ways")
    return ok


def check_classes(s, page_text, out=print):
    cell = r"([^|]*)\|" * (s.column - 1)
    rx = re.compile(r"^\|\s*`([^`]+)`\s*\|" + cell)
    bad = []
    for line in page_text.splitlines():
        m = rx.match(line)
        if not m:
            continue
        rests = m.group(s.column)
        if not any(c in rests for c in s.classes):
            bad.append((m.group(1), rests.strip()[:50]))
    if bad:
        out(f"  FAIL: {len(bad)} row(s) whose 'rests on' names no defined class:")
        for f, r in bad:
            out(f"      {f}: {r!r}")
        out(f"      Defined classes: {', '.join(s.classes)}")
        return False
    out("  ok: every row's evidence class is one the page defines")
    return True


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=None)
    ap.add_argument("--root", default=None)
    ap.add_argument("--page", default=None, help="the register (default [provenance].page under the root)")
    a = ap.parse_args(argv)
    cfg, root = C.consumer(a.config, a.root)
    s = Settings(cfg)
    page = a.page or os.path.join(root, s.page)
    if not os.path.isfile(page):
        print(f"FAIL: {s.page} is missing")
        return 1
    text = open(page, encoding="utf-8").read()
    rc = 0
    print("== 1. every expectation file has a row, every row an existing file")
    if not check_complete(root, s, text):
        rc = 1
    print("== 2. every row names an evidence class the page defines")
    if not check_classes(s, text):
        rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
