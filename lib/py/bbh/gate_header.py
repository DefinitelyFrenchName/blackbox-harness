"""gate_header.py — THE HEADER CONTRACT parser, one copy (docs/gate_contract.md
§3), shared by the gate index, the header-defaults check and anything else
that reads a gate's opening comment block.

A gate's header is every `#` line after the shebang, up to the first line
that is not a comment. Its FIRST PARAGRAPH — up to the first bare `#` line —
opens with `# <name>.sh — <claim>` and is the gate's index sentence; the
WHOLE block carries the runtime it quotes (`~N min`), the session token, a
`Usage:` line naming its defaults. Every regex is the consumer's
`[gate_header]` section (docs/config.md); the defaults are the lineage's.

Lineage: VampireSaved's tools/gen_gate_index.py (header_text, locks_sentence,
derive_since, derive_needs) and tools/audit_header_defaults.py
(header_lines) — two private readers of the same block, now one.
"""
import re

from . import config as C


def header_lines(path, limit=400):
    """The raw `#` lines after the shebang (each still starting with `#`)."""
    out = []
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    for line in lines[1:limit + 1]:
        if not line.startswith("#"):
            break
        out.append(line)
    return out


def header_text(path, whole=False, limit=120):
    """The header as one string: the FIRST PARAGRAPH (up to the first blank
    `#` line) by default, the WHOLE block with `whole=True`; the `#` markers
    and blank lines dropped, lines joined by a space."""
    out = []
    for line in header_lines(path, limit):
        t = line.lstrip("#").strip()
        if not t and out and not whole:
            break
        if t:
            out.append(t)
    return " ".join(out)


class Settings:
    """The [gate_header] section, read once."""

    def __init__(self, cfg):
        g = lambda k: C.get(cfg, "gate_header." + k)
        self.title_sep = g("title_sep_regex")
        self.session_re = re.compile(g("session_regex"))
        self.duration_re = re.compile(g("duration_regex"))
        self.index_out = g("index_out")
        self.families_tsv = g("families_tsv")
        self.families = [(f[0], f[1]) for f in g("families")]
        self.kinds = [(k[0], k[1]) for k in g("kinds")]
        self.needs_instruments = [(k[0], k[1]) for k in g("needs_instruments")]
        self.needs_build_re = re.compile(g("needs_build_regex"))
        self.preamble = list(g("index_preamble"))


def claim(name, head, settings):
    """The index sentence: the first paragraph with `<name>.sh —` stripped,
    whitespace collapsed, cut at ~240 chars on a sentence boundary."""
    t = re.sub(r"^" + re.escape(name) + settings.title_sep, "", head)
    t = re.sub(r"\s+", " ", t).strip()
    if len(t) <= 240:
        return t
    cut = t[:240]
    m = max(cut.rfind(". "), cut.rfind("; "), cut.rfind(": "))
    if m > 120:
        return cut[:m + 1].rstrip()
    return cut.rstrip() + "…"


def first_session(head, settings):
    m = settings.session_re.search(head)
    return m.group(1) if m else "—"


def first_duration(head, settings):
    m = settings.duration_re.search(head)
    return f"~{m.group(1)} {m.group(2)}" if m else ""


def kind_of(name, settings):
    for prefix, kind in settings.kinds:
        if name.startswith(prefix):
            return kind
    return "test"
