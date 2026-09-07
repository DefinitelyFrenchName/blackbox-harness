#!/usr/bin/env python3
"""checkskills.py — lock a consumer's SKILLS to the docs they distil (H10).

  bbh check-skills [--config bbh.toml] [--root DIR] [-v] [--no-selftest]

A SKILL is an agent-facing distillation of a project's documentation that
loads BEFORE the work, so a stale skill is a confidently wrong instruction.
Each rule `- [PFX-N]` in a skill is ANCHORED `**[PFX-N]**` at the exact
paragraph of the docs it distils, and four things are asserted:

  1. ID-LOCK, both ways.  Every rule DEFINITION in a skill has exactly ONE
     anchor in that skill's anchor docs, and every anchor has a definition.
     Deleting or rewriting an anchored paragraph breaks the lock; so does
     adding a rule without anchoring it. A plain `[PFX-N]` (no bold, not
     opening a bullet) is a cross-reference and is ignored on both sides.
  2. LIFTABILITY.  A skill may forbid tokens (a game name, a build dir, a
     board name — whatever would make it level 2 where it claims level 1 or
     0): a fixed list, grepped case-insensitively.
  3. NUMBERS CITE THE LOG.  Every numeric literal a skill quotes (hex,
     comma-grouped integers, decimals, 4+-digit integers, $-addresses, hash
     fragments) must appear verbatim in one of the skill's LOG files —
     never only in a synthesis. A `<name>_history.md` log carries NO
     anchor (a twin is where numbers go, never where a rule lives).
  4. CROSS-REFERENCES RESOLVE.  A plain `[PFX-N]` naming another configured
     prefix must name a rule that skill defines. A prefix NOT configured
     is ignored — a skill that must cite nothing outside its table forbids
     the bracket tokens instead (docs/config.md [skills]).

The table is the consumer's `[skills]` section — `prefixes` (in order) and
one `[skill_<PFX>]` table each (`path`, `docs`, `logs`, `forbid`, optional
`sections` = [[file, "## Header", ...], ...] confining that file's anchors
to named sections). Lineage: VampireSaved `tools/checkskills.py` (14z-114;
table-driven per prefix since then; level 0 added 14z-134), moved with its
logic and every message intact — fidelity F11 diffs the two over the
lineage's eight skills. The extractors are negative-controlled on synthetic
content every run. ROM-free, instrument-free.
"""
import argparse
import re
import sys
import tempfile
from pathlib import Path

from . import config as C


def load_skills(cfg):
    """(skills, xref_prefixes) from a consumer config: an ordered dict of
    prefix -> {path, docs, logs, forbid, sections} — `sections` as
    {file: [headers]} — and the set of prefixes cross-references resolve
    against."""
    skills = {}
    for prefix in C.get(cfg, "skills.prefixes", []) or []:
        sec = f"skill_{prefix}"
        if sec not in cfg:
            raise KeyError(f"[skills].prefixes names {prefix!r} but there is no [{sec}] table")
        t = cfg[sec]
        for k in ("path", "docs", "logs"):
            if k not in t:
                raise KeyError(f"[{sec}] lacks {k!r}")
        sections = {}
        for row in t.get("sections", []) or []:
            if not isinstance(row, list) or len(row) < 2:
                raise KeyError(f"[{sec}].sections rows are [file, header, ...]")
            sections[row[0]] = list(row[1:])
        skills[prefix] = dict(path=t["path"], docs=list(t["docs"]), logs=list(t["logs"]),
                              forbid=list(t.get("forbid", []) or []), sections=sections)
    return skills, set(skills)


ID = r"\[([A-Z]+-\d+)\]"
DEF_SKILL = re.compile(rf"^- {ID}", re.M)        # `- [MSC-3] ...`
ANCHOR_DOC = re.compile(rf"\*\*{ID}\*\*")         # `**[MSC-3]**` anywhere
NUM_PATTERNS = [
    re.compile(r"0x[0-9A-Fa-f]{3,}"),
    re.compile(r"\$[0-9A-Fa-f]{4,}"),
    re.compile(r"(?<![\d.])\d{1,3}(?:,\d{3})+(?!\d)"),
    re.compile(r"(?<![\d.])\d+\.\d+(?![\d.])"),
    re.compile(r"(?<![\d.,])\d{4,}(?![\d.])"),
    re.compile(r"(?<![0-9A-Za-z])[0-9a-f]{8,}(?![0-9A-Za-z])"),
]


