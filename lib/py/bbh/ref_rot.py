"""ref_rot.py — A HARD-CODED PATH DEFAULT MUST NOT HAVE ROTTED (bbh ref-rot).

    python3 -m bbh.ref_rot [--config bbh.toml] [--root DIR]

THE CLASS (lineage: VampireSaved 14z-94, GitHub #94 there). Build dirs are
UNTRACKED by design, so every `${1:-build/pyron22}` default is a pointer
with a shelf life. Four instances surfaced in one session, each found the
same way: somebody ran the audit months later and it died before measuring
anything. The individual fix is one line each; the class is this check:
nothing told anyone a reference had rotted until they ran the audit, and
on-demand audits go months between runs.

THE SIGNATURE IS PRECISE, and it is the consumer's: [ref_rot].stale_marker
= [member prefix, required member, reason] — an image carrying any PREFIX
member but not REQUIRED is too old to carry what the reader needs (the
lineage: a pre-WIDE-v1.1 zip has `vsw.*` and no `vsw.z01`). A consumer with
another rule gives [ref_rot].predicate, a command: `$1` = the image, print
its one-line description, exit 0 live / 1 rotted.

AND IT MUST CONSIDER WHAT THE SCRIPT READS. A default is checked only when
the script dereferences it as an IMAGE — `$VAR<rompath_suffix>` appears in
the body, or the default itself ends in the suffix. A build referenced for
its extract/ or patch/ dir is a different contract; flagging it would be a
false positive, and a check that cries wolf about a working reference is
one people switch off.

ABSENT IS NOT ROTTED. On a clean checkout every build dir is missing; that
is reported, never failed. A dir that exists with no image dir, or an image
dir with no image, is "unbuilt here" too. ROTTED means an image that exists
and is too old.

THE THREE DEFAULT IDIOMS, every one a hole closed after it hid a reference:
    VAR="${1:-<token>}"               positional
    VAR="${VAR:-<token>}"             named env (eleven references, unseen at first)
    VAR=<token>                       plain, no override at all (seven)
    VAR="${1:-$REPO/<token>/rompath}" root-prefixed, and usually the image
                                      dir itself — this one was hiding a real rot

CURRENCY, which rot cannot see — REPORTED, NEVER FAILED. Every reference
reports "ok" the moment it LOADS, and a superseded build loads perfectly:
that is how the lineage's battery judged today's build against a set five
generations back and was green about it for weeks. Two mechanical signals,
no external truth needed: (1) fingerprint the referenced image, look its
set up in the suite registry, compare against the newest generation of its
family ([ref_rot].family_regex: two groups, family and generation); (2)
several gates naming DIFFERENT dirs of one family — at most one can be
current. A superseded reference is often CORRECT (the pre-fix build in an
A/B audit, a known-bad ground truth), and only the gate's author knows
which, so the report is the triage worksheet and never a verdict.

Every line printed is the lineage gate's own; exit 1 only on ROTTED.
"""
import argparse
import glob
import os
import re
import subprocess
import sys
import zipfile

from . import config as C
from . import fingerprint as FP


class Settings:
    def __init__(self, cfg, config_path):
        g = lambda k: C.get(cfg, "ref_rot." + k)
        self.gates_dir = C.get(cfg, "project.gates_dir")
        self.gate_glob = C.get(cfg, "project.gate_glob")
        self.token = g("token_regex")
        self.suffix = g("rompath_suffix")
        self.image_glob = g("image_glob")
        self.image_prefer = list(g("image_prefer"))
        self.stale = list(g("stale_marker"))
        self.predicate = g("predicate")
        self.family_re = re.compile(g("family_regex"))
        self.no_row_note = g("no_row_note")
        self.advice = list(g("rotted_advice"))
        prefix = g("root_prefix_regex")
        self.def_re = re.compile(
            r'^\s*([A-Za-z_][A-Za-z0-9_]*)='
            r'(?:"\$\{(?:[0-9]+|[A-Za-z_][A-Za-z0-9_]*):-'
            + prefix + r'(?P<sub>' + self.token + r')(?P<subtail>' + re.escape(self.suffix) + r')?\}"'
            r'|"?(?P<plain>' + self.token + r')"?\s*(?:#.*)?$)', re.M)
        self.fp = FP.settings(config_path)


def images_of(imgdir, s):
    """The images under an image dir, the preferred one first. The lineage
    took `vsavjw` else DIRECTORY ORDER until its 14z-139 — on its host `vsavj.zip` happened to
    list before `vsav.zip`, so a stock build was judged by its own image; the
    harness names that preference ([ref_rot].image_prefer, in order) instead
    of inheriting the filesystem's, and falls back to name order."""
    zs = sorted(glob.glob(os.path.join(imgdir, s.image_glob)))
    for sub in s.image_prefer:
        pref = [z for z in zs if sub in os.path.basename(z)]
        if pref:
            return pref
    return zs


