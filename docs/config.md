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

## `[sweep]` — the instrument-tier sweep (`bbh run-sweep`, H4)

The registry is `[registries].sweep`: `gate <TAB> lane <TAB> scope <TAB>
cadence <TAB> args <TAB> note [<TAB> timeout]`. The vocabularies of the
lane, scope and cadence columns are these keys.

| key | default | origin | meaning |
|---|---|---|---|
| `lanes` | `["prereq","fbneo","mame","mister"]` | config | every lane, in RUN ORDER; `--lane all` |
| `default_lanes` | `["prereq","fbneo","mame"]` | config | what runs with no `--lane` (the lineage's Verilator lane is opt-in) |
| `prereq_lane` | `"prereq"` | config | runs FIRST and serially; a red there STOPS the run (`--keep-going` overrides) |
| `release_scope` | `"release"` | config | the scope value that gates a release; any other value is `out` (never "do not run": `--scope all`) |
| `cadences` | `["romset","bitstream"]` | config | the cadence column's vocabulary |
| `freeze_cadence` | `"romset"` | config | what `--freeze` selects; the other cadences are DROPPED and NAMED |
| `cadence_drop_note` | the lineage's four lines | config | printed under the dropped list (an array of lines; `[]` = nothing) |
| `default_timeout` | `5400` | config | seconds per gate; a row's 7th column overrides it |
| `precondition` | `python3 tools/audit_roms.py "$ROMDIR" > /dev/null` | config | a command run before anything (`eval`); `""` = none |
| `precondition_fail_text` | `ROM audit FAILED — stop (CLAUDE.md §3)` | config | printed when it fails (exit 1) |
| `input_env` | `"ROMDIR"` | config | the reference-input variable; demanded (after `--list`), made absolute |
| `log_dir_prefix` | `"build/emu_sweep_"` | config | + a timestamp when `--log` is not given |
| `placeholders` | the lineage's five build dirs | config | `NAME = "dir"`: `%NAME%` in args; an environment variable `NAME` overrides the default |
| `rompath_placeholder_suffix` | `"_RP"` | code | `%NAME_RP%` = `%NAME%` + `rompath_suffix` |
| `rompath_suffix` | `"/rompath"` | config | the build dir's search-path subdirectory (`""` when the dir IS the search path) |
| `build_sets` | `["vsavjw","vsavj"]` | config | for the banner's fingerprint: the first set whose zip exists under the build's search path |
| `instruments` | the lineage's three | config | `[name, override variable, default path]` rows; `$HOME` and `$REPO` substituted; each printed with MISSING when not executable |
| `env_defaults` | `[["MAME_BIN","mame-wide"]]` | config | `[variable, instrument name]`: every gate receives the instrument's path unless the CALLER set the variable; the banner says which |
| `scratch_lanes` | `["mister"]` | config | lanes whose `--jobs` slots each get their own scratch: slot 0 the base, slot N `<base>-slotN` |
| `scratch_env` | `"JTSIM_SCRATCH"` | config | the variable carrying it; `""` disables |
| `scratch_default` | `"vampire-saved-jtsim"` | config | under `${TMPDIR:-/tmp}` when the variable is unset |
| `prereq_cite` | `"[CPE-24]"` | config | the citation in the prereq STOP text; `""` = none |

## `[gate_header]` — THE HEADER CONTRACT and THE GATE INDEX (`bbh gate-index`, H5)

Read by `lib/py/bbh/gate_header.py` (the one header parser) and
`gen_gate_index.py`. A gate's header is every `#` line after the shebang;
its FIRST PARAGRAPH (to the first bare `#`) opens `# <name>.sh — <claim>`
and is the index sentence (`docs/gate_contract.md` §3).

| key | default | origin | meaning |
|---|---|---|---|
| `title_sep_regex` | `\s*[—–-]+\s*` | code | what separates `<name>.sh` from the claim on line 2 |
| `session_regex` | the lineage's (`14z-N`, `M2a`, `session N`, a date) | config | `since` = the first match in the whole header; group 1 is the token |
| `duration_regex` | `~\s*(\d+(?:\.\d+)?)\s*(min\|s\b\|sec\|h\b\|hours?)` | code | the runtime a header quotes, appended to `needs` |
| `index_out` | `"docs/project/gate_index.md"` | config | the GENERATED index; `--check` compares a regeneration against it |
| `families_tsv` | `"tests/gate_index.tsv"` | config | `gate <TAB> family [<TAB> needs] [<TAB> since]` — the ONE hand-maintained input; complete both ways or `--check` fails |
| `families` | the lineage's ten | config | `[[name, description], …]` in the order the index groups them; a TSV family not here is a PROBLEM |
| `kinds` | `[["audit_","audit"],["run_","run"]]` | config | name prefix → `kind`; anything else is `test` |
| `needs_instruments` | the lineage's five (`verilator`/`jtsim`/`simulator` → Verilator, `mame`, `fbneo`) | config | header keyword (matched lowercased) → the instrument named in a derived `needs` |
| `needs_build_regex` | `build/\w\|build dir\|builddir\|<build>` | config | a header matching it needs "a build dir" |
| `index_preamble` | the lineage's opening lines | config | the index's opening prose, one array item per line (this is the consumer's text: what the index is, how to regenerate it) |

The tier labels are derived, not configured: the portable and static
registries' file stems (`ci_portable`, `ci_static`) and
`[project].instrument_word`; a static gate's derived `needs` is
`[registries].static_needs_env`.

## `[header_defaults]` — a header names the default its code uses (`bbh header-defaults`, H5)

| key | default | origin | meaning |
|---|---|---|---|
| `token_regex` | `build/[A-Za-z0-9_]+` | config | what a path default looks like |
| `claim_line_regex` | `usage\s*:\|defaults?\b` | code | a header line that presents itself as an invocation or a default — only those are checked |
| `verbatim_regex` | `\(verbatim[;,)]` | code | opens an ARCHIVE block, exempt until the next bare `#` line |
| `root_prefix_regex` | `(?:\$\{?REPO\}?/)?` | config | an optional root prefix before the token in a code default (`${1:-$REPO/build/x}`) |

Backticked tokens and a token followed by `<` (a template) are exempt by
code. `--fix` rewrites a mechanical mismatch when the code has exactly one
default and refuses to guess otherwise.

## `[ref_rot]` — a hard-coded path default must not have rotted (`bbh ref-rot`, H5)

| key | default | origin | meaning |
|---|---|---|---|
| `token_regex` | `build/[a-z0-9_]+` | config | the default's shape in CODE (the lineage's header and code regexes differ; both are kept) |
| `root_prefix_regex` | `(?:\$\{?REPO\}?/)?` | config | as above |
| `rompath_suffix` | `"/rompath"` | config | the subdirectory a script dereferences to read the image; a default is judged only if `$VAR<suffix>` appears in the body or the default itself ends in it; `""` = the dir is the image dir |
| `image_glob` | `"*.zip"` | config | what an image looks like inside it; none = "unbuilt" |
| `image_prefer` | `["vsavjw", "vsavj"]` | config | substrings, in order, choosing among several images; else the first by name (the lineage took directory order) |
| `stale_marker` | `["vsw.", "vsw.z01", "no vsw.z01 (pre-WIDE v1.1)"]` | config | `[member prefix, required member, reason]`: an image with any PREFIX member and no REQUIRED member is ROTTED |
| `predicate` | `""` | config | a command instead of the marker: `$1` = the image, print its one-line description, exit 0 live / 1 rotted |
| `family_regex` | `^([a-z]+)-m(\d+)$` | config | a registry set name → (family, generation) for the CURRENCY report; group 2 is an integer |
| `no_row_note` | the lineage's | config | the currency line for an image with no registry row |
| `rotted_advice` | the lineage's four lines | config | printed under a ROTTED verdict |

The registry is `[suite].registry` and the program key is
`[fingerprint]`'s. Currency is REPORTED, never failed; only ROTTED exits 1.

## `[provenance]` — every frozen expectation file says where its numbers came from (`bbh provenance`, H5)

| key | default | origin | meaning |
|---|---|---|---|
| `page` | `"tests/expected/PROVENANCE.md"` | config | the register: a table whose first cell is the `backticked` file name |
| `scope` | `[["tests/expected", ""], ["tests/expect", "expect/"]]` | config | `[dir, row prefix]`: the FILES directly under each dir (never subdirectories), named `prefix + file` in the page |
| `exclude` | `["PROVENANCE.md"]` | config | files in scope that are not expectations |
| `evidence_classes` | the lineage's seven | config (policy) | the CLOSED vocabulary a `rests on` cell must name (as a substring) |
| `rests_on_column` | `4` | config | which table column is `rests on` |

## `[project]` keys used by `lib/sh/shadow_tools.sh` (H5)

`tools_dir` and `shadow_link_dirs` reach the sh lib as `BBH_TOOLS_DIR` and
`BBH_SHADOW_LINK_DIRS` (space-separated), exported by a runner or set by
the gate; `REPO` or `BBH_ROOT` names the real root. `lib/sh/accounting.sh`
has no keys: it reads the classifier's `BBH_CLASSIFY_*`.

## `[fields]` — mapped fields at sync anchors, and dump completeness (`bbh compare-fields`, `bbh check-dumps`, H7)

The dual-implementation protocol: two implementations of one machine
traverse identical states on different frame indices, so the comparable
thing is the MAPPED state at anchors each side finds on its own. The
predicate and the bases were the one comparator's game facts in SOURCE in
the lineage; here they are the consumer's.

| key | default | origin | meaning |
|---|---|---|---|
| `table` | `"tests/fields_m2a.tsv"` | config | `name <TAB> base <TAB> addr <TAB> width [<TAB> phase [<TAB> note]]`; `--fields` overrides; the TSV may carry `# base <name>=<addr>` header lines that override `bases` |
| `dump_regex` | `(?:^\|\.)dump_(\d+)_([0-9a-fA-F]{6})\.bin$` | code | a dump file's name: group 1 the frame, group 2 the hex address (the driver contract's `dump_<frame>_<lo>.bin`; a driver-prefixed `<out>.dump_…` matches too) |
| `bases` | `{ p1 = 0xFF8400, p2 = 0xFF8800 }` | config | a field's `base` column names one of these; its address is added to `addr`; `abs` is always accepted |
| `anchor` | the lineage's four clauses | config (a game fact) | `[[address, width, value], …]`, all true = the anchor predicate; its debounced RISING EDGE is an anchor |
| `anchor_hint` | `dump $FF8000-$FF8300 and $FF8400-$FF8C00 windows` | config | printed when a predicate field is not covered by the dumps |
| `stable` | `30` | config (policy) | an edge counts only if the predicate holds this many frames (the lineage measured a transient true during round intros) |
| `settle` | `120` | config (policy) | `settled` fields are compared at offsets ≥ this (`--settle` overrides) |
| `integrity_hint` | the lineage's two lines | config | printed under `DUMP INTEGRITY FAILED` |

Section `[machine]` arrives with slice H6 and is documented here when it
lands.
