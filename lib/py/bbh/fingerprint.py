#!/usr/bin/env python3
"""fingerprint.py — identify which build an input path resolves to, and map
it to an expectation set (the auto-detecting runner's dispatch).

    python3 -m bbh.fingerprint <rompath> [--set NAME] [--registry FILE]
                               [--sha-only | --set-key | --full] [--config bbh.toml]

Prints the expectation-set name on stdout (exit 0), or the unregistered
fingerprint with exit 2. --sha-only prints just the PROGRAM key; --set-key
just the WHOLE-SET key; --full a whole-set digest with a per-region
breakdown (reporting only — see below).

THE TWO KEYS. The PROGRAM key is the SHA-1 of the set's program members
(file order, sorted by member number) from the FIRST image found along the
';'-separated search path — the resolution an emulator applies. The
WHOLE-SET key is the SHA-1 over every member of every image in the build's
OWN directory (the directory holding the resolved image) and nothing else,
so it is CHAIN-INDEPENDENT by construction: `--full` hashes the union of the
RESOLVED images, and a ';' chain folds the reference directory into that
digest, so one build hashes differently depending on which caller asked
(the lineage measured it: two digests for one build dir). The registry maps
either key to an expectation-set name; the resolver tries WHOLE-SET first
(the specific key), then PROGRAM, loudly — the program key cannot see
non-program content, and two builds differing only there share it. Rows
are added only at freeze time, as a build decision.

KINDS (`[fingerprint].kind`):
  zip-members  the lineage's: `<set>.zip` on the search path, program
               members selected by `program_member_regex` (group 1 = the
               member's ORDER, an integer), whole-set over every *.zip in
               the directory, `--full` over the resolved image plus each
               `parent_sets` image found along the path
  file-sha1    the image is ONE file, `file_pattern` with `{set}` (default
               `{set}.bin`): the program key is its SHA-1, the whole-set
               key covers every regular file in its directory
  command      `program_command` / `wholeset_command` are run with
               `{rompath}` and `{set}` substituted and must print the key —
               for a system whose identity no file rule captures

Lineage: VampireSaved's tools/build_fingerprint.py, which imported its
board's decryption module ONLY for the member regex and hard-named the
parent set; both are `[fingerprint]` config here. Every printed line is
the lineage's text (fidelity F6 diffs them).
"""

import argparse
import hashlib
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path

_LINEAGE = {
    "kind": "zip-members",
    "program_member_regex": r"\.(0[3-9]|10|4[1-4])[a-ln-z]?$",
    "parent_sets": ["vsav"],
    "region_rules": [[r"\.key$", "key"], [r"\.0[12]$", "z80"],
                     [r"^vsw\..*m$", "gfx/qsnd"], [r"^vsw\.", "prg"],
                     ["@program", "prg"]],
    "region_default": "gfx/qsnd",
    "file_pattern": "{set}.bin",
    "program_command": "",
    "wholeset_command": "",
}


def settings(config_path=None):
    """The [fingerprint] section plus the suite's registry / default set,
    from --config, else $BBH_CONFIG, else the lineage's literals."""
    vals = dict(_LINEAGE)
    vals["registry"] = "tests/expected/registry.tsv"
    vals["default_set"] = "vsavj"
    path = config_path or os.environ.get("BBH_CONFIG")
    if path and os.path.isfile(path):
        from . import config as C
        cfg = C.load(path)
        root = C.root_of(path, cfg)
        for k in _LINEAGE:
            vals[k] = C.get(cfg, "fingerprint." + k, vals[k])
        vals["registry"] = os.path.join(root, C.get(cfg, "suite.registry", vals["registry"]))
        vals["default_set"] = C.get(cfg, "suite.default_set", vals["default_set"])
    return vals


# ── zip-members ──────────────────────────────────────────────────────────────

def _prg_re(s):
    return re.compile(s["program_member_regex"])


def program_sha1(zpath, s):
    rx = _prg_re(s)
    with zipfile.ZipFile(zpath) as zf:
        prgs = sorted((n for n in zf.namelist() if rx.search(n)),
                      key=lambda n: int(rx.search(n).group(1)))
        if not prgs:
            sys.exit(f"{zpath}: no program members")
        h = hashlib.sha1()
        for n in prgs:
            h.update(zf.read(n))
    return h.hexdigest()


def _region(name, s, rx):
    for pat, region in s["region_rules"]:
        if pat == "@program":
            if rx.search(name):
                return region
        elif re.search(pat, name):
            return region
    return s["region_default"]


def full_fingerprint(zpaths, s):
    """SHA-1 over every member of every resolved image, plus a per-region
    breakdown by NAME — a heuristic (an emulator classifies by descriptor
    type, which this tool cannot read); `region_rules` is where a consumer
    names its members so the heuristic stays right."""
    rx = _prg_re(s)
    per = {}
    h = hashlib.sha1()
    for zpath in zpaths:
        with zipfile.ZipFile(zpath) as zf:
            for n in sorted(zf.namelist()):
                data = zf.read(n)
                h.update(n.encode())
                h.update(data)
                region = _region(n, s, rx)
                cnt, size = per.get(region, (0, 0))
                per[region] = (cnt + 1, size + len(data))
    return h.hexdigest(), per


def wholeset_key(zpath):
    """The DISPATCH whole-set key: every *.zip in the image's own directory."""
    h = hashlib.sha1()
    for zp in sorted(Path(zpath).parent.glob("*.zip"), key=lambda q: q.name):
        h.update(zp.name.encode())
        with zipfile.ZipFile(zp) as zf:
            for n in sorted(zf.namelist()):
                h.update(n.encode())
                h.update(zf.read(n))
    return h.hexdigest()