def judge(image, s):
    """(rotted: bool, description)"""
    if s.predicate:
        r = subprocess.run(["sh", "-c", s.predicate, "_", image], capture_output=True, text=True)
        return r.returncode != 0, r.stdout.strip()
    names = zipfile.ZipFile(image).namelist()
    prefix, required, reason = s.stale
    marked = [n for n in names if n.startswith(prefix)]
    if marked and required not in names:
        return True, f"{len(names)} members, {reason}"
    return False, f"{len(names)} members"


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=None)
    ap.add_argument("--root", default=None)
    a = ap.parse_args(argv)
    cfg, root = C.consumer(a.config, a.root)
    s = Settings(cfg, a.config)
    os.chdir(root)

    rotted, absent, ok, skipped = [], [], [], []
    for path in sorted(glob.glob(os.path.join(s.gates_dir, s.gate_glob))):
        src = open(path, errors="replace").read()
        body = "\n".join(l for l in src.splitlines() if not l.lstrip().startswith("#"))
        for m in s.def_re.finditer(body):
            var = m.group(1)
            bdir = m.group("sub") or m.group("plain")
            name = os.path.basename(path)
            if m.group("subtail"):
                pass
            elif f"${var}{s.suffix}" not in body and f"${{{var}}}{s.suffix}" not in body:
                skipped.append((name, var, bdir, "not read as a romset"))
                continue
            imgdir = bdir + s.suffix
            if not os.path.isdir(bdir) or not os.path.isdir(imgdir):
                absent.append((name, var, bdir))
                continue
            zs = images_of(imgdir, s)
            if not zs:
                absent.append((name, var, bdir))
                continue
            is_rot, desc = judge(zs[0], s)
            (rotted if is_rot else ok).append((name, var, bdir, desc))

    print(f"== {len(ok)} live, {len(absent)} unbuilt, {len(rotted)} ROTTED"
          f" ({len(skipped)} not romset refs)")
    for n, v, d, w in ok:
        print(f"  ok      {d:<22} {n} (${v}) — {w}")
    for n, v, d in absent:
        print(f"  unbuilt {d:<22} {n} (${v}) — not built here; not a failure")
    for n, v, d, w in rotted:
        print(f"  ROTTED  {d:<22} {n} (${v}) — {w}")

    # ── CURRENCY: reported, never failed. See the header. ─────────────────
    # Wrapped, because a check whose REPORT can abort its VERDICT reports the
    # wrong thing when it breaks.
    try:
        reg, fam_newest = {}, {}
        for row in FP.read_registry(s.fp["registry"]):
            reg[row[0]] = row[1]
        for name in reg.values():
            m = s.family_re.match(name)
            if m:
                fam, n = m.group(1), int(m.group(2))
                if n > fam_newest.get(fam, (-1, ""))[0]:
                    fam_newest[fam] = (n, name)
        # Currency covers EVERY matched reference, not just the ones read as
        # an image: a superseded reference is superseded however the script
        # opens it.
        seen, rows = {}, []
        for script, var, bdir, _w in ok + [(a_, b_, c_, "") for a_, b_, c_, _ in skipped]:
            if not os.path.isdir(bdir):
                continue
            if bdir not in seen:
                zs = images_of(bdir + s.suffix, s)
                try:
                    seen[bdir] = reg.get(FP.program_sha1(zs[0], s.fp), None)
                except (Exception, SystemExit):   # the fingerprint EXITS on an image with no program members
                    seen[bdir] = None
            rows.append((bdir, script, var, seen[bdir]))
        fam_dirs = {}
        for bdir in sorted(seen):
            fam_dirs.setdefault(re.sub(r"\d+$", "", bdir), set()).add(bdir)

        print("\n== currency (REPORT ONLY — a superseded reference is often correct)")
        stale = 0
        for bdir, script, var, expset in sorted(rows):
            if expset is None:
                note = s.no_row_note
            else:
                m = s.family_re.match(expset)
                newest = fam_newest.get(m.group(1), (None, None))[1] if m else None
                if newest and newest != expset:
                    note = f"SUPERSEDED — {expset}; newest is {newest}"
                    stale += 1
                else:
                    note = f"current — {expset}"
            print(f"  {bdir:<22} {script:<34} {note}")
        split = {f: d for f, d in fam_dirs.items() if len(d) > 1}
        if split:
            print("\n  families referenced at MORE THAN ONE generation — at most one")
            print("  of each can be current:")
            for f, d in sorted(split.items()):
                print(f"      {f + '*':<18} {', '.join(sorted(d))}")
        print(f"\n  {stale} registered reference(s) point at a superseded set."
              f" That is information, not a verdict: re-point the ones that meant"
              f" 'the current build', and leave the ones that meant 'that build'.")
    except (Exception, SystemExit) as e:
        print(f"\n  (currency report failed: {e} — the ROT verdict below is unaffected)")

    if rotted:
        print()
        for line in s.advice:
            print(f"  {line}")
    return 1 if rotted else 0


if __name__ == "__main__":
    sys.exit(main())
