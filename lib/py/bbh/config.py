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
    # [skills] — the skills lock and the guide generator (H10). The table is
    # `prefixes` + one [skill_<PFX>] table each (docs/config.md); these are
    # the settings around it. The guide_header lines are the lineage's exact
    # text, so its committed guides regenerate byte-identical (fidelity F11).
    "skills": {
        "prefixes": [],                       # the skills, IN ORDER; each has a [skill_<PFX>] table
        "history_regex": r"_(history|HISTORY)\.md$",   # a LOG file matching this is a history twin: numbers resolve there, anchors may not live there
        "history_exempt": [],                 # logs matching the regex that are session ARCHIVES, not twins (the lineage: STATE_HISTORY.md, DECISIONS_HISTORY.md)
        "guided": [],                         # the skills with a GENERATED GUIDE.md beside SKILL.md
        "guide_origin": "",                   # substituted for {origin} in guide_header
        "guide_header": [                     # the guide's opening lines; {title} {name} {origin} substituted
            "# {title} — the guide", "",
            "The human rendition of `SKILL.md` in this directory: the same rules, the same",
            "IDs, each followed by the INCIDENT that taught it. **GENERATED** by",
            "`tools/gen_skill_guide.py` of the originating project from the documentation",
            "paragraph every rule is anchored to — never hand-edited; regenerate there.",
            "Origin: {origin}. The incidents therefore name that project's game, builds,",
            "gates and session tags (`14z-N`); the RULES do not. The rule is the reminder,",
            "the incident is the fact. IDs are stable and never reused; a gap means the",
            "rule stayed at the origin's board-specific level.", "",
            "**To use this skill elsewhere:** copy this directory (`SKILL.md` + `GUIDE.md`)",
            "into `~/.claude/skills/{name}/`. Nothing in it depends on the origin tree.", "",
        ],
    },
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
        # H3 — the suite runner (bin/bbh-run-suite)
        "registry": "tests/expected/registry.tsv",   # fingerprint -> expectation set
        "default_set": "vsavj",                      # the set run when none is named
        "driver": "tools/run_replay_mame.sh",        # a path from the root, or a bare harness driver name (drivers/<name>.sh)
        "runs_per_replay": 2,                        # every replay run this many times; any difference = NONDETERMINISTIC
        "mask_env": "MASK_RANGES",                   # the variable the driver reads the mask from
        "rompath_env": "MAME_ROMPATH",               # the variable naming the build's search path (falls back to input_env)
        "input_env": "ROMDIR",                       # the reference-input directory; demanded at the entrance
        "hermetic_unset": ["POKES", "DUMPS", "SNAP_FRAMES", "TAIL_FRAMES", "VIDEO_OUT",
                           "INPUT_OUT", "INPUT_INJECT_TEST", "NO_INPUT_CHECK"],
        "hash_cmd": "shasum",                        # prints "<hex> <file>"; sha1sum on Linux
    },
    "sweep": {
        # H4 — the instrument-tier sweep (bin/bbh-run-sweep); the lineage's literals
        "lanes": ["prereq", "fbneo", "mame", "mister"],   # every lane, in RUN ORDER
        "default_lanes": ["prereq", "fbneo", "mame"],     # what runs when no --lane is given
        "prereq_lane": "prereq",                          # runs first, serial; a red there stops the run
        "release_scope": "release",                       # the scope column's value that gates a release
        "cadences": ["romset", "bitstream"],              # the cadence column's vocabulary
        "freeze_cadence": "romset",                       # what --freeze selects (the rest are dropped, named)
        "cadence_drop_note": ["These follow the .rbf, not the romset (ruled 2026-09-03). A",
                              "RELEASE always runs them; this run does not.",
                              ">> IS THIS FREEZE TARGETING MiSTer? If yes, re-run with",
                              "   --cadence all --lane mister. If no, this is correct."],
        "default_timeout": 5400,                          # seconds per gate; a row's 7th column overrides
        "precondition": 'python3 tools/audit_roms.py "$ROMDIR" > /dev/null',   # a command; "" = none
        "precondition_fail_text": "ROM audit FAILED — stop (CLAUDE.md §3)",
        "input_env": "ROMDIR",                            # demanded, made absolute
        "log_dir_prefix": "build/emu_sweep_",             # + a timestamp
        "placeholders": {"MERGED": "build/m3b_merged23", "DON": "build/don_m20", "HUI": "build/hui54",
                         "PYR": "build/pyron38", "STOCK": "build/m5_stock15"},   # %NAME%; env NAME= overrides
        "rompath_placeholder_suffix": "_RP",              # %NAME_RP% = %NAME% + rompath_suffix
        "rompath_suffix": "/rompath",
        "build_sets": ["vsavjw", "vsavj"],                # the set fingerprinted: the first whose zip exists
        "instruments": [["mame-wide", "MAME_WIDE_BIN", "$HOME/.cache/vampire-saved/mame/cps2"],
                        ["mame-ref", "MAME_REF_BIN", "$HOME/.cache/vampire-saved/mame-ref/cps2"],
                        ["fbneo", "", "$REPO/emu/fbneo/fbneo"]],   # name, override variable, default path
        "env_defaults": [["MAME_BIN", "mame-wide"]],      # variable every gate receives unless the caller set it
        "scratch_lanes": ["mister"],                      # lanes whose --jobs slots get their own scratch
        "scratch_env": "JTSIM_SCRATCH",                   # the variable carrying it; "" = no scratch handling
        "scratch_default": "vampire-saved-jtsim",         # under ${TMPDIR:-/tmp} when the variable is unset
        "prereq_cite": "[CPE-24]",                        # the citation in the prereq STOP text — the lineage's rule ID ("a measurement taken after a moved instrument is not evidence"); a consumer names its own or sets ""
    },
    "fingerprint": {
        "kind": "zip-members",                       # zip-members | file-sha1 | command
        "program_member_regex": r"\.(0[3-9]|10|4[1-4])[a-ln-z]?$",   # group 1 = the member's order
        "parent_sets": ["vsav"],                     # images --full folds in along the search path
        "region_rules": [[r"\.key$", "key"], [r"\.0[12]$", "z80"],
                         [r"^vsw\..*m$", "gfx/qsnd"], [r"^vsw\.", "prg"],
                         ["@program", "prg"]],       # --full's per-region breakdown, first match wins; @program = the program regex
        "region_default": "gfx/qsnd",
        "file_pattern": "{set}.bin",                 # kind file-sha1: the image's name
        "program_command": "",                       # kind command: print the program key
        "wholeset_command": "",                      # kind command: print the whole-set key
    },
    "gate_header": {
        # H5 — THE HEADER CONTRACT and THE GATE INDEX (bbh gate-index); the lineage's literals
        "title_sep_regex": r"\s*[—–-]+\s*",       # between `<name>.sh` and the claim on line 2
        "session_regex": r"\b(14z-\d+[a-z]?(?:\s*\(\d+\))?|M[0-9][a-z]?\b|session \d+[a-z]?|20\d\d-\d\d-\d\d)",   # `since` = the first match in the header
        "duration_regex": r"~\s*(\d+(?:\.\d+)?)\s*(min|s\b|sec|h\b|hours?)",   # the runtime a header quotes
        "index_out": "docs/project/gate_index.md",   # the GENERATED index
        "families_tsv": "tests/gate_index.tsv",      # gate <TAB> family [<TAB> needs] [<TAB> since] — the one hand-maintained input
        "families": [["runner", "the suite runners and their own ground truth"],
                     ["docs", "the documentation locks — docs, skills, indexes, tables follow the tree"],
                     ["platform", "the emulators and the ROM images as instruments — builds, decrypt, replay determinism, harness hygiene"],
                     ["pipeline", "the build pipeline — manifests, patch ops, extraction/reconciliation/generation law, static censuses"],
                     ["oracle", "the CLAUDE.md §4 oracle classes — masked legacy, flicker/window/composite, dual-track, the recording corpus"],
                     ["gfx", "tiles, OBJ records, sprite lists, render-layer verdicts"],
                     ["tenant", "tenant content — per-character gates and on-demand audits on the ported characters"],
                     ["character-data", "the character-data map — move naming, hitboxes, reactions, projectiles, measured mechanics"],
                     ["review-triage", "the 14z-94 adversarial-review closures (GitHub #74's index) — every one a guard the review asked for"],
                     ["mister", "the MiSTer lane — the jtcps2w core, the simulation oracles, MRA/.rom generation"]],
        "kinds": [["audit_", "audit"], ["run_", "run"]],   # name prefix -> kind; anything else is "test"
        "needs_instruments": [["verilator", "Verilator"], ["jtsim", "Verilator"], ["simulator", "Verilator"],
                              ["mame", "MAME"], ["fbneo", "FBNeo"]],   # header keyword (lowercased) -> the instrument named in `needs`
        "needs_build_regex": r"build/\w|build dir|builddir|<build>",   # a header matching this needs "a build dir"
        "index_preamble": ["# The gate index (GENERATED)",
                           "",
                           "<!-- generated by tools/gen_gate_index.py — do not edit; regenerate -->",
                           "",
                           "**STATUS: GENERATED (14z-123).** One row per script under `tests/`, grouped by",
                           "family. The `locks` column is each script's OWN header sentence — the header",
                           "is the source of truth (the 14z-123 ruling: a gate's WHY lives in the gate);",
                           "`family` comes from `tests/gate_index.tsv`, the one hand-maintained input;",
                           "`tier` from `tests/ci_portable.txt` / `tests/ci_static.txt`. Regenerate with",
                           "`python3 tools/gen_gate_index.py`; `tests/test_gate_index_current.sh` fails",
                           "when this file is stale or a script has no family row.",
                           "",
                           "**How to run things** is HANDOFF.md \"How to test\": the portable tier is",
                           "`tests/run_all_static.sh` (ROM-free, ~1 min), `ROMDIR=... tests/run_all_static.sh",
                           "--strict` adds the static tier and makes SKIP fatal; emulator-tier gates and",
                           "audits are run by name with the `needs` shown here. HANDOFF's former per-gate",
                           "fence (as of 14z-123) is verbatim in `HANDOFF_HISTORY.md`."],   # the index's opening lines, the consumer's prose
    },
    "header_defaults": {
        # H5 — a gate's HEADER states the default its CODE uses (bbh header-defaults)
        "token_regex": r"build/[A-Za-z0-9_]+",              # what a path default looks like
        "claim_line_regex": r"usage\s*:|defaults?\b",        # a header line that presents itself as an invocation or a default
        "verbatim_regex": r"\(verbatim[;,)]",                # opens an ARCHIVE block (until the next bare `#`), exempt
        "root_prefix_regex": r"(?:\$\{?REPO\}?/)?",          # an optional root prefix before the token in a code default
    },
    "ref_rot": {
        # H5 — a hard-coded path default must not have ROTTED (bbh ref-rot)
        "token_regex": r"build/[a-z0-9_]+",                  # the default's shape in code (NOT the header's regex: the lineage's differ)
        "root_prefix_regex": r"(?:\$\{?REPO\}?/)?",
        "rompath_suffix": "/rompath",                        # the subdirectory a script dereferences to read the image ("" = the dir itself)
        "image_glob": "*.zip",                               # what an image looks like inside it
        "image_prefer": ["vsavjw", "vsavj"],                 # substrings, in order of preference, choosing among several images ([] = the first by name)
        "stale_marker": ["vsw.", "vsw.z01", "no vsw.z01 (pre-WIDE v1.1)"],   # [member prefix, required member, reason]: an image carrying any PREFIX member without REQUIRED is ROTTED
        "predicate": "",                                     # a command instead: `$1` = the image; prints its description; exit 0 live / 1 rotted
        "family_regex": r"^([a-z]+)-m(\d+)$",                # a registry set name -> (family, generation) for the CURRENCY report
        "no_row_note": "no registry row (by design for the blanks instrument; a merged build has one since B2; else a pre-freeze build)",
        "rotted_advice": ["A rotted default means the script cannot run at all: it dies before",
                          "measuring anything, and it says so only when somebody runs it.",
                          "Re-point it at a current build, or parameterise it the way",
                          "audit_merged_legacy.sh's leg (b) was at 14z-94."],
    },
    "provenance": {
        # H5 — every frozen expectation file says WHERE ITS NUMBERS CAME FROM (bbh provenance)
        "page": "tests/expected/PROVENANCE.md",              # the register: one table row per file, first cell the `backticked` name
        "scope": [["tests/expected", ""], ["tests/expect", "expect/"]],   # [dir, row prefix]: the FILES directly under each dir, named prefix+file
        "exclude": ["PROVENANCE.md"],                        # files in scope that are not expectations
        "evidence_classes": ["in-emulator (reference)", "in-emulator (ours)", "in-emulator (reference + ours)",
                             "derived", "static", "hash-lock", "registry"],   # the CLOSED vocabulary the `rests on` cell must name
        "rests_on_column": 4,                                # which table column carries the evidence class
    },
    "fields": {
        # H7 — mapped-field comparison at anchors (bbh compare-fields) and dump completeness (bbh check-dumps)
        "table": "tests/fields_m2a.tsv",              # name/base/addr/width[/phase[/note]] TSV; `# base p1=0x…` headers override `bases`
        "dump_regex": r"(?:^|\.)dump_(\d+)_([0-9a-fA-F]{6})\.bin$",   # group 1 the frame, group 2 the hex address
        "bases": {"p1": 0xFF8400, "p2": 0xFF8800},    # base name -> address added to a field's addr (the lineage's player blocks)
        "anchor": [[0xFF8004, 4, 0x40000], [0xFF8008, 4, 0x40000],
                   [0xFF8450, 2, 0x120], [0xFF8850, 2, 0x120]],   # [address, width, value] clauses, all true = the anchor predicate (match start)
        "anchor_hint": "dump $FF8000-$FF8300 and $FF8400-$FF8C00 windows",   # what to dump when a predicate field is not covered
        "stable": 30,                                 # debounce: an edge counts only if the predicate holds this many frames
        "settle": 120,                                # the offset at/after which `settled` fields are compared
        "integrity_hint": ["A glob-based comparison would have silently used a DIFFERENT",
                           "frame set. Do not compare this run — see docs/platform/gotchas.md."],   # under a DUMP INTEGRITY FAILED
    },
    "machine": {
        # H6 — the MAME Lua layer: which machine profile the drivers run under.
        # NO DEFAULT for `profile` (H6b): a board is never implied — a consumer
        # names one, or the section is absent and BBH_PROFILE comes from the
        # caller (drivers refuse to run without one).
    },
    "inp": {
        # H6 — the recording corpus (bbh inp-corpus / bbh inp-play); the lineage's literals
        "corpus_dir": "tests/inp",                    # <corpus_dir>/<name>/{<name>.inp, nvram/, NOTE, DEFECT?}
        "set": "vsavjw",                              # the set the recordings were played on
        "build": "build/m3b_merged23",                # the build dir under test (env BUILD / --build override)
        "rompath_suffix": "/rompath",                 # + the build dir = the search path's first component
        "profile": "",                               # the playback guard's profile; "" = [machine].profile, else BBH_PROFILE from the caller
        "mame_bin_default": "$HOME/.cache/vampire-saved/mame/cps2",   # MAME_BIN when the caller set none
        "max_frames": 6000,                           # MAX_FRAMES: the playback cap
        "stop_after": 5,                              # STOP_AFTER: frames after the first crash
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


def consumer(config_path=None, root=None):
    """(cfg, root) for a tool: the config from `config_path`, else $BBH_CONFIG,
    else {} (every key at its default); the root from `root` when given, else
    [project].root resolved against the config, else the working directory."""
    import os
    path = config_path or os.environ.get("BBH_CONFIG")
    if path and os.path.isfile(path):
        cfg = load(path)
        r = root or root_of(path, cfg)
    else:
        cfg = {}
        r = root or os.getcwd()
    return cfg, os.path.abspath(r)


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
