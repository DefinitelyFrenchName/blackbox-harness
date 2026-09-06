"""config.py — load a consumer's bbh.toml and answer `get <section.key>`.

    python3 -m bbh.config <bbh.toml> get <section.key> [--default VALUE]
    python3 -m bbh.config <bbh.toml> dump

Paths in a config are RELATIVE TO THE CONFIG FILE'S DIRECTORY (the consumer
root); the sh side cd's there before reading any of them. A list prints one
item per line (an inner array as tab-joined fields); an inline table prints
`key=value` lines; a missing key without --default exits 3 with the key
named, so a runner cannot silently run on an empty value.

Defaults live in DEFAULTS below, ONE place, and are the values the
VampireSaved harness carried as literals — documented in docs/config.md with
the bin (code / config / profile) each key came from.
"""
import sys
from . import toml_subset

DEFAULTS = {
    "project": {
        "root": ".",                # the consumer tree, relative to the config file
        "gates_dir": "tests",
        "gate_glob": "*.sh",
        "lib_dir": "tests/lib",
        "runner_prefixes": ["run_"],
        "manual_suffixes": ["_soak"],
        "tools_dir": "tools",
        "shadow_link_dirs": ["build", "tests", "docs"],
        "instrument_word": "emulator",
    },
    "registries": {
        "portable": "tests/ci_portable.txt",
        "static": "tests/ci_static.txt",
        "sweep": "tests/ci_emulator.tsv",
        "static_needs_env": "ROMDIR",
    },
    "tier": {
        "patterns": [r"run_(replay_)?(mame|fbneo)\.sh", r"run_replay_guarded\.sh",
                     r"MAME_BIN", r"FBNEO_BIN", r"autoboot_script", r"emu/fbneo/fbneo",
                     r"run_battery", r"run_sim_jtcps2\.sh",
                     r"run_inp_probe\.sh", r"run_inp_guarded\.sh"],
        "source_regex": r'^\s*\.\s+"?\$(?:REPO|\{REPO\})"?/(tests/lib/[a-z0-9_]+\.sh)',
        "source_depth": 2,
    },
    "thresholds": {
        "flicker_max": 2,
        "reconverge": 60,
        "flicker_max_total": 8,
    },
    "suite": {
        "replays_dir": "tests/replays",
        "expected_dir": "tests/expected",
        "mask_default": "043c-043d,4182-41a2,7f00-8000",
    },
    "classify": {
        "skip_regex": r"^ *SKIP",
        "shell_error_regex": r"\.sh: line [0-9]+: [A-Za-z_][A-Za-z0-9_]*: ",
        "timeout_exits": [124, 137],
        "fail_tail": 4,
    },
}


def load(path):
    return toml_subset.load(path)


def root_of(cfg_path, cfg=None):
    """The consumer root: [project].root resolved against the config's dir."""
    import os
    cfg = cfg if cfg is not None else load(cfg_path)
    base = os.path.dirname(os.path.abspath(cfg_path))
    return os.path.normpath(os.path.join(base, get(cfg, "project.root")))


def get(cfg, dotted, default=None):
    """cfg['a']['b'] for 'a.b', falling back to DEFAULTS, then `default`."""
    parts = dotted.split(".")
    if len(parts) != 2:
        raise KeyError(f"a key is section.key, got {dotted!r}")
    sec, key = parts
    if sec in cfg and key in cfg[sec]:
        return cfg[sec][key]
    if sec in DEFAULTS and key in DEFAULTS[sec]:
        return DEFAULTS[sec][key]
    if default is not None:
        return default
    raise KeyError(dotted)


def _emit(v):
    if isinstance(v, bool):
        print("true" if v else "false")
    elif isinstance(v, list):
        for item in v:
            if isinstance(item, list):
                print("\t".join(str(x) for x in item))
            else:
                print(item)
    elif isinstance(v, dict):
        for k, x in v.items():
            print(f"{k}={x}")
    else:
        print(v)


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    path, cmd = argv[0], argv[1]
    try:
        cfg = load(path)
    except (OSError, toml_subset.SubsetError) as e:
        print(f"bbh config: {path}: {e}", file=sys.stderr)
        return 2
    if cmd == "root":
        print(root_of(path, cfg))
        return 0
    if cmd == "dump":
        for sec, tab in cfg.items():
            print(f"[{sec}]")
            for k, v in tab.items():
                print(f"{k} = {v!r}")
        return 0
    if cmd == "get":
        if len(argv) < 3:
            print("bbh config: get needs <section.key>", file=sys.stderr)
            return 2
        key = argv[2]
        default = None
        if len(argv) >= 5 and argv[3] == "--default":
            default = argv[4]
        try:
            _emit(get(cfg, key, default))
        except KeyError:
            print(f"bbh config: {path}: no value for '{key}' and no default", file=sys.stderr)
            return 3
        return 0
    print(f"bbh config: unknown command {cmd!r}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
