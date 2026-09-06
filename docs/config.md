# The config — `bbh.toml`, every key, its default, and the bin it came from

One file per consumer. Paths are relative to the config file's directory,
unless `[project].root` moves the consumer root elsewhere (so a consumer
config may live OUTSIDE the tree it describes — `example/consumers/`). The
sh runners read it through `python3 -m bbh.config <file> get <section.key>`;
a missing key falls back to the default here, and a key with no default and
no `--default` is FATAL (exit 3): a runner never runs on an empty value
silently.

The reader is a TOML SUBSET (`lib/py/bbh/toml_subset.py`): tables, basic
and literal strings, integers, booleans, arrays (of scalars or of arrays of
scalars, possibly multi-line), inline tables of scalars. Dotted names,
arrays of tables, duplicate keys, floats, escapes and nested inline tables
are REFUSED — everything it accepts, `tomllib` reads identically
(`selftest/test_config.sh` proves it on a host that has one). Regexes go in
`'literal strings'`.

"Origin" says which bin the key came from when it was extracted:
**code** = the harness's own contract, not a consumer choice; **config** =
a literal the lineage carried in source that is a consumer VALUE.

## `[project]`

| key | default | origin | meaning |
|---|---|---|---|
| `root` | `"."` | config | the consumer tree, relative to the config file |
| `gates_dir` | `"tests"` | config | where the gates live |
| `gate_glob` | `"*.sh"` | config | what a gate file is called |
| `lib_dir` | `"tests/lib"` | config | sourced libs (H1 documents it; H5 uses it) |
| `runner_prefixes` | `["run_"]` | config | names the anti-orphan report ignores (runners) |
| `manual_suffixes` | `["_soak"]` | config | names it ignores (deliberately manual) |
| `tools_dir` | `"tools"` | config | for shadow tools (H5) |
| `shadow_link_dirs` | `["build","tests","docs"]` | config | dirs symlinked beside a shadow tool (H5) |
| `instrument_word` | `"emulator"` | config | the noun the reports use ("emulator-free gate") |

## `[registries]`

| key | default | origin | meaning |
|---|---|---|---|
| `portable` | `"tests/ci_portable.txt"` | config | gates a clean checkout can run; one name per line, `#` comments |
| `static` | `"tests/ci_static.txt"` | config | gates needing the reference input or a build dir, no instrument |
| `sweep` | `"tests/ci_emulator.tsv"` | config | the instrument-tier registry (H4) |
| `static_needs_env` | `"ROMDIR"` | config | the variable whose presence enables the static tier; its value is made ABSOLUTE at the entrance; `""` = always run |

## `[tier]` — the transitive "needs an instrument" classifier

| key | default | origin | meaning |
|---|---|---|---|
| `patterns` | the lineage's ten (MAME/FBNeo/Verilator wrappers and binary variables) | config | a gate whose comment-stripped body matches any NEEDS an instrument |
| `source_regex` | `^\s*\.\s+"?\$(?:REPO\|\{REPO\})"?/(tests/lib/[a-z0-9_]+\.sh)` | config | how a gate sources a lib; group 1 is the lib path from the root |
| `source_depth` | `2` | code | how far sourced libs are followed |

## `[classify]` — the verdict classifier

| key | default | origin | meaning |
|---|---|---|---|
| `skip_regex` | `^ *SKIP` | code | exit 0 + a line matching this = SKIP |
| `shell_error_regex` | `\.sh: line [0-9]+: [A-Za-z_][A-Za-z0-9_]*: ` | code | exit 0 + a line matching this = FAIL (a crash) |
| `timeout_exits` | `[124, 137]` | code | exits read as TIMEOUT (the timeout wrapper's) |
| `fail_tail` | `4` | config | lines of a failing gate's output shown (`FAIL_TAIL` env overrides) |

Sections `[sweep]`, `[suite]`, `[thresholds]`, `[fingerprint]`, `[fields]`,
`[gate_header]`, `[ref_rot]`, `[provenance]`, `[machine]` arrive with slices
H2-H7 and are documented here as they land.
