"""tier.py — the transitive "needs an instrument" classifier, and the
anti-orphan report the runners print.

    python3 -m bbh.tier <bbh.toml> --unregistered   the runner's report block
    python3 -m bbh.tier <bbh.toml> --list           name / INSTRUMENT|PLAIN / registry

A gate needs an instrument (an emulator, a simulator, a driver) if its body,
comments stripped, matches any of [tier].patterns — or if a lib it SOURCES
does, followed to [tier].source_depth. Lineage: VampireSaved's
run_all_static.sh, where the check had to become transitive after two gates
reached MAME only through a sourced lib and were reported static; one of
them then ran for 208 s inside a chain advertised as emulator-free.

The report is REPORTED, NOT FAILED, by design: adding a gate and forgetting
to register it is exactly the drift the runner exists to surface, but a new
gate is also the moment a hard failure is most annoying and least
informative. `--strict` on the sweep runner is where it becomes fatal.
"""
import glob
import os
import re
import sys

from . import config as C


def _uncomment(path):
    try:
        with open(path, errors="replace") as f:
            return "\n".join(l for l in f.read().splitlines()
                             if not l.lstrip().startswith("#"))
    except OSError:
        return ""


class Tier:
    def __init__(self, cfg, root):
        self.root = root
        self.emu = re.compile("|".join(f"(?:{p})" for p in C.get(cfg, "tier.patterns")))
        self.src = re.compile(C.get(cfg, "tier.source_regex"), re.M)
        self.depth = int(C.get(cfg, "tier.source_depth"))
        self.gates_dir = C.get(cfg, "project.gates_dir")
        self.gate_glob = C.get(cfg, "project.gate_glob")
        self.prefixes = list(C.get(cfg, "project.runner_prefixes"))
        self.suffixes = list(C.get(cfg, "project.manual_suffixes"))

    def needs_instrument(self, path, _depth=0):
        body = _uncomment(path)
        if self.emu.search(body):
            return True
        if _depth < self.depth:
            for lib in self.src.findall(body):
                if self.needs_instrument(os.path.join(self.root, lib), _depth + 1):
                    return True
        return False

    def gates(self):
        pat = os.path.join(self.root, self.gates_dir, self.gate_glob)
        for p in sorted(glob.glob(pat)):
            name = os.path.basename(p)
            name = name[:-3] if name.endswith(".sh") else name
            yield name, p

    def is_runner_or_manual(self, name):
        return any(name.startswith(x) for x in self.prefixes) or \
               any(name.endswith(x) for x in self.suffixes)


def read_registry(path):
    if not os.path.exists(path):
        return set()
    with open(path) as f:
        return {l.split("#")[0].strip() for l in f} - {""}


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    cfg_path = argv[0]
    cfg = C.load(cfg_path)
    root = C.root_of(cfg_path, cfg)
    t = Tier(cfg, root)
    word = C.get(cfg, "project.instrument_word")
    reg_p = os.path.join(root, C.get(cfg, "registries.portable"))
    reg_s = os.path.join(root, C.get(cfg, "registries.static"))
    portable, static = read_registry(reg_p), read_registry(reg_s)
    known = portable | static
    mode = argv[1] if len(argv) > 1 else "--unregistered"
    if mode == "--list":
        for name, p in t.gates():
            kind = "INSTRUMENT" if t.needs_instrument(p) else "PLAIN"
            where = "portable" if name in portable else "static" if name in static else "-"
            print(f"{name}\t{kind}\t{where}")
        return 0
    if mode == "--unregistered":
        unreg = []
        for name, p in t.gates():
            if name in known or t.is_runner_or_manual(name):
                continue
            if not t.needs_instrument(p):
                unreg.append(name)
        if unreg:
            print(f"  {len(unreg)} {word}-free gate(s) in NEITHER registry:")
            for n in unreg:
                print(f"      {n}")
            print(f"  Add each to {os.path.relpath(reg_s, root)} (or "
                  f"{os.path.basename(reg_p)} if it needs no")
            print(f"  {C.get(cfg, 'registries.static_needs_env') or 'input'} and no build dir),"
                  f" or note why it must stay manual.")
        else:
            print(f"  ok: every {word}-free gate is registered")
        return 0
    print(f"bbh tier: unknown mode {mode!r}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
