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

## `[thresholds]` — the comparison classes' numbers (H2)

Read by `lib/py/bbh/thresholds.py` through `BBH_CONFIG` and nowhere else;
every comparator and the proposer import from there. These are a
consumer's RATIFIED comparison policy, not a tuning knob: changing one is a
reviewed edit of the config.

| key | default | origin | meaning |
|---|---|---|---|
| `flicker_max` | `2` | config (policy) | a divergent run this short or shorter is a FLICKER frame |
| `reconverge` | `60` | config (policy) | identical frames required after the last divergence (the non-propagation proof; intra-mechanism) |
| `flicker_max_total` | `8` | config (policy) | the cap on a flicker INVENTORY; never applied to a window run |

## `[suite]` — the expectation tree and the suite runner (H2 reads three keys; H3 the rest)

| key | default | origin | meaning |
|---|---|---|---|
| `replays_dir` | `"tests/replays"` | config | where `<name>.rpl` lives; `enumerate_expectations` ignores a stem with no replay |
| `expected_dir` | `"tests/expected"` | config | the expectation tree: `<set>/<name>.{masked,skip,sha1,pending}`, `<set>/mask`, `<basis>/MASK`, `<basis>/logs/<name>.log` |
| `mask_default` | `"043c-043d,4182-41a2,7f00-8000"` | config | the mask a set without its own `mask` file runs under (offsets from the machine profile's RAM window base); exported to `masked_compare.sh` as `BBH_MASK_DEFAULT` |

The rest of `[suite]` is the SUITE RUNNER's (`bbh run-suite`, H3):

| key | default | origin | meaning |
|---|---|---|---|
| `registry` | `"tests/expected/registry.tsv"` | config | `sha1 <TAB> expectation-set <TAB> notes`; `#` comments; rows only at freeze time, as a build decision |
| `default_set` | `"vsavj"` | config | the set run when the command line names none |
| `driver` | `"tools/run_replay_mame.sh"` | config | a path from the consumer root, or a bare name = `drivers/<name>.sh` in the harness (`fake`, `mame`, …); `--driver` overrides |
| `runs_per_replay` | `2` | code (policy) | every replay is run this many times; any difference is NONDETERMINISTIC and a failure |
| `mask_env` | `"MASK_RANGES"` | code | the variable the driver reads the mask from (drivers/README.md) |
| `rompath_env` | `"MAME_ROMPATH"` | config | the driver's search-path variable; unset = `input_env`'s value |
| `input_env` | `"ROMDIR"` | config | the reference-input directory; demanded at the entrance and made absolute |
| `hermetic_unset` | the lineage's eight (`POKES DUMPS SNAP_FRAMES TAIL_FRAMES VIDEO_OUT INPUT_OUT INPUT_INJECT_TEST NO_INPUT_CHECK`) | code | scrubbed from the environment before any driver runs, so nothing from the caller's shell reaches a frozen log |
| `hash_cmd` | `"shasum"` | config | prints `<hex> <file>`; the `.sha1` kind's hash (`sha1sum` on Linux) |

## `[fingerprint]` — build identity → expectation set (H3)

Read by `lib/py/bbh/fingerprint.py` through `--config` or `BBH_CONFIG`.

| key | default | origin | meaning |
|---|---|---|---|
| `kind` | `"zip-members"` | config | `zip-members` (the set is `<set>.zip` on a `;` search path), `file-sha1` (one file), `command` (two commands print the keys) |
| `program_member_regex` | `\.(0[3-9]\|10\|4[1-4])[a-ln-z]?$` | config | which zip members are the PROGRAM; group 1 is the member's ORDER, an integer — the program key hashes them in that order |
| `parent_sets` | `["vsav"]` | config | set names whose images `--full` folds in along the search path (a clone set's parent) |
| `region_rules` | the lineage's five | config | `[[regex, region], …]` for `--full`'s per-region breakdown, first match wins; the pseudo-regex `@program` means "matches the program regex" |
| `region_default` | `"gfx/qsnd"` | config | the region of a member no rule names |
| `file_pattern` | `"{set}.bin"` | config | kind `file-sha1`: the image's file name |
| `program_command`, `wholeset_command` | `""` | config | kind `command`: shell commands printing the keys, `{rompath}` and `{set}` substituted |

Sections `[sweep]`, `[fields]`, `[gate_header]`, `[ref_rot]`,
`[provenance]`, `[machine]` arrive with slices H4-H7 and are documented
here as they land.