def skill_defs(text):
    return DEF_SKILL.findall(text)


def doc_anchors(text):
    return ANCHOR_DOC.findall(text)


def numbers(text):
    found = set()
    for pat in NUM_PATTERNS:
        for m in pat.finditer(text):
            tok = m.group(0)
            if re.fullmatch(r"\d{4}", tok) and tok.startswith("20"):
                continue  # years
            if re.fullmatch(r"\d\.\d", tok):
                continue  # section numbers (1.3, 2.5)
            if re.fullmatch(r"[0-9a-f]{8,}", tok) and tok.isdigit():
                continue  # long decimal caught by the integer pattern
            found.add(tok)
    # a decimal run inside a hex/$ token is not a number of its own
    return {t for t in found
            if not (t.isdigit() and any(t != u and t in u for u in found))}


XREF = re.compile(r"(?<!\*)\[([A-Z]+-\d+)\](?!\*)")


def check(root, skills, xref_prefixes, verbose=False,
          history_regex=r"_(history|HISTORY)\.md$", history_exempt=()):
    root = Path(root)
    fails = []
    cache = {}
    history_re = re.compile(history_regex) if history_regex else None

    def read(rel):
        if rel not in cache:
            p = root / rel
            cache[rel] = p.read_text(encoding="utf-8") if p.exists() else None
        return cache[rel]

    # pass 1: every skill's definitions (for cross-reference resolution)
    defined = {}
    for prefix, cfg in skills.items():
        text = read(cfg["path"])
        defined[prefix] = set(skill_defs(text)) if text else set()

    for prefix, cfg in skills.items():
        text = read(cfg["path"])
        if text is None:
            fails.append(f"{prefix}: skill {cfg['path']} does not exist")
            continue
        if not re.match(r"^---\nname: [a-z0-9-]+\ndescription: .+\n---\n", text):
            fails.append(f"{prefix}: {cfg['path']} lacks the name/description frontmatter")
        defs = skill_defs(text)
        if verbose:
            print(f"  {prefix}: {len(defs)} rules defined in {cfg['path']}")
        if not defs:
            fails.append(f"{prefix}: the skill defines NO rules — has the syntax changed?")
        dupes = sorted({i for i in defs if defs.count(i) > 1})
        if dupes:
            fails.append(f"{prefix}: duplicate definition(s): {', '.join(dupes)}")
        foreign = sorted({i for i in defs if not i.startswith(prefix + "-")})
        if foreign:
            fails.append(f"{prefix}: DEFINES foreign-prefix rule(s) {', '.join(foreign)}")

        # 1. ID-lock against this skill's anchor docs
        anchors = {}
        for rel in cfg["docs"]:
            t = read(rel)
            if t is None:
                fails.append(f"{prefix}: anchor doc missing: {rel}")
                continue
            for i in doc_anchors(t):
                if i.startswith(prefix + "-"):
                    anchors.setdefault(i, []).append(rel)
            # anchors confined to named sections of a rolling file
            hdr_list = cfg.get("sections", {}).get(rel)
            if hdr_list:
                spans = []
                for hdr in hdr_list:
                    s = t.find("\n" + hdr)
                    if s < 0:
                        fails.append(f"{prefix}: {rel} has no section '{hdr}'")
                        continue
                    e = t.find("\n## ", s + 1)
                    spans.append((s, len(t) if e < 0 else e))
                for m in ANCHOR_DOC.finditer(t):
                    i = m.group(1)
                    if i.startswith(prefix + "-") and not any(s <= m.start() < e for s, e in spans):
                        fails.append(f"{prefix}: {i} anchored in {rel} OUTSIDE the standing sections "
                                     f"({', '.join(hdr_list)}) — that file rolls over")
        key = lambda i: int(i.split("-")[1])
        only_skill = sorted(set(defs) - set(anchors), key=key)
        only_docs = sorted(set(anchors) - set(defs), key=key)
        if only_skill:
            fails.append(f"{prefix}: defined in the skill, ANCHORED NOWHERE: {', '.join(only_skill)}")
        if only_docs:
            fails.append(f"{prefix}: anchored in the docs, NOT DEFINED in the skill: {', '.join(only_docs)}")
        for i in sorted((i for i, locs in anchors.items() if len(locs) > 1), key=key):
            fails.append(f"{prefix}: {i} anchored in more than one place: {', '.join(anchors[i])}")

        # 2. liftability (the frontmatter names sibling skills; lint the body)
        body = text.split("\n---\n", 1)[-1]
        for tok in cfg["forbid"]:
            for n, line in enumerate(body.splitlines(), 1):
                if tok.lower() in line.lower():
                    fails.append(f"{prefix}: level-1 skill names '{tok}' at line {n} — that is level 2")
                    break

        # 3. numbers cite the log
        log_text = ""
        for rel in cfg["logs"]:
            t = read(rel)
            if t is None:
                fails.append(f"{prefix}: log missing: {rel}")
            else:
                log_text += "\n" + t
                # HISTORY FILES CARRY NO ANCHORS: a `<name>_history.md` twin
                # is a LOG (numbers moved there still resolve) but an
                # anchored paragraph may never move there — the anchor
                # migrates to the surviving reference sentence, or the
                # paragraph stays. Session archives named in
                # [skills].history_exempt are not twins and are exempt.
                if (history_re and history_re.search(rel)
                        and rel not in set(history_exempt)):
                    for i in doc_anchors(t):
                        if i.startswith(prefix + "-"):
                            fails.append(f"{prefix}: {i} anchored in HISTORY file {rel} "
                                         "— history carries no anchors")
        missing = sorted(t for t in numbers(text) if t not in log_text)
        if verbose:
            print(f"  {prefix}: {len(numbers(text))} numeric tokens quoted")
        if missing:
            fails.append(f"{prefix}: number(s) quoted but in NO log: {', '.join(missing)}")

        # 4. cross-references resolve
        for ref in sorted(set(XREF.findall(body))):
            rp = ref.split("-")[0]
            if rp in xref_prefixes and rp != prefix and ref not in defined.get(rp, set()):
                fails.append(f"{prefix}: cross-reference [{ref}] names a rule {rp} does not define")
    return fails