# ── file-sha1 ────────────────────────────────────────────────────────────────

def file_sha1(path):
    h = hashlib.sha1()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def dir_sha1(path):
    """Every regular file in the image's directory, by name."""
    h = hashlib.sha1()
    for p in sorted(Path(path).parent.iterdir(), key=lambda q: q.name):
        if p.is_file():
            h.update(p.name.encode())
            h.update(p.read_bytes())
    return h.hexdigest()


# ── command ──────────────────────────────────────────────────────────────────

def command_key(template, rompath, setname):
    if not template:
        sys.exit("kind 'command' needs [fingerprint].program_command and wholeset_command")
    cmd = template.replace("{rompath}", rompath).replace("{set}", setname)
    out = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        sys.exit(f"fingerprint command failed ({out.returncode}): {cmd}\n{out.stderr}")
    return out.stdout.split()[0]


# ── resolution ───────────────────────────────────────────────────────────────

def resolve_image(rompath, setname, s):
    """The first image found along the ';'-separated search path, or None."""
    kind = s["kind"]
    for d in rompath.split(";"):
        if kind == "zip-members":
            cand = Path(d) / f"{setname}.zip"
        elif kind == "file-sha1":
            cand = Path(d) / s["file_pattern"].replace("{set}", setname)
        else:
            return Path(d)      # command: the path is the command's business
        if cand.is_file():
            return cand
    return None


def keys_for(rompath, setname, s):
    """(program key, whole-set key, the resolved image path) for a search path."""
    kind = s["kind"]
    if kind == "command":
        return (command_key(s["program_command"], rompath, setname),
                command_key(s["wholeset_command"], rompath, setname),
                Path(rompath.split(";")[0]))
    zpath = resolve_image(rompath, setname, s)
    if zpath is None:
        what = f"{setname}.zip" if kind == "zip-members" else s["file_pattern"].replace("{set}", setname)
        sys.exit(f"{what} not found in rompath {rompath}")
    if kind == "zip-members":
        return program_sha1(zpath, s), wholeset_key(zpath), zpath
    if kind == "file-sha1":
        return file_sha1(zpath), dir_sha1(zpath), zpath
    sys.exit(f"unknown [fingerprint].kind '{kind}'")


def read_registry(path):
    rows = []
    if Path(path).is_file():
        for line in Path(path).read_text().splitlines():
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) >= 2:
                rows.append((parts[0], parts[1]))
    return rows


def lookup(rows, wkey, sha, zpath, registry):
    """The lineage's DUAL LOOKUP: whole-set first (silently), then the
    program key with a NOTE on stderr, else None."""
    for key, name in rows:
        if key == wkey:
            return name
    for key, name in rows:
        if key == sha:
            # LOUD BY DESIGN. A program-key hit means "not registered under a
            # whole-set key", and a silent hit is how two builds differing
            # only outside the program members resolve to ONE set.
            print(f"NOTE: {Path(zpath).parent} resolved to '{name}' by PROGRAM KEY "
                  f"{sha} — not registered under a whole-set key ({wkey}). "
                  f"The program key cannot see gfx/QSound/extension content.",
                  file=sys.stderr)
            return name
    return None


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("rompath", help="';'-separated search path, emulator resolution order")
    ap.add_argument("--set", dest="setname", default=None)
    ap.add_argument("--registry", type=Path, default=None)
    ap.add_argument("--config", default=None, help="bbh.toml (else $BBH_CONFIG, else the lineage's literals)")
    ap.add_argument("--sha-only", action="store_true")
    ap.add_argument("--set-key", action="store_true",
                    help="print the whole-set DISPATCH key (this build's own directory only) and exit")
    ap.add_argument("--full", action="store_true",
                    help="whole-set fingerprint over every resolved image + region breakdown (reporting)")
    args = ap.parse_args(argv)

    s = settings(args.config)
    setname = args.setname or s["default_set"]
    registry = args.registry if args.registry is not None else Path(s["registry"])

    if args.full:
        if s["kind"] != "zip-members":
            sys.exit("--full is defined for kind 'zip-members' only")
        zpath = resolve_image(args.rompath, setname, s)
        if zpath is None:
            sys.exit(f"{setname}.zip not found in rompath {args.rompath}")
        # Resolve the clone chain the way the emulator does: the set's own
        # image first, then each parent set's image for shared members —
        # deduped by RESOLVED path, because overlay directories symlink the
        # reference images and the same file appears under several names.
        chain, seen = [zpath], {zpath.resolve()}
        for d in args.rompath.split(";"):
            for parent in s["parent_sets"]:
                cand = Path(d) / f"{parent}.zip"
                if cand.is_file() and cand.resolve() not in seen:
                    seen.add(cand.resolve())
                    chain.append(cand)
        full, per = full_fingerprint(chain, s)
        print(f"full-set fingerprint: {full}")
        for region in sorted(per):
            cnt, size = per[region]
            print(f"  {region:9s} {cnt:2d} members  {size/1048576:7.2f} MB")
        print("  zips: " + ", ".join(str(z.name) for z in chain))
        return 0

    sha, wkey, zpath = keys_for(args.rompath, setname, s)
    if args.sha_only:
        print(sha)
        return 0
    if args.set_key:
        print(wkey)
        return 0

    name = lookup(read_registry(registry), wkey, sha, zpath, registry)
    if name is not None:
        print(name)
        return 0
    print(f"UNREGISTERED build: whole-set {wkey}, program {sha} ({zpath})\n"
          f"add a row to {registry} as a build decision (STATE.md)",
          file=sys.stderr)
    print(sha)
    return 2


if __name__ == "__main__":
    sys.exit(main())
