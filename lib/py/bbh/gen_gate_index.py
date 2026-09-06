"""gen_gate_index.py — THE GATE INDEX is GENERATED (bbh gate-index).

    python3 -m bbh.gen_gate_index [--config bbh.toml] [--root DIR]   rewrite the index
    python3 -m bbh.gen_gate_index ... --check       regenerate, cmp, diff on drift (exit 1)
    python3 -m bbh.gen_gate_index ... --stdout      print the regenerated index instead

WHY THIS EXISTS (lineage: VampireSaved 14z-123, the documentation
rationalization pass). Its HANDOFF carried a 2,160-line hand-written fence
of `tests/x.sh   # comment` lines — 168 of the 281 scripts, 113 unindexed,
one duplicated, each comment a session narrative the script's own header
often lacked. The ruling: a gate's WHY lives in the gate's header; the index
is what a reader opens INSTEAD of the fence, and it cannot go stale — every
row is derived from the tree, and a consumer gate running `--check` fails
when the committed file differs from a regeneration.

WHAT A ROW IS. One per gate under the gates dir:
  gate    — the script
  kind    — from its name prefix ([gate_header].kinds: audit / run / test)
  tier    — the portable registry's name / the static registry's name /
            the instrument word (in neither: needs an instrument)
  family  — hand-assigned in [gate_header].families_tsv (the ONE hand-
            maintained input: `gate<TAB>family[<TAB>needs][<TAB>since]`);
            completeness is enforced both ways — a new script without a
            row, or a row whose script is gone, fails --check
  needs   — the TSV override, else derived: portable = nothing; static =
            the [registries].static_needs_env variable; instrument = the
            instruments its header names ([gate_header].needs_instruments,
            "a build dir" on needs_build_regex) + the first `~N min/s`
  locks   — the header's own first paragraph, cut at ~240 chars on a
            sentence end. The header is the source of truth; if a row
            reads badly, fix the header, not this tool.
  since   — the TSV override, else the first session token the header quotes
Rows are grouped by family ([gate_header].families, in that order), sorted
by name. The opening prose is [gate_header].index_preamble.
"""
import argparse
import difflib
import os
import sys
from pathlib import Path

from . import config as C
from . import gate_header as GH


def read_tsv(root, tsv):
    rows = {}
    p = root / tsv
    if not p.exists():
        return rows
    for line in p.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        c = line.split("\t")
        rows[c[0]] = {"family": c[1] if len(c) > 1 else "",
                      "needs": c[2] if len(c) > 2 else "",
                      "since": c[3] if len(c) > 3 else ""}
    return rows


def registry_names(root, rel):
    p = root / rel
    if not p.exists():
        return set()
    return {l.strip() for l in p.read_text(encoding="utf-8").splitlines()
            if l.strip() and not l.startswith("#")}


def derive_needs(tier, head, s, tiers, static_needs, word):
    if tier == tiers["portable"]:
        return "—"
    if tier == tiers["static"]:
        return static_needs
    inst = []
    h = head.lower()
    for key, label in s.needs_instruments:
        if key in h and label not in inst:
            inst.append(label)
    if s.needs_build_re.search(h):
        inst.append("a build dir")
    dur = GH.first_duration(head, s)
    return ", ".join(inst + ([dur] if dur else [])) or word


