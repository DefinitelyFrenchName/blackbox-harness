# Expectation and gate hygiene — the checks that keep a suite honest between runs

A suite rots in ways no gate run can see: a frozen number nobody can say
the origin of, a header telling the reader to run a default the code no
longer uses, a code default pointing at an image that is too old to load,
an index that drifted from the tree, a "GREEN" printed over a third of the
gates that never ran, a perturbation control that edited the tracked tool.
Each of these was paid for once in the lineage (Project VAMPIRE SAVED) and
each is one check here. They are ROM-free and instrument-free; a consumer
runs them in one portable gate (`example/tests/g_hygiene.sh` is the shape).

| check | what it locks | the incident it exists for |
|---|---|---|
| `bbh provenance` | every frozen expectation FILE has a row in a register naming what it describes, a CLOSED evidence class it rests on, and how to re-freeze it; complete both ways | a gate was GREEN on a constant of playtest testimony presented as measured; it happened to be right — luck, not method. A red gate is a QUESTION whose first question is which side rests on a measurement, and the FILE is what a triage opens |
| `bbh header-defaults` | every path default on a header's `Usage:` / "default" line is one the CODE sets (`--fix` repairs the mechanical ones) | 37 headers told the reader to pass a build dir pruned three freezes earlier; the gate index is generated FROM those headers |
| `bbh ref-rot` | a hard-coded path default the script READS as an image has not rotted (exists but is too old); absent is not rotted; CURRENCY (a superseded registered image) is reported and never failed | four audits died on a pruned default months after anyone ran them; a battery judged today's build against a set five generations back and was green for weeks |
| `bbh gate-index` | the gate index is GENERATED from every gate's own header plus one hand-maintained family TSV, complete both ways; `--check` in a gate | a 2,160-line hand-written fence indexed 168 of 281 scripts, one twice, with comments the scripts' headers lacked |
| `lib/sh/accounting.sh` | a battery cannot print GREEN while a gate self-skipped; a FAIL, a shell error read as exit 0, or a timeout stops it and names the gate | nine of ~24 gates never ran on a machine without the instrument and the script still printed BATTERY GREEN |
| `lib/sh/shadow_tools.sh` | a perturbation control edits a COPY under a shadow root whose siblings are symlinks; the tracked tool is never written | controls edited the tracked generator in place and restored on an exit trap — which covers Ctrl-C and nothing else |
| `bbh demand-after-trap` (H1) | no `${VAR:?}` demand after an EXIT trap | a 65-minute gate recorded `PASS 0s` |
| `bbh check-skills` / `bbh skill-guide` (H10) | a SKILL (an agent-facing distillation of the docs, loaded BEFORE the work) is ID-locked to the paragraphs it distils, both ways; it names no forbidden token; every number it quotes is in a log; its cross-references resolve; its GUIDE.md is GENERATED from the anchored paragraphs and `--check`ed | the lineage's first skill run found five figures the skills needed that no log carried, and a stale skill is a confidently wrong instruction |

## The register (`bbh provenance`)

A markdown table under `[provenance].page`; the first cell is the file's
`backticked` name (with the scope dir's row prefix, e.g. `expect/x.txt`),
the `rests on` column names one of `[provenance].evidence_classes`. The
lineage's vocabulary, which is a POLICY and not a format:

- `in-emulator (reference)` — produced by running a REFERENCE and reading
  its own state. The strongest class: the number is what the reference DOES.
- `in-emulator (ours)` — produced by running OUR build. Locks CURRENCY,
  not correctness: a candidate for re-anchoring, never a finished
  measurement (the ruled precedence there: an explicit ruling > the vanilla
  reference > the donor reference; a build of ours is nowhere in it).
- `derived` — computed from the image by a tool; only as good as the reader.
- `static` — read off the image or the tree without running anything.
- `hash-lock` — a digest of generator output; locks CURRENCY, never
  correctness.
- `registry` — a ledger of decisions, not a measurement.

Files with no re-freeze path are hand-maintained, and changing one is a
decision. Directories are out of scope by design: a per-build expectation
SET's provenance is the registry row plus whatever the consumer freezes it
with, and two checks on one claim is one too many.

## The header contract these read (`docs/gate_contract.md` §3)

One parser, `lib/py/bbh/gate_header.py`: the `#` lines after the shebang;
the first paragraph (to the first bare `#`) as the index sentence; the
whole block for the runtime, the session token and the `Usage:` line.
Every regex is `[gate_header]` (`docs/config.md`). A consumer with another
comment style gets nothing from these three checks and loses nothing
else: the runners read names, exit statuses and output, never headers.

## Rot vs currency (`bbh ref-rot`)

ROTTED = present, read as an image, too old to carry what the reader
needs — the consumer's `[ref_rot].stale_marker` (a member prefix that
implies a required member) or a `predicate` command. It is the one thing
this check FAILS on. Absent is "unbuilt here" and never a failure (a clean
checkout has no build dirs). A default the script reads for another
purpose (its extract dir, its patch dir) is not judged — a check that cries
wolf about a working reference is one people switch off.

CURRENCY is the other question: the image loads, and is it the generation
the gate meant? The report fingerprints each referenced image, looks its
set up in `[suite].registry`, compares it against the newest generation of
its family (`family_regex`), and lists families referenced at more than
one generation. A superseded reference is often CORRECT — the pre-fix
build in an A/B audit, a known-bad ground truth — and only the gate's
author knows which, so it is a triage worksheet, never a verdict.

## Fidelity

`selftest/test_fidelity_vampire.sh` F9 runs each of these with the
lineage's consumer config against the lineage's own tools over the lineage
tree, full stdout and exit status diffed: identical at H5.