SYN_SKILL = ("---\nname: x\ndescription: y\n---\n"
             "- [XX-1] rule one, see [YY-9] and 0x600000 and 2609\n- [XX-2] rule two\n")
SYN_DOC = "text **[XX-1]** anchor one. Also **[XX-2]** anchor two. plain [XX-3] is a ref\n"
SYN_LOG = "the log says 0x600000 and 2609\n"


def selftests():
    """The extractors and every check, negative-controlled on synthetic
    content — a family that has stopped matching passes every claim it no
    longer finds."""
    bad = []
    if skill_defs(SYN_SKILL) != ["XX-1", "XX-2"]:
        bad.append("skill extractor no longer matches the definition syntax")
    if doc_anchors(SYN_DOC) != ["XX-1", "XX-2"]:
        bad.append("doc extractor no longer matches the anchor syntax (or counts a plain ref)")
    if "YY-9" in skill_defs(SYN_SKILL):
        bad.append("a cross-reference was read as a definition")
    probe = "see 0x600000, 2609, 66,265,152, 0.125, $FF8058, 46fc74af, 12 MB, 2026"
    if numbers(probe) != {"0x600000", "2609", "66,265,152", "0.125", "$FF8058", "46fc74af"}:
        bad.append(f"number extractor drifted: {numbers(probe)}")

    def xx(**kw):
        d = dict(path="skill.md", docs=["doc.md"], logs=["log.md"], forbid=["vsav"], sections={})
        d.update(kw)
        return d

    skills = {"XX": xx()}
    xref = {"XX", "YY"}
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)

        def write(skill=SYN_SKILL, doc=SYN_DOC, log=SYN_LOG):
            (root / "skill.md").write_text(skill)
            (root / "doc.md").write_text(doc)
            (root / "log.md").write_text(log)

        def run():
            return check(root, skills, xref)

        write()
        # YY-9 is a cross-ref to a prefix with no skill: must not fail on its own
        skills["YY"] = dict(path="yy.md", docs=["doc.md"], logs=["log.md"], forbid=[], sections={})
        (root / "yy.md").write_text("---\nname: y\ndescription: y\n---\n- [YY-9] nine\n")
        (root / "doc.md").write_text(SYN_DOC + "**[YY-9]** y anchor\n")
        if run():
            bad.append(f"a matched synthetic tree FAILS — the checks are wrong: {run()}")
        (root / "yy.md").write_text("---\nname: y\ndescription: y\n---\n- [YY-8] eight\n")
        (root / "doc.md").write_text(SYN_DOC + "**[YY-8]** y anchor\n")
        if not any("cross-reference [YY-9]" in f for f in run()):
            bad.append("a dangling cross-reference was not caught")
        del skills["YY"]
        write(skill=SYN_SKILL + "- [XX-3] unanchored\n")
        if not any("ANCHORED NOWHERE" in f for f in run()):
            bad.append("an unanchored rule was not caught")
        write(doc=SYN_DOC + "**[XX-4]** orphan\n")
        if not any("NOT DEFINED" in f for f in run()):
            bad.append("an orphan anchor was not caught")
        write(doc=SYN_DOC + "again **[XX-1]**\n")
        if not any("more than one place" in f for f in run()):
            bad.append("a duplicate anchor was not caught")
        write(skill=SYN_SKILL + "- [XX-2] again\n")
        if not any("duplicate definition" in f for f in run()):
            bad.append("a duplicate definition was not caught")
        write(skill=SYN_SKILL + "- [ZZ-1] wrong tier\n")
        if not any("foreign-prefix" in f for f in run()):
            bad.append("a foreign-prefix definition was not caught")
        write(skill=SYN_SKILL.replace("rule two", "rule two about VSAV"))
        if not any("level-1 skill names" in f for f in run()):
            bad.append("a forbidden token in a level-1 skill was not caught")
        write(skill=SYN_SKILL.replace("rule two", "rule two quotes 0x123456"))
        if not any("in NO log" in f for f in run()):
            bad.append("a number missing from every log was not caught")
        skills["XX"] = xx(logs=["log.md", "log_history.md"])
        write()
        (root / "log_history.md").write_text("archived. **[XX-2]** moved here\n")
        if not any("anchored in HISTORY file" in f for f in run()):
            bad.append("an anchor in a history-file log was not caught")
        # the same twin named exempt (a session archive) is NOT a finding
        if any("anchored in HISTORY file" in f
               for f in check(root, skills, xref, history_exempt=["log_history.md"])):
            bad.append("an exempt history file was still read as a twin")
        # a section restriction: anchors under the named header pass, one
        # outside it fails (the skill here cites no other prefix, so the
        # positive case must come back EMPTY)
        skills["XX"] = xx(sections={"doc.md": ["## Standing"]})
        lone = SYN_SKILL.replace(", see [YY-9]", "")
        write(skill=lone, doc="intro\n\n## Standing\n" + SYN_DOC)
        if run():
            bad.append(f"anchors inside the named section FAIL: {run()}")
        write(skill=lone, doc="intro\n\n## Standing\nnothing\n\n## Other\n" + SYN_DOC)
        if not any("OUTSIDE the standing sections" in f for f in run()):
            bad.append("an anchor outside the named sections was not caught")
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--config", help="the consumer's bbh.toml (else $BBH_CONFIG)")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--root", help="tree to check (default: the consumer root)")
    ap.add_argument("--no-selftest", action="store_true")
    args = ap.parse_args()

    cfg, root = C.consumer(args.config, args.root)
    try:
        skills, xref = load_skills(cfg)
    except KeyError as e:
        print(f"  FAIL  config: {e}")
        sys.exit(2)
    if not skills:
        print("  FAIL  config: [skills].prefixes names no skill")
        sys.exit(2)
    fails = check(root, skills, xref, args.verbose,
                  history_regex=C.get(cfg, "skills.history_regex"),
                  history_exempt=C.get(cfg, "skills.history_exempt"))
    if not args.no_selftest:
        fails += [f"SELF-TEST: {b}" for b in selftests()]
    if fails:
        for line in fails:
            print(f"  FAIL  {line}")
        print(f"\n{len(fails)} problem(s) between the skills and the docs")
        sys.exit(1)
    n = sum(len(skill_defs((Path(root) / c["path"]).read_text())) for c in skills.values())
    print(f"ALL PASS ({n} rules across {len(skills)} skills: every rule anchored once, "
          "every anchor defined, level 1 game-free, every number in a log)")


if __name__ == "__main__":
    main()