def collect(cfg, root):
    s = GH.Settings(cfg)
    gates_dir = C.get(cfg, "project.gates_dir")
    gate_glob = C.get(cfg, "project.gate_glob")
    reg_port = C.get(cfg, "registries.portable")
    reg_stat = C.get(cfg, "registries.static")
    word = C.get(cfg, "project.instrument_word")
    static_needs = C.get(cfg, "registries.static_needs_env") or "—"
    tiers = {"portable": Path(reg_port).stem, "static": Path(reg_stat).stem, "instrument": word}
    tsv = read_tsv(root, s.families_tsv)
    port, stat = registry_names(root, reg_port), registry_names(root, reg_stat)
    fam_names = [f for f, _ in s.families]
    scripts = sorted((root / gates_dir).glob(gate_glob))
    rows, problems, seen = [], [], set()
    for p in scripts:
        gate = f"{gates_dir}/{p.name}"
        seen.add(gate)
        head = GH.header_text(p)
        whole = GH.header_text(p, whole=True)
        tier = tiers["portable"] if p.stem in port else tiers["static"] if p.stem in stat else tiers["instrument"]
        t = tsv.get(gate)
        if t is None:
            problems.append(f"NO FAMILY ROW in {s.families_tsv}: {gate}")
            fam = "?"
            needs = since = ""
        else:
            fam, needs, since = t["family"], t["needs"], t["since"]
            if fam not in fam_names:
                problems.append(f"UNKNOWN FAMILY {fam!r} for {gate}")
        rows.append({"gate": gate, "kind": GH.kind_of(p.name, s), "tier": tier, "family": fam,
                     "needs": needs or derive_needs(tier, whole, s, tiers, static_needs, word),
                     "locks": GH.claim(p.name, head, s) or "(no header sentence — write one)",
                     "since": since or GH.first_session(whole, s)})
    for gate in tsv:
        if gate not in seen:
            problems.append(f"DEAD ROW in {s.families_tsv}: {gate} (script gone)")
    return rows, problems, s, tiers


def cell(x):
    return x.replace("|", "\\|")


def render(rows, s, tiers):
    out = ["\n".join(s.preamble) + "\n"]
    n = len(rows)
    tp, ts, ti = tiers["portable"], tiers["static"], tiers["instrument"]
    count = {t: sum(1 for r in rows if r["tier"] == t) for t in (tp, ts, ti)}
    out.append(f"**{n} scripts** — {count[tp]} {tp}, {count[ts]} {ts}, "
               f"{count[ti]} {ti}-tier (run by name).\n")
    out.append("| family | scripts | what the family is |\n|---|---|---|")
    for f, desc in s.families:
        out.append(f"| [{f}](#{f}) | {sum(1 for r in rows if r['family'] == f)} | {desc} |")
    out.append("")
    for f, desc in s.families:
        fam_rows = [r for r in rows if r["family"] == f]
        if not fam_rows:
            continue
        out.append(f"## {f}\n")
        out.append(f"{desc}.\n")
        out.append("| gate | kind | tier | needs | locks (the script's own header) | since |\n|---|---|---|---|---|---|")
        for r in sorted(fam_rows, key=lambda r: r["gate"]):
            out.append(f"| `{r['gate']}` | {r['kind']} | {r['tier']} | {cell(r['needs'])} | {cell(r['locks'])} | {cell(r['since'])} |")
        out.append("")
    fam_names = [f for f, _ in s.families]
    unk = [r for r in rows if r["family"] not in fam_names]
    if unk:
        out.append(f"## UNASSIGNED (fix {s.families_tsv})\n")
        out.append("| gate | tier |\n|---|---|")
        for r in unk:
            out.append(f"| `{r['gate']}` | {r['tier']} |")
        out.append("")
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=None)
    ap.add_argument("--root", default=None)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--stdout", action="store_true")
    a = ap.parse_args(argv)
    cfg, root = C.consumer(a.config, a.root)
    root = Path(root)
    rows, problems, s, tiers = collect(cfg, root)
    for p in problems:
        print("PROBLEM " + p)
    text = render(rows, s, tiers)
    if a.stdout:
        sys.stdout.write(text)
        return 1 if problems else 0
    dst = root / s.index_out
    if a.check:
        cur = dst.read_text(encoding="utf-8") if dst.exists() else ""
        if cur != text:
            print(f"STALE {s.index_out} differs from a regeneration:")
            for line in list(difflib.unified_diff(cur.splitlines(), text.splitlines(),
                                                  "committed", "regenerated", lineterm=""))[:40]:
                print("  " + line)
            return 1
        if problems:
            return 1
        print(f"ok    {s.index_out} is current ({len(rows)} scripts, every one with a family)")
        return 0
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(text, encoding="utf-8")
    print(f"wrote {s.index_out} ({len(rows)} scripts; {len(problems)} problems)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
