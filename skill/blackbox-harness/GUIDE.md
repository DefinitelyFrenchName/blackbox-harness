# The black-box harness discipline (level 0, project-agnostic) — the guide

The human rendition of `SKILL.md` in this directory: the same rules, the same
IDs, each followed by the INCIDENT that taught it. **GENERATED** by
`bbh skill-guide` from the documentation paragraph every rule is anchored
to — never hand-edited; regenerate in the harness. Origin: the blackbox-harness repository (bbh), itself extracted from an arcade ROM hack with 304 gates and 4,000 frozen expectations. The
incidents may name that lineage; the RULES name no project, no board and no
game. The rule is the reminder, the incident is the fact. IDs are stable and
never reused.

**To use this skill elsewhere:** symlink or copy this directory (`SKILL.md` +
`GUIDE.md`) into `~/.claude/skills/blackbox-harness/`. Nothing in it depends on the
harness tree at load time.

## 1. The doctrine

**[BBH-1]** **The extraction question decides every bin.** A piece belongs to the harness only if it would still be true were the thing under test not this image, not this board, not even a game: what survives is CODE; what a consumer must DECLARE (a path, a regex naming its instruments, a threshold it ratified) is CONFIG; what is true of one CPU or board is a MACHINE PROFILE; what is true of one system STAYS with that consumer. The bins are why a consumer can adopt the harness without inheriting anyone's game.

> **Incident** (`docs/doctrine.md` › *1. The extraction question, and the four bins*):
>
> Everything here passed one test, asked of every piece of the lineage's
> harness: *would this still be true if the thing under test were not that
> ROM, not that board, not even a game?* What survived is CODE (true for
> anything: the classifier, the runners, the grammars, the comparison
> classes, the driver contract); what a consumer must DECLARE is CONFIG (a
> path, a regex naming its instruments, a threshold it ratified); what is
> true of one CPU or board is a MACHINE PROFILE (one table per board); and
> what is true of one system only STAYS with that consumer. The bins are not
> a filing convention: they are the reason a consumer can adopt the harness
> without inheriting the lineage's game.

**[BBH-2]** **No untested change survives.** Every change to a gate, a driver, a comparator or an expectation is run through the harness before it is committed; "it should be equivalent" is not a test result. The harness's own gate chain is classified by the same classifier its runners use, and a change to any lifted piece re-runs the fidelity checks beside the originals.

> **Incident** (`docs/doctrine.md` › *2. The seven sentences*):
>
> **No untested change survives.** Every change to a gate, a driver, a
> comparator or an expectation is run through the harness before it is
> committed — "it should be equivalent" is not a test result. The lineage
> inherited this from an earlier project where systematic in-emulator
> verification was the difference between working and shipping. Mechanism:
> the harness's own gate chain (`selftest/run.sh`) is classified by the same
> classifier the runners use, and the fidelity checks re-run the lineage's
> tools beside this harness's on every change to a lifted piece.

**[BBH-3]** **Every in-instrument measurement becomes a rerunnable case before the session ends.** A probe, a sanity check, a "let me just look" is captured as a scripted gate; the suite only grows, and the registries' anti-orphan reports name every gate that exists and is registered nowhere.

> **Incident** (`docs/doctrine.md` › *2. The seven sentences*):
>
> **Every in-instrument measurement becomes a rerunnable case.** A probe run
> during development — a measurement, a sanity check, a "let me just look" —
> is captured as a scripted gate before the session ends; the suite only
> grows. The lineage's most valuable artifact is that suite, above every
> unit test. Mechanism: the registries (`docs/gate_contract.md` §6) and the
> anti-orphan reports of `bbh run-static` and `bbh run-sweep`, which name
> every gate that exists and is registered nowhere.

**[BBH-4]** **Verdict logic is itself tested, in both directions.** A classifier's verdicts are validated against known ground-truth cases before they are trusted — a gate born against a live defect has never exercised PASS — and every selftest carries a MUST-FIRE control; a control that passes for the wrong reason is itself a failure.

> **Incident** (`docs/doctrine.md` › *2. The seven sentences*):
>
> **Verdict logic is itself tested.** A classifier's verdicts are validated
> against known ground-truth cases before they are trusted, in BOTH
> directions — a gate born against a live defect has never exercised PASS.
> The lineage's predecessor shipped a wrong conclusion from a verdict bug,
> not a game bug. Mechanism: every selftest here carries a MUST-FIRE control
> (`docs/gate_contract.md` §5) — an input perturbed so the check must fail
> for the stated reason — and a control that passes for the wrong reason is
> itself a failure.

**[BBH-5]** **A field report is a RECORDING before it is a theory.** A reproducible crash is captured first as the machine's own input recording with the fresh state it started from and replayed under a guard at every freeze; mechanism theories come after, because a win-fast rig never gives the system time to reach the path that crashes in the field.

> **Incident** (`docs/doctrine.md` › *2. The seven sentences*):
>
> **A field report is a RECORDING before it is a theory.** A reproducible
> crash a human can produce is captured first as the machine's own input
> recording with the fresh state it started from, and replayed under a guard
> at every freeze; mechanism theories come after. The lineage spent three
> sessions and two shipped fixes on a rig-derived mechanism that was never
> the field crash; the first hand-played recording found the real one in an
> evening, because a win-fast rig never gives an AI opponent time to reach
> its rarer scripts. Mechanism: `bbh inp-play`, `bbh inp-corpus` and the
> recording guard (`docs/lua.md` §4), with a liveness predicate so a dead
> playback is never read as clean.

**[BBH-6]** **SKIP is not PASS.** A gate whose inputs are absent prints a `SKIP:` line and exits 0, and counting that as a pass is how a clean checkout that runs a fraction of its gates reports itself green: exit status decides first, the marker is read only on exit 0, `--strict` makes a skip fatal, and ONE classifier — sourced by every runner — decides, because two copies of it DIFFER.

> **Incident** (`docs/doctrine.md` › *2. The seven sentences*):
>
> **SKIP is not PASS.** A gate whose inputs are absent prints a `SKIP:` line
> and exits 0; counting that as a pass is how a clean checkout that runs 3%
> of its gates reports itself green. Exit status decides first, the SKIP
> marker is read only on exit 0, and `--strict` makes a skip fatal.
> Mechanism: `lib/sh/classify.sh` — the ONE classifier, sourced by every
> runner, because the lineage carried two copies that DIFFERED and a crash
> read PASS under one of them for five sessions.

**[BBH-7]** **A red gate is a QUESTION whose first question is which side rests on a measurement.** Before choosing fix-the-gate, fix-what-it-caught or delete, establish which side's expectation was MEASURED; a frozen number whose provenance cannot be named is a claim with a number in it, and a gate can be green on a constant of testimony by luck.

> **Incident** (`docs/doctrine.md` › *2. The seven sentences*):
>
> **A red gate is a QUESTION whose first question is which side rests on a
> measurement.** Before choosing fix-the-gate / fix-what-it-caught / delete,
> establish which side's expectation was MEASURED; a frozen number whose
> provenance cannot be named is a claim with a number in it. The lineage
> found a gate green on a constant of playtest testimony presented as
> measured — right by luck. Mechanism: `bbh provenance` (`docs/hygiene.md`)
> demands a row with a CLOSED evidence class for every frozen expectation
> file, complete both ways.

**[BBH-8]** **When a claim changes, grep for the claim.** A finding propagates into headers, summary lines, registry rows and comments, and the copies outlive the correction: grep the wording and its paraphrases across the whole tree, fix the header and the summary line first, keep the superseded text marked with what replaced it, re-grep and show the empty result.

> **Incident** (`docs/doctrine.md` › *2. The seven sentences*):
>
> **When a claim changes, grep for the claim.** A finding does not live in
> one place: it propagates into headers, summary lines, registry rows and
> gate comments, and the copies outlive the correction. Fixing "where I
> remember writing it" is how a document asserts the opposite of the
> subsection beneath it. The procedure: grep the wording and its paraphrases
> across the whole tree, fix the header and the summary line first, keep
> the superseded text marked with what replaced it, re-grep and show the
> empty result. Mechanism: none can replace the grep; what the harness adds
> is that a stale claim about a VERDICT is loud — a re-baseline of the
> fidelity contract is a dated line every run prints (`docs/rebaselines.md`).

**[BBH-9]** **The docs stay LEAN and are searched by KEY; the complete LOG lives in `<name>_history.md` twins.** A reference page carries one rule per paragraph, anchored with a stable ID where a skill distils it; the dated measurements, superseded figures and incident narratives live in the page's twin, which carries no anchor and which the skills lock reads as a log. The page says what is true, the twin says how it came to be known, and nothing is deleted from either.

> **Incident** (`docs/doctrine.md` › *3. The documentation convention (ruled by the lineage's maintainer, 2026-09-07)*):
>
> The docs stay LEAN and are searched by KEY: a reference page carries one
> rule per paragraph, and a rule that a skill distils is ANCHORED there with
> a stable ID (`**[BBH-N]**`) at the paragraph that records it, so the skill,
> the page and the guide generated from the page cannot drift apart
> (`docs/hygiene.md`, the skills lock). The complete LOG — dated
> measurements, superseded figures, the narrative of an incident — lives in
> the page's `<name>_history.md` twin, never in the page: a twin carries no
> anchor, and the lock reads it as a log (a number a skill quotes must
> appear in a page or its twin). Two records and one rule: the page says
> what is true, the twin says how it came to be known, and nothing is
> deleted from either — a corrected claim is marked in place with what
> replaced it.

**[BBH-10]** **The doctrine is not a tuning guide and not a claim about correctness.** Thresholds, masks, evidence classes and scopes are the consumer's RATIFIED policy, and the harness makes a change to any of them a reviewed edit rather than a knob turned to make a red green; it proves that a system behaves as its frozen reference did under the classes its consumer ratified — which side of a red is right is the question it makes askable, not the one it answers.

> **Incident** (`docs/doctrine.md` › *5. What the doctrine is not*):
>
> It is not a tuning guide. The thresholds, the masks, the evidence classes
> and the scopes are the consumer's RATIFIED policy (`docs/config.md`), and
> the harness's job is to make a change to any of them a reviewed edit
> rather than a knob turned to make a red green. And it is not a claim about
> correctness: the harness proves that a system under test behaves as its
> frozen reference did, under the classes its consumer ratified — which
> side of a red is right is the question it makes askable, not the one it
> answers.

## 2. The gate contract

**[BBH-11]** **The runners read a gate's NAME, EXIT STATUS and OUTPUT — never its code.** The contract is what makes those three mean the same thing in every gate; a runner that read code to decide a verdict would be a second implementation of every gate.

> **Incident** (`docs/gate_contract.md` › *The gate contract — what a gate looks like so the runners can read it*):
>
> A GATE is one executable script under the consumer's gates dir (default
> `tests/*.sh`). The runners do not read its code; they read its NAME, its
> EXIT STATUS and its OUTPUT. The contract is what makes those three mean the
> same thing in every gate.

**[BBH-12]** **Exit status decides FIRST.** A non-zero exit is FAIL whatever the gate printed — a `SKIP:` line plus a non-zero exit is a gate that ran, could not complete, and said so; an exit-status-second classifier once downgraded the one gate that justified modifying an emulator to a benign skip.

> **Incident** (`docs/gate_contract.md` › *1. The verdict contract (what `bbh run-static` and `bbh run-sweep` read)*):
>
> | exits non-zero | **FAIL** — whatever it printed. A `SKIP:` line plus a non-zero exit is a FAILURE: the gate ran, could not complete, and said so. |

**[BBH-13]** **The timeout wrapper's exits are TIMEOUT, never FAIL,** so a killed gate is not read as a defect in the artifact; a red that is a cap, not a finding, is answered by measuring the gate's runtime and giving it its own timeout.

> **Incident** (`docs/gate_contract.md` › *1. The verdict contract (what `bbh run-static` and `bbh run-sweep` read)*):
>
> | exits 124 or 137 (the timeout wrapper's) | **TIMEOUT** — never FAIL, so a killed gate is not read as a defect in the artifact. |

**[BBH-14]** **Exit 0 after the shell's OWN error line is a CRASH, not a PASS.** Some shells return 0 for a parameter abort once an EXIT trap is armed, and a long gate was recorded as passing in zero seconds on four lines of log; the classifier reads `<script>: line N: NAME: message` as FAIL, while an instrument's teardown segfault line — digits where the NAME would be — stays benign.

> **Incident** (`docs/gate_contract.md` › *1. The verdict contract (what `bbh run-static` and `bbh run-sweep` read)*):
>
> | exits 0 and its output carries the shell's own `<script>.sh: line N: NAME: message` | **FAIL** — "exit 0 after a shell error". macOS bash 3.2 exits 0 for a `${VAR:?}` abort once an EXIT trap is armed; a 65-minute gate was once recorded `PASS 0s` on four lines of log. A driver's teardown segfault line (`line N:  <pid> Segmentation fault`) has digits where the NAME would be and is not this. |

**[BBH-15]** **The SKIP marker is a line matching the skip regex on exit 0, and the word SKIP in PROSE is not a marker;** a gate that documents the skip convention in its output must still count as PASS.

> **Incident** (`docs/gate_contract.md` › *1. The verdict contract (what `bbh run-static` and `bbh run-sweep` read)*):
>
> | exits 0 and prints a line matching `^ *SKIP` | **SKIP** — the reason is that line. The word SKIP in PROSE is not a marker. |

**[BBH-16]** **`--strict` makes SKIP fatal:** a skipped gate asserts NOTHING, and a checkout that skips most of its gates and reports green is its own false green; at release, anything red and anything skipped is a hard fail unless explicitly approved at release time.

> **Incident** (`docs/gate_contract.md` › *1. The verdict contract (what `bbh run-static` and `bbh run-sweep` read)*):
>
> Both regexes and the exit list are the consumer's `[classify]` section.
> `--strict` makes SKIP fatal: a skipped gate asserts NOTHING, and a clean
> checkout that skips 97% of its gates and reports green is its own false
> green.

**[BBH-17]** **A demand is placed BEFORE any trap, and after a trap is armed a demand is an EXPLICIT TEST, never a parameter abort** — `[ -n "${X:-}" ] || { echo "FAIL: set X"; exit 1; }` — and the demand-after-trap lint bars the forbidden shape.

> **Incident** (`docs/gate_contract.md` › *Usage: tests/<name>.sh [ARGS]    (a header names the default the CODE uses)*):
>
> After the trap is armed, a demand is an EXPLICIT TEST, never `${VAR:?}`:

**[BBH-18]** **Line 2 of a gate is an API:** `# <name>.sh — <claim>`, the header continuing to the first bare `#` line, read by the index generator as the gate's index sentence — written as the CLAIM the gate locks, never a description of its mechanics.

> **Incident** (`docs/gate_contract.md` › *3. The header (line 2 is an API)*):
>
> Line 1 is `#!/bin/sh`. Line 2 is `# <name>.sh — <claim>`, and the header
> continues until the first bare `#` line. The gate index generator (`bbh
> gate-index`) reads exactly that first paragraph as the gate's index
> sentence, so it is written as the CLAIM the gate locks, not as a description
> of its mechanics. A `Usage:` line names the gate's defaults, and the
> header-defaults check (`bbh header-defaults`) asserts every path default the
> header shows is one the CODE uses — a header that says `build/m11` while the
> code says `build/m21` is how a reader runs the wrong measurement. The
> parser is one module, `lib/py/bbh/gate_header.py`; the checks that read
> the header are `docs/hygiene.md`.

**[BBH-19]** **A header names the default its CODE uses.** A `Usage:` line that says one build while the code says another is how a reader runs the wrong measurement; the header-defaults check asserts every path default the header shows is one the code sets.

> **Incident** (`docs/hygiene.md` › *Expectation and gate hygiene — the checks that keep a suite honest between runs*):
>
> | `bbh header-defaults` | every path default on a header's `Usage:` / "default" line is one the CODE sets (`--fix` repairs the mechanical ones) | 37 headers told the reader to pass a build dir pruned three freezes earlier; the gate index is generated FROM those headers |

**[BBH-20]** **A gate ends with ONE verdict line of its own** — `PASS: <what held>` or `FAIL: <what did not>` — and a PASS row whose log has no verdict line of the gate's own is read as a crash until proven otherwise.

> **Incident** (`docs/gate_contract.md` › *4. The output (one verdict line of the gate's own)*):
>
> A gate prints its findings and ends with ONE line that states its verdict
> in its own words — `PASS: <what held>` or `FAIL: <what did not>`. The runner
> does not grep for those words (it reads the exit status), but a human
> reading a log does, and a PASS row whose log has NO verdict line of the
> gate's own is read as a crash until proven otherwise.

**[BBH-21]** **Every gate that asserts a property carries a MUST-FIRE control** in one of three shapes — perturb one byte of a copied artifact, a shadow copy of a tool with a line stripped, a synthetic tree or a known-bad reference — and requires its own check to fail for the stated reason; a dead control refuses a verdict.

> **Incident** (`docs/gate_contract.md` › *5. The must-fire control (a check that cannot fail is not a check)*):
>
> Every gate that asserts a property PERTURBS an input and requires its own
> check to fail for the stated reason. Three shapes, in order of how often
> they fit:

**[BBH-88]** **A control is DECLARED as one header line in one grammar, and four regexes are its only reader:** `# MUST-FIRE: <shape>: <name> — <what must fail>` (shape `perturbed-copy` | `shadow-tool` | `known-bad`, name `[a-z0-9-]+`, the em dash) in the leading comment block, a bare `#` continuing it; a malformed line or one below the first code line declares NOTHING, and a gate that asserts nothing says `# MUST-FIRE: none — <why>` so silence is distinguishable from omission.

> **Incident** (`docs/gate_contract.md` › *5.1 The declaration (the header line the runners read)*):
>
> A control is DECLARED as one line in the gate's HEADER — the leading
> comment block, every `#` line after the shebang up to the first non-comment
> line, a bare `#` continuing it — in exactly this grammar, and the four
> regexes of `lib/sh/controls.sh` are the only reader:

**[BBH-89]** **A declared control that did not print `CONTROL FIRED: <name>` at column 0, a `CONTROL DEAD:` line, or a firing no header declares is plain FAIL — no fourth verdict;** the classifier reads the gate SCRIPT beside the log, an undeclared gate is counted and never failed, and SKIP and FAIL are never touched.

> **Incident** (`docs/gate_contract.md` › *5.2 The firing (what the classifier compares)*):
>
> When a declared control fails for its stated reason the gate prints, at
> column 0, `CONTROL FIRED: <name> — <evidence>`; when it does not — it
> passed, or failed for another reason — `CONTROL DEAD: <name> — <what
> happened>`. An indented line is prose. Every runner hands the classifier
> the gate SCRIPT beside the log (`bbh_classify <exit> <log> <width> <script>`),
> and for a PASSING gate the classifier compares declared against fired: a
> declared control that did not fire, a `CONTROL DEAD:` line, or a firing no
> header declares turns the verdict into plain **FAIL** — there is no fourth
> verdict, and the FAIL row names it (`controls RED: <name>(not fired)`). A
> gate with no declaration is left alone and COUNTED as undeclared (a
> consumer's gates may predate the grammar); a `none` declaration is counted
> as such. SKIP and FAIL are never touched: a skipped gate ran nothing, a
> failed gate is already red.

**[BBH-90]** **`CONTROL FIRED` is a self-report, so every declared name is also a MODE:** `CONTROL=<name> <gate>` applies the perturbation to the REAL input and must reach the gate's own FAIL — HONOURED; exit 0 or a SKIP is LIES, a `REFUSED: CONTROL=` line (exit 3, the gate's answer to a name it does not declare or a prerequisite the host lacks) is a dead mode, a crash is DIED — and a gate never uses `CONTROL` as its own variable.

> **Incident** (`docs/gate_contract.md` › *5.3 The executable form (`CONTROL=<name>`)*):
>
> `CONTROL FIRED` is the gate's SELF-report, and a control can print it while
> testing nothing — it wrote a value and asserted the value was not something
> else. So a declared name is also a MODE: `CONTROL=<name> tests/<gate>.sh`
> applies that control's perturbation to the gate's REAL input and runs to the
> gate's OWN verdict, which must be FAIL. The gate announces the mode
> (`CONTROL MODE: <name> — …`, `bbh_ctl_mode "$0"`) and REFUSES a name its
> header does not declare (`REFUSED: CONTROL=<name> is not a mode of this
> gate`, exit 3). The runner's verdict on a control run (`bbh_classify_control`,
> one copy, so no runner carries a second shell-error regex):

**[BBH-91]** **One `perturb` function serves the control section and the mode,** so what the mode proves is what the control claims; the static runner executes every declared control after a PASS by default (`--exec-controls none` to iterate) and prints the fired/declared and executed readout only when a tier declared or executed anything, and the sweep executes under `--controls` as `<gate>@<name>` rows on the consumer's release cadence.

> **Incident** (`docs/gate_contract.md` › *5.4 The pattern, and the runners*):
>
> Write each perturbation as ONE function the control section and the mode
> both call (`perturb <name> <copy>`); under the mode the perturbed copy
> becomes the INPUT the main check reads, while the control section still
> builds its own copy and prints the FIRED/DEAD line — so what the mode
> proves is exactly what the control claims, and the two cannot drift.
> `bbh run-static` reads every gate's block for free and EXECUTES each declared
> control after a PASS (`--exec-controls all|portable|none`, default `all`,
> because a lying control must not pass a pre-commit; `none` is the
> developer's iteration knob), printing a readout — `fired N / declared N`,
> the none and undeclared counts, `executed N honoured N lies N refused N
> died N` — only when the tier declared or executed anything, so a consumer
> that has not adopted the grammar sees the runner it always had, byte for
> byte. `bbh run-sweep` reads every block on every run and executes under
> `--controls` (one more row per declared name, `<gate>@<name>`, PASS =
> honoured, in the tally and under `--strict`); it is off by default because
> it multiplies a tier measured in hours, and when it runs is the consumer's
> release policy. `example/tests/g_control.sh` is the worked instance; the
> ground truth is `selftest/test_controls.sh` with the runners' selftests.

**[BBH-22]** **A gate that is in no registry is not run.** Instrument-free gates are in the portable or the static registry, instrument gates in the sweep registry, and the runners report every gate in neither and every registered gate that no longer exists: the anti-orphan report is the mechanism, and without it a runner is a smaller thing to forget to update.

> **Incident** (`docs/gate_contract.md` › *6. Registration (a gate that is not in a registry is not run)*):
>
> A gate that needs no instrument is in `ci_portable.txt` (runs on a clean
> checkout) or `ci_static.txt` (needs the input the consumer names in
> `[registries].static_needs_env`, or a build dir, but no instrument). A gate
> that reaches an instrument — directly, or through a sourced lib — belongs to
> the sweep registry (H4) and to neither plain one. `bbh run-static` reports
> every instrument-free gate that is in neither; `bbh run-sweep --strict`
> fails on an unregistered instrument gate and on a registered gate that no
> longer exists. That report is the anti-orphan mechanism: without it a runner
> is just a smaller thing to forget to update.

**[BBH-23]** **Whether a gate reaches an instrument is decided TRANSITIVELY**, through the libs it sources, because a gate that reaches the instrument only through a sourced lib was once reported static and ran for minutes inside a chain advertised as instrument-free.

> **Incident** (`README.md` › *What it gives a consumer project*):
>
> | **the tier classifier** (`bbh tier`) | which gates reach an instrument — transitively, through sourced libs — so none falls between the runners | H1 |

**[BBH-24]** **The harness will NOT read a gate's code, guess a skip from prose, count a self-skip as a pass, edit a running script, or weaken its classifier to make a consumer green:** a delta between the harness's classifier and a consumer's older one is a FINDING about the consumer.

> **Incident** (`docs/gate_contract.md` › *7. What the harness will NOT do*):
>
> It will not read a gate's code to decide anything, will not guess a skip
> from prose, will not count a self-skipping gate as a pass, will not edit a
> running script (the shell reads by byte offset), and will not weaken the
> classifier to make a consumer green: a delta between this classifier and
> a consumer's older one is a FINDING about the consumer.

## 3. The driver contract

**[BBH-25]** **A driver has four arguments — `<set> <replay> <out.log> [sandbox]` — and the suite, the comparators and the fidelity checks know only that contract,** never which machine is behind it; a consumer's own driver fits the same shape or the suite cannot drive it.

> **Incident** (`drivers/README.md` › *The driver contract — how the suite drives a machine*):
>
> A DRIVER runs one replay on one machine and writes one checksum log. The
> suite runner (`bbh run-suite`), the comparators and the fidelity checks
> never know which machine is behind it; they know this contract. Every
> driver in this directory — and any a consumer writes — has the same four
> arguments, honours the same environment, and writes the same grammar.

**[BBH-26]** **The build under test is what the driver's SEARCH PATH resolves,** through the driver's own variable, falling back to the reference-input variable; a driver documents that variable in its header, and a chained search path that resolves the pristine reference when the build dir is empty measures the reference against itself.

> **Incident** (`drivers/README.md` › *1. The invocation*):
>
> The build under test is what the driver's SEARCH PATH resolves: the
> variable is the driver's own (`MAME_ROMPATH`, `FBNEO_ROMPATH`,
> `FAKE_ROMPATH`) and the suite names it in `[suite].rompath_env`, falling
> back to the reference-input variable (`[suite].input_env`, the lineage's
> `ROMDIR`). A driver documents its variable in its header.

**[BBH-27]** **The output log is REMOVED before the run,** so "no END line" can never be satisfied by a previous run's file; a stale artifact is a false green with a timestamp.

> **Incident** (`drivers/README.md` › *1. The invocation*):
>
> | `out.log` | the checksum log to write; made absolute; **removed before the run** so "no END line" can never be satisfied by a previous run's file |

**[BBH-28]** **A driver that cannot honour a variable REFUSES it — `REFUSED: <driver> cannot honour <VAR>`, exit 3 — and never ignores it.** A caller that set the variable is measuring something; a run that silently did not measure it is the false green every gate exists to remove (a driver with no mask support once took masks for a session before a gate noticed the logs were unmasked).

> **Incident** (`drivers/README.md` › *2. The environment — the replay family (every driver)*):
>
> **THE RULE: a driver that cannot honour a variable REFUSES it — prints
> `REFUSED: <driver> cannot honour <VAR> (<why>)` and exits 3 — and never
> ignores it.** A caller that set the variable is measuring something; a run
> that silently did not measure it is the false green every gate here exists
> to remove. (The lineage's FBNeo driver has no `MASK_RANGES`; the lineage
> passed masks to it for a session before a gate noticed the logs were
> unmasked.)

**[BBH-29]** **The replay family is one vocabulary for every driver:** masks, dumps, pokes, snapshots, a video log, an input log, the tail, the integrity switch and its must-fire; the guard family belongs to the GUARDED drivers only, and a plain driver refuses it.

> **Incident** (`drivers/README.md` › *2. The environment — the replay family (every driver)*):
>
> The guard family — `GUARD_DEBUG`, `GUARD_PROBE`, `GUARD_PROBE_COND`,
> `GUARD_TRACE`, `GUARD_PC_LOG`, `GUARD_BREAK`, `GUARD_MATCH`,
> `CRASH_VECTORS`, `CODE_RANGES` — belongs to the GUARDED drivers
> (`mame_guarded.sh`, H6). A plain driver REFUSES them.

**[BBH-30]** **A masked log is a BASIS:** masked bytes are SKIPPED from the hash, so a log under one mask is never comparable to a log under another, and a driver whose log is not checksum-comparable (a debug-timeline guard) refuses a mask rather than emit a log a gate would compare.

> **Incident** (`drivers/README.md` › *2. The environment — the replay family (every driver)*):
>
> | `MASK_RANGES` | `lo-hi,...` hex OFFSETS from the checksum window's base, end exclusive; masked bytes are SKIPPED from the hash, so a mask defines a BASIS (a log under one mask is never comparable to a log under another) | REFUSE (the crash guard's precedent: its `-debug` timeline is not checksum-comparable, so it refuses a mask rather than emit a log a gate would compare) |

**[BBH-31]** **The video log is a SECOND hash log over the framebuffer, in the same grammar, written to a separate file** so no RAM expectation moves — a RAM-only gate is structurally blind to the whole video path.

> **Incident** (`drivers/README.md` › *2. The environment — the replay family (every driver)*):
>
> | `VIDEO_OUT` | a path: a SECOND hash log over the framebuffer, same grammar, written to a separate file so no RAM expectation moves (a RAM-only gate is structurally blind to the whole video path) | REFUSE |

**[BBH-32]** **The input-integrity assertion is always on, and it has a must-fire:** the machine records its ports every frame against the scripted values, host input leaking into the emulated controls writes an `INPUT-VIOLATION` line BEFORE `END`, and the injection test proves the assertion fires by simulating a foreign press.

> **Incident** (`drivers/README.md` › *2. The environment — the replay family (every driver)*):
>
> | `INPUT_INJECT_TEST` | `<frame>`: the assertion's MUST-FIRE control — the machine simulates a foreign press and the log must carry an `INPUT-VIOLATION` line | honour if the assertion exists |

**[BBH-33]** **The log grammar is `<frame> <hash>` per frame then `END <n>`,** the hash any fixed-width hex token the machine computes over its window minus the mask, compared as tokens and never interpreted; the guarded grammar adds the crash lines and ends `END-CRASH`, and one reader parses both.

> **Incident** (`drivers/README.md` › *3. The output — the log grammar*):
>
> `<hash>` is any fixed-width hex token the machine computes over its
> checksum window minus the mask; the harness compares tokens, never
> interprets them. The guarded grammar adds `CRASH <frame> <vector> PC <pc>`,
> `REGS …`, `STACK …`, `PCWEEDS …`, `SOFTRESET …` and ends with `END-CRASH
> <frame>` instead of `END`. `lib/py/bbh/logfmt.py` is the one reader.

**[BBH-34]** **The four exits mean four things:** 0 the log is complete and clean; 1 the machine failed, no END, or a violation — the run is DISCARDED and never compared; 2 the guard tripped and the log is the bug report; 3 a variable was refused.

> **Incident** (`drivers/README.md` › *4. The exit status*):
>
> | 0 | the log is complete (`END` present) and carries no `INPUT-VIOLATION` |

**[BBH-35]** **The suite scrubs the replay family from its environment before any driver runs,** so nothing from the caller's shell reaches a frozen expectation; a poke exported in a shell once would have moved every log of a suite.

> **Incident** (`drivers/README.md` › *2. The environment — the replay family (every driver)*):
>
> The suite scrubs `[suite].hermetic_unset` from its environment before any
> driver runs, so nothing from the caller's shell reaches a frozen
> expectation.

**[BBH-36]** **The sandbox is the machine's home** — cfg, nvram, snapshots, its own stderr log — a fresh temp dir when omitted, so no state carries from one run into the next; a NAMED sandbox is deliberate carry-over, and a run that means to start fresh does not name one.

> **Incident** (`drivers/README.md` › *1. The invocation*):
>
> | `sandbox` | optional: a directory the machine may treat as its home (cfg, nvram, snapshots, its own stderr log); made absolute; a fresh temp dir when omitted |

**[BBH-37]** **A second implementation of the same machine is a driver under the same contract**, mapping what it can (dumps, pokes, the video log) to its own switches and REFUSING the rest — never adapting the contract to the implementation.

> **Incident** (`drivers/README.md` › *5. The drivers here*):
>
> | `fbneo.sh` | a patched FBNeo frontend carrying the replay harness (`-hinput/-hout/-hdump`, `FBNEO_HPOKE`, `FBNEO_HVIDEO`) — a SECOND implementation of the same machine | `FBNEO_ROMPATH` (first wins; `ROMDIR` always last), built as a symlink overlay because the frontend has no `-rompath`; `FBNEO_BIN` required | maps `DUMPS` to `-hdump` (files `<out>.dump_<f>_<a>.bin`), `POKES` to `FBNEO_HPOKE`, `VIDEO_OUT` to `FBNEO_HVIDEO`; refuses `MASK_RANGES`, `SNAP_FRAMES`, `INPUT_OUT`, `INPUT_INJECT_TEST`, `NO_INPUT_CHECK`, a `TAIL_FRAMES` other than the frontend's 120, and the guard family (H6) |

## 4. The oracle classes

**[BBH-38]** **A mask is a basis, not a flag:** adding a range changes every frame's hash, so a reference frozen under one mask is not comparable to a run under another; a basis directory records the mask it was frozen under, a set records the mask it runs under, and the checker REFUSES a pairing whose two masks differ or a mask-carrying set citing a record-less basis. Re-freezing to make that green is the one thing the guard exists to prevent.

> **Incident** (`docs/method/oracle_classes.md` › *The basis: masked bytes are SKIPPED, so a mask is a basis, not a flag*):
>
> A per-frame checksum covers a RAM window minus a MASK — byte ranges the
> consumer has ratified as execution-position noise (a dead-stack window, a
> sound-latch phase word). Masked bytes are skipped FROM THE CHECKSUM, so
> adding a range changes every frame's hash: a reference frozen under one
> mask is not comparable to a run under another. Hence the two records and
> the guard: a basis directory carries `MASK` (what it was frozen under), a
> set may carry `mask` (what it runs under), and `masked_check` REFUSES a
> pairing whose two masks differ, or a mask-carrying set citing a record-less
> basis. Re-freezing to make that green is the one thing the guard exists to
> prevent.

**[BBH-39]** **Every non-exact class is a MEASURED MECHANISM with a FROZEN expectation; none is a tolerance.** Exact is the default; the others exist because zero-cost hooking is impossible on a real engine, where a hook on a path the reference executes costs cycles and interrupts land at skewed boundaries.

> **Incident** (`docs/method/oracle_classes.md` › *The oracle classes — the ratified comparison vocabulary, and what may never loosen it*):
>
> A REFERENCE COMPARISON puts the system under test beside a frozen
> reference run of the same replay and asks whether the per-frame state
> stream is the same. The answer is not always "bit-identical", and the
> classes below are the only other answers a consumer's expectation may give.
> Each is a MEASURED MECHANISM with a FROZEN expectation; none is a
> tolerance. The checkers are `lib/py/bbh/compare_*.py` and
> `check_diverge.py`, dispatched by `lib/sh/masked_compare.sh` from a spec
> line `<class> <baseset> <args>`; their ground truths are the
> `selftest/test_compare_*.sh` and `test_masked_compare.sh` gates. The
> thresholds are `lib/py/bbh/thresholds.py`, declared once. (Lineage:
> VampireSaved's `docs/project/oracle_classes.md`, v1-v6; the numbers and the
> named exemptions stayed there.)

**[BBH-40]** **Flicker-tolerated asserts that the divergent frames are EXACTLY the frozen inventory** — each run within the flicker cap, re-convergence after each, the total within its cap — and a divergence the log ends inside is FAIL-SHORT, a different finding (the replay is too short) from FAIL (the build diverged).

> **Incident** (`docs/method/oracle_classes.md` › *The classes*):
>
> | **flicker-tolerated** (v2) | `flicker <basis> <n> <f1,f2,…>` | the divergent frames are EXACTLY the frozen inventory: each run ≤ `flicker_max` frames, ≥ `reconverge` identical frames after each, ≤ `flicker_max_total` in all; NO end-of-log exemption — a divergence the log ends inside is `FAIL-SHORT`, a different finding (the replay is too short) from `FAIL` (the build diverged) | `compare_flicker` |

**[BBH-41]** **The frozen first-divergence constant asserts line-identity through `frame−1` and a first divergence EXACTLY at `frame`;** earlier, later or absent FAILS, and a length mismatch FAILS — a short log is never a prefix match.

> **Incident** (`docs/method/oracle_classes.md` › *The classes*):
>
> | **frozen first-divergence constant** | `diverge <basis> <frame>` | line-identical through `frame−1`, first divergence EXACTLY at `frame`; earlier, later or absent FAILS; a length mismatch FAILS (a short log is never a prefix match) | `check_diverge` — the spec file's STEM names the base log |

**[BBH-42]** **The bounded re-convergent window asserts ONE contiguous run, a FIXED onset, full re-convergence and the end state untouched, and a bit-identical pair FAILS it:** the expectation asserts the divergence EXISTS, and an onset moving EARLIER is the failure.

> **Incident** (`docs/method/oracle_classes.md` › *The classes*):
>
> | **bounded re-convergent window** (v3) | `window <basis> <onset> <end>` | ONE contiguous divergent run, a FIXED onset, full RE-CONVERGENCE (≥ `reconverge` identical frames after), the end state untouched; a bit-identical pair FAILS — the expectation asserts the divergence EXISTS | `compare_window` |

**[BBH-43]** **Composite is the strict CONJUNCTION of flicker and window:** every divergent run accounted for BY NAME, the flicker set equal to its inventory, the window list exact — it adds NO tolerance and is stricter than either component.

> **Incident** (`docs/method/oracle_classes.md` › *The classes*):
>
> | **composite** (v4) | `composite <basis> <f1,…> <onset-end;…>` | the strict CONJUNCTION of flicker and window: every divergent run accounted for BY NAME, the flicker set equal to its frozen inventory, the window list exact, full re-convergence; adds NO tolerance — it is stricter than either component | `compare_composite` |

**[BBH-44]** **The re-convergence rule is INTRA-mechanism:** it governs the tail after the last divergence of ONE attributed mechanism and does not bind across the gap between two; making it bind between flicker runs is off by default and a consumer that turns it on is amending its policy.

> **Incident** (`docs/method/oracle_classes.md` › *The classes*):
>
> - **The ≥ `reconverge` rule is INTRA-mechanism** (v5): it governs the tail
>   after the last divergence of ONE mechanism and does not bind across the
>   gap between two separately attributed ones. `--min-converge-flicker` makes
>   it bind between flicker runs; it is OFF by default and a consumer that
>   turns it on is amending its policy.

**[BBH-45]** **A divergence that does not re-converge is NOT expressible in the vocabulary.** The proposer says so and proposes nothing; the shape is root-caused, never absorbed into a widened tolerance.

> **Incident** (`docs/method/oracle_classes.md` › *The classes*):
>
> - **A divergence that does not re-converge is NOT expressible** in this
>   vocabulary. The proposer (`describe_masked_shape`) says so and proposes
>   nothing; the shape is root-caused, never absorbed into a widened
>   tolerance.

**[BBH-46]** **A replay is reclassified to a looser class only with a NEW MEASURED MECHANISM and the consumer's sign-off** — never to make a red green.

> **Incident** (`docs/method/oracle_classes.md` › *What may never loosen a class*):
>
> 1. **A replay is reclassified to a looser class only with a NEW MEASURED
>    MECHANISM and the consumer's sign-off** — never to make a red green.

**[BBH-47]** **The standing watch: flickers growing beyond the frozen inventory, or divergences turning systematic, mean STOP AND ROOT-CAUSE.** A grown inventory FAILS and so does a shrunk one — a frozen expectation describes ONE build, and a fresh build that differs either way is not that build.

> **Incident** (`docs/method/oracle_classes.md` › *What may never loosen a class*):
>
> 2. **The standing watch:** flickers growing beyond the frozen inventory, or
>    divergences turning systematic, mean STOP AND ROOT-CAUSE. That pattern
>    is a deeper issue, not tolerance noise. A grown inventory FAILS; so does
>    a SHRUNK one — drift either way is loud, because a frozen expectation
>    describes ONE build and a fresh build that differs is not that build.

**[BBH-48]** **The proposer and the enforcers cannot disagree:** they import the same thresholds, declared once, and a selftest proves a consumer override reaches both — a proposed line drops into a spec verbatim and passes.

> **Incident** (`docs/method/oracle_classes.md` › *What may never loosen a class*):
>
> 3. **The proposer and the enforcers cannot disagree:** they import the same
>    thresholds, and `selftest/test_thresholds.sh` proves that a consumer
>    override reaches both (a proposed line must drop into a spec verbatim
>    and pass).

**[BBH-49]** **Whole-state frame-exact remains the standard** for reference runs, run-to-run determinism and hook-free builds; every replay is run more than once and any difference between the runs is NONDETERMINISTIC and a failure before any class is consulted.

> **Incident** (`docs/method/oracle_classes.md` › *What may never loosen a class*):
>
> 4. **Whole-state frame-exact remains the standard** for reference runs,
>    run-to-run determinism and hook-free builds; the non-exact classes exist
>    because zero-cost hooking is impossible on a real engine — a hook on a
>    path the reference executes costs cycles, and interrupts then land at
>    skewed instruction boundaries in otherwise-identical frames.

**[BBH-50]** **A self-frozen expectation answers "did this build change since I froze it" and can never see a regression against the reference;** only a spec against a reference basis can, and a new expectation KIND is registered in one place and nowhere else, so an unknown kind is reported rather than silently ignored.

> **Incident** (`docs/method/oracle_classes.md` › *Where a class is written*):
>
> A set directory holds one expectation per replay:
> `<set>/<name>.masked` (a spec line above), `.skip` (deliberately not run,
> with a reason), `.sha1` (self-frozen to ONE image — it answers "did this
> build change since I froze it" and can never see a regression against the
> reference). A new KIND is registered in `enumerate_expectations.sh` and
> nowhere else, so an unknown kind is REPORTED rather than silently ignored.

**[BBH-51]** **A `.pending` expectation is REPORTED as unevaluated, never silently skipped** — it marks a pairing with no ratified class anywhere, exactly the state an audit exists to detect — and the enumeration returns non-zero on it.

> **Incident** (`docs/method/oracle_classes.md` › *Where a class is written*):
>
> A `.pending` expectation marks a replay with no ratified class yet — a
> pairing the reference comparison has never evaluated, exactly the state an
> audit exists to detect. It is REPORTED as unevaluated, never silently
> skipped: `enumerate_expectations` returns non-zero on it, and a suite that
> carries one is not green.

## 5. Expectation and gate hygiene

**[BBH-52]** **Every frozen expectation FILE has a row in a register naming what it describes, a CLOSED evidence class it rests on, and how to re-freeze it, complete both ways;** the file is what a triage opens, and a gate found green on a constant of testimony presented as measured is why.

> **Incident** (`docs/hygiene.md` › *Expectation and gate hygiene — the checks that keep a suite honest between runs*):
>
> | `bbh provenance` | every frozen expectation FILE has a row in a register naming what it describes, a CLOSED evidence class it rests on, and how to re-freeze it; complete both ways | a gate was GREEN on a constant of playtest testimony presented as measured; it happened to be right — luck, not method. A red gate is a QUESTION whose first question is which side rests on a measurement, and the FILE is what a triage opens |

**[BBH-53]** **The evidence classes are a policy, not a format,** and they are ranked: a number the REFERENCE produced is the strongest; a number OUR build produced locks currency and never correctness; derived is only as good as the reader; a hash-lock locks currency; a registry is a ledger of decisions. A file with no re-freeze path is hand-maintained and changing it is a decision.

> **Incident** (`docs/hygiene.md` › *The register (`bbh provenance`)*):
>
> A markdown table under `[provenance].page`; the first cell is the file's
> `backticked` name (with the scope dir's row prefix, e.g. `expect/x.txt`),
> the `rests on` column names one of `[provenance].evidence_classes`. The
> lineage's vocabulary, which is a POLICY and not a format:

**[BBH-54]** **A hard-coded path default the script READS as an image must not have ROTTED** — present, read as an image, too old to carry what the reader needs; ABSENT is "unbuilt here" and never a failure, and a default read for another purpose is not judged, because a check that cries wolf about a working reference is one people switch off.

> **Incident** (`docs/hygiene.md` › *Rot vs currency (`bbh ref-rot`)*):
>
> ROTTED = present, read as an image, too old to carry what the reader
> needs — the consumer's `[ref_rot].stale_marker` (a member prefix that
> implies a required member) or a `predicate` command. It is the one thing
> this check FAILS on. Absent is "unbuilt here" and never a failure (a clean
> checkout has no build dirs). A default the script reads for another
> purpose (its extract dir, its patch dir) is not judged — a check that cries
> wolf about a working reference is one people switch off.

**[BBH-55]** **CURRENCY is the other question and it is REPORTED, never failed:** the image loads, but is it the generation the gate meant? A superseded reference is often CORRECT — the pre-fix build of an A/B, a known-bad ground truth — and only the gate's author knows which, so the report is a triage worksheet.

> **Incident** (`docs/hygiene.md` › *Rot vs currency (`bbh ref-rot`)*):
>
> CURRENCY is the other question: the image loads, and is it the generation
> the gate meant? The report fingerprints each referenced image, looks its
> set up in `[suite].registry`, compares it against the newest generation of
> its family (`family_regex`), and lists families referenced at more than
> one generation. A superseded reference is often CORRECT — the pre-fix
> build in an A/B audit, a known-bad ground truth — and only the gate's
> author knows which, so it is a triage worksheet, never a verdict.

**[BBH-56]** **A pick among several files is sorted first and then an ORDERED, NAMED preference;** a verdict that depends on which file the filesystem lists first is a verdict about the filesystem.

> **Incident** (`docs/config.md` › *`[ref_rot]` — a hard-coded path default must not have rotted (`bbh ref-rot`, H5)*):
>
> | `image_prefer` | `["vsavjw", "vsavj"]` | config | substrings, in order, choosing among several images; else the first by name (the lineage took directory order) |

**[BBH-57]** **The gate index is GENERATED from every gate's own header plus one hand-maintained family table, complete both ways, and `--check`ed in a gate;** a hand-written index once covered half the scripts, one twice, with comments the scripts' headers lacked.

> **Incident** (`docs/hygiene.md` › *Expectation and gate hygiene — the checks that keep a suite honest between runs*):
>
> | `bbh gate-index` | the gate index is GENERATED from every gate's own header plus one hand-maintained family TSV, complete both ways; `--check` in a gate | a 2,160-line hand-written fence indexed 168 of 281 scripts, one twice, with comments the scripts' headers lacked |

**[BBH-58]** **A battery cannot print GREEN while a gate self-skipped:** every gate call goes through a counted wrapper, a whole-group skip is counted by size, the closing sentence is GREEN only at zero skips, and a FAIL, an exit-0 shell error or a timeout stops it and names the gate.

> **Incident** (`docs/hygiene.md` › *Expectation and gate hygiene — the checks that keep a suite honest between runs*):
>
> | `lib/sh/accounting.sh` | a battery cannot print GREEN while a gate self-skipped; a FAIL, a shell error read as exit 0, or a timeout stops it and names the gate | nine of ~24 gates never ran on a machine without the instrument and the script still printed BATTERY GREEN |

**[BBH-59]** **A perturbation control edits a SHADOW COPY of the tool under a throwaway root whose siblings are symlinks; the tracked tool is never written.** Controls that edited the tracked generator in place and restored on an exit trap covered Ctrl-C and nothing else.

> **Incident** (`docs/hygiene.md` › *Expectation and gate hygiene — the checks that keep a suite honest between runs*):
>
> | `lib/sh/shadow_tools.sh` | a perturbation control edits a COPY under a shadow root whose siblings are symlinks; the tracked tool is never written | controls edited the tracked generator in place and restored on an exit trap — which covers Ctrl-C and nothing else |

**[BBH-60]** **The one header parser is the only reader of headers,** and a consumer with another comment style loses the three header checks and nothing else: the runners read names, exit statuses and output, never headers.

> **Incident** (`docs/hygiene.md` › *The header contract these read (`docs/gate_contract.md` §3)*):
>
> One parser, `lib/py/bbh/gate_header.py`: the `#` lines after the shebang;
> the first paragraph (to the first bare `#`) as the index sentence; the
> whole block for the runtime, the session token and the `Usage:` line.
> Every regex is `[gate_header]` (`docs/config.md`). A consumer with another
> comment style gets nothing from these three checks and loses nothing
> else: the runners read names, exit statuses and output, never headers.

## 6. Config discipline

**[BBH-61]** **Every key has a default and a BIN it came from, listed in one reference;** "code" is the harness's own contract and not a consumer choice, "config" is a literal the lineage carried in source that is a consumer VALUE.

> **Incident** (`docs/config.md` › *The config — `bbh.toml`, every key, its default, and the bin it came from*):
>
> "Origin" says which bin the key came from when it was extracted:
> **code** = the harness's own contract, not a consumer choice; **config** =
> a literal the lineage carried in source that is a consumer VALUE.

**[BBH-62]** **A missing key with no default is FATAL, never silent:** a runner never runs on an empty value, and a demanded consumer value that is absent stops the tool naming the key.

> **Incident** (`docs/config.md` › *The config — `bbh.toml`, every key, its default, and the bin it came from*):
>
> One file per consumer. Paths are relative to the config file's directory,
> unless `[project].root` moves the consumer root elsewhere (so a consumer
> config may live OUTSIDE the tree it describes — `example/consumers/`). The
> sh runners read it through `python3 -m bbh.config <file> get <section.key>`;
> a missing key falls back to the default here, and a key with no default and
> no `--default` is FATAL (exit 3): a runner never runs on an empty value
> silently.

**[BBH-63]** **The config is a TOML SUBSET, refused where it is ambiguous:** tables, strings, integers, booleans, arrays of scalars and of arrays of scalars, inline tables of scalars; dotted names, arrays of tables, duplicate keys, floats and escapes are REFUSED, and everything accepted reads identically under a full parser.

> **Incident** (`docs/config.md` › *The config — `bbh.toml`, every key, its default, and the bin it came from*):
>
> The reader is a TOML SUBSET (`lib/py/bbh/toml_subset.py`): tables, basic
> and literal strings, integers, booleans, arrays (of scalars or of arrays of
> scalars, possibly multi-line), inline tables of scalars. Dotted names,
> arrays of tables, duplicate keys, floats, escapes and nested inline tables
> are REFUSED — everything it accepts, `tomllib` reads identically
> (`selftest/test_config.sh` proves it on a host that has one). Regexes go in
> `'literal strings'`.

**[BBH-64]** **The thresholds are a consumer's RATIFIED comparison policy, not tuning knobs:** changing one is a reviewed edit of the config, and the comparators and the proposer read them from one place.

> **Incident** (`docs/config.md` › *`[thresholds]` — the comparison classes' numbers (H2)*):
>
> Read by `lib/py/bbh/thresholds.py` through `BBH_CONFIG` and nowhere else;
> every comparator and the proposer import from there. These are a
> consumer's RATIFIED comparison policy, not a tuning knob: changing one is a
> reviewed edit of the config.

**[BBH-65]** **A board is never implied:** the machine-profile key has NO default, nothing is exported without one, and a driver that needs a profile REFUSES to run without it — the example consumer omits the section because its fake machine runs no Lua.

> **Incident** (`docs/config.md` › *`[machine]` — the machine profile the MAME drivers run under (H6)*):
>
> | `profile` | **none** | config | a name under `lua/mame/profiles/` (`cps2`, `cps2w`, or a consumer's own by path). `bbh run-suite` exports it as `BBH_PROFILE` when the caller has not set one; with neither, nothing is exported and a MAME driver REFUSES to run. There is deliberately no default: a board is never implied (the example omits the section — its fake driver needs none). The profile's keys are `docs/lua.md` and `lua/mame/profiles/TEMPLATE.lua` |

**[BBH-66]** **A consumer config that lives outside the tree it describes carries ONE host's layout,** so the consumer's own gate passes its location as an input and the fidelity test derives a private config copy with that absolute root — never an environment override inside the resolver, which would leak into every other config the same run opens.

> **Incident** (`docs/conventions.md` › *Conventions — the harness's ruled defaults, and what each would cost to change*):
>
> 6. **A consumer that does not consume the harness keeps its config HERE
>    (`example/consumers/<name>.toml`), and that config's `[project].root` is
>    one host's layout — so the consumer's own gate passes its location as
>    `BBH_FIDELITY_ROOT`, and `selftest/test_fidelity_vampire.sh` derives a
>    private copy of the config with that absolute root.** Ruled 2026-09-07,
>    with the input added the same day: before it, the lineage's fidelity
>    gate failed on any clone whose directory layout differed from the
>    author's, for a reason that was not fidelity. Deliberately NOT an
>    environment override inside the config resolver: that would leak into
>    every other config the same run opens (the fake repo of F1, the example).

**[BBH-67]** **Registry rows are written only at freeze time, as a build decision** — `sha1 <TAB> expectation-set <TAB> notes` — so an image the registry does not know is refused loudly rather than run against a guessed set.

> **Incident** (`docs/config.md` › *`[suite]` — the expectation tree and the suite runner (H2 reads three keys; H3 the rest)*):
>
> | `registry` | `"tests/expected/registry.tsv"` | config | `sha1 <TAB> expectation-set <TAB> notes`; `#` comments; rows only at freeze time, as a build decision |

**[BBH-68]** **The sweep registry declares a release's instrument scope:** one row per instrument gate with lane, scope, cadence, args and an optional per-row timeout; `out` never means "do not run", the prereq lane runs first and serially and a red there STOPS the run, and a gate's args default to its OWN defaults because what a release would actually hit is what the sweep must measure.

> **Incident** (`docs/config.md` › *`[sweep]` — the instrument-tier sweep (`bbh run-sweep`, H4)*):
>
> The registry is `[registries].sweep`: `gate <TAB> lane <TAB> scope <TAB>
> cadence <TAB> args <TAB> note [<TAB> timeout]`. The vocabularies of the
> lane, scope and cadence columns are these keys.

**[BBH-69]** **A recording is a directory of four things** — the emulator's own input recording, the fresh state it started from, a one-line NOTE of what it exercises, and for a captured-but-unfixed crash a DEFECT file naming the expected fault — and the corpus dir, the set and the build under test are the consumer's config, never a silent default.

> **Incident** (`docs/config.md` › *`[inp]` — the recording corpus (`bbh inp-corpus`, `bbh inp-play`, H6)*):
>
> A RECORDING is `<corpus_dir>/<name>/{<name>.inp, nvram/, NOTE[, DEFECT]}`:
> the emulator's own input recording, the fresh nvram it started from, a
> one-line note of what it exercises, and — for a captured-but-unfixed crash
> — the expected `vec<n> PC <pc6>` the gate asserts instead (so the capture
> cannot rot).

**[BBH-70]** **A default that names one host's file, one project's build or one lineage's session is a dated assertion with no expiry:** it is documented as the lineage's literal where it must stay, overridable where it must not, and the example consumer sets its own.

> **Incident** (`docs/config.md` › *`[sweep]` — the instrument-tier sweep (`bbh run-sweep`, H4)*):
>
> | `prereq_cite` | `"[CPE-24]"` | config | the citation appended to the prereq STOP text ("a measurement taken after a moved instrument is not evidence"); the default is the lineage's rule ID for exactly that sentence, meaningful only there — a consumer names its own rule or sets `""` (the example does) |

## 7. The instrument layer

**[BBH-71]** **Every board literal lives in ONE machine-profile table** — the CPU and space tags, the RAM window, the port map and its tokens, the exception frame and vectors, the code window, the exception store — and a script never runs on an implied board: the loader refuses a profile missing a required key, and each guard refuses a profile missing a crash key it reads.

> **Incident** (`docs/lua.md` › *1. The machine profile (`lua/mame/profile.lua`, `profiles/*.lua`)*):
>
> `BBH_PROFILE` names it — a bare name (`cps2`) resolves to
> `lua/mame/profiles/<name>.lua`, a path is used as is. `profile.load()`
> REFUSES a profile missing a required key, and every guard script refuses
> one missing a `crash.*` key it reads; a script never runs on an implied
> board. `profiles/TEMPLATE.lua` carries every key with a comment;
> `selftest/test_profiles.sh` keeps the template complete (every `P.x` / `C.x`
> a script reads is in it) and the loader's required list in step.

**[BBH-72]** **Two guards on one board must draw the same sketch of one crash:** the code window is a per-instrument "plausible address" bound that a profile change must visit, and the lineage's two guards carried different values for weeks until one profile table put them side by side.

> **Incident** (`docs/lua.md` › *1. The machine profile (`lua/mame/profile.lua`, `profiles/*.lua`)*):
>
> | `crash.code = {lo, hi}` | guards | a ROM-plausible long: handler addresses, the STACK sketch. `cps2` (4 MB) and `cps2w` (6 MB) differ ONLY here — the lineage's two guards carried different values and drew different sketches of the same crash |

**[BBH-73]** **One strict grammar, whose two copies are diffed:** a lenient parser that silently DROPS an unknown token is a malformed replay read as a shorter one; the Lua and the python parse of every replay are compared, under a standalone interpreter where one exists and under the machine's own interpreter in fidelity.

> **Incident** (`docs/lua.md` › *2. The grammar (`lua/mame/rpl_parse.lua` == `lib/py/bbh/rpl.py`)*):
>
> One strict parser for every script (the lineage had one strict copy and
> five lenient ones that silently DROPPED an unknown token — a malformed
> replay now fails loudly, with the lineage's own error texts, on both
> sides). Two copies of a grammar are the harness's own rot risk, so their
> canonical parses are diffed: `selftest/test_rpl_lua.sh` under a standalone
> `lua` (SKIP with the reason when none is present), and fidelity F8 under
> MAME's own interpreter over every lineage replay — the production one.
> `lua/mame/rpl_dump.lua` and `bbh rpl dump` print that canonical text.

**[BBH-74]** **Input staging is CANONICAL** — parse `held[frame]`, stage for the NEXT frame — so a frame number in any instrument's log is a replay frame number; ten instruments once staged one frame off because one variant was copied by every later file.

> **Incident** (`docs/lua.md` › *3. The scripts*):
>
> Two things every instrument shares and a consumer copying one must keep:
> INPUT STAGING IS CANONICAL — parse `held[fr]`, stage for the NEXT frame
> (`held[frame + 1]`), so a frame number in any log IS a replay.lua frame
> number (the lineage's ten `+1` deviants were one variant copied by every
> later file until a census pinned the split).

**[BBH-75]** **A memory tap is dropped silently whenever the machine re-installs handlers in the space;** every tap script re-installs on the space's change notifier, or it logs boot writes only and reads as "nobody writes this field".

> **Incident** (`docs/lua.md` › *3. The scripts*):
>
> A memory TAP is dropped silently whenever the machine re-installs handlers
> in the space — every tap script re-installs on the space's change
> notifier, or it logs boot writes only and reads as "nobody writes this
> field".

**[BBH-76]** **A written value and a read value are correlated in ONE run through a non-debug read-and-write tap, never across runs;** two runs are two timelines, and a value serialised from one beside a value from the other is a correlation of nothing.

> **Incident** (`docs/lua.md` › *3. The scripts*):
>
> | `read_tap.lua` | (direct) | a non-debug READ+WRITE tap — serialise a state-dependent value's writes and reads in ONE run (never correlate one across runs) |

**[BBH-77]** **Every reproducible crash is captured as a recording named after the freeze it was PLAYED on, tracked with its note, and replayed under the guard at every freeze;** the corpus gate fails on the first exception, and a captured-but-unfixed crash is declared by its DEFECT file so the capture cannot rot.

> **Incident** (`docs/lua.md` › *4. The recording corpus (`bbh inp-play`, `bbh inp-corpus`)*):
>
> The lineage's law: a field report is a RECORDING before it is a theory. A
> win-fast rig never gives a CPU opponent the time to reach the script that
> crashes; the maintainer's first hand-played recording found in an evening
> what three sessions of rig-derived fixes had not. So: every reproducible
> crash is captured as the emulator's own input recording with the fresh
> nvram it started from, tracked under `[inp].corpus_dir/<name>/` with a
> one-line NOTE, named `<what>-<freeze>-NN` after the freeze it was PLAYED on;
> `bbh inp-corpus` replays every one under `inp_guard.lua` at every freeze and
> fails on the first exception; a captured-but-unfixed crash is declared by a
> DEFECT file naming the `vec<n> PC <pc6>` the gate then asserts (so the
> capture cannot rot) and lists as OPEN.

**[BBH-78]** **A playback that ran ZERO frames executes no code and can raise no exception:** the log is terminated only when the emulator itself reports a playback of more than zero frames, the corpus gate's liveness predicate rejects the rest, and the gate runs its own controls on that predicate every time.

> **Incident** (`docs/lua.md` › *4. The recording corpus (`bbh inp-play`, `bbh inp-corpus`)*):
>
> A playback that ran ZERO frames executes no code and can raise no
> exception: `bbh inp-play` terminates a
> log only when the emulator itself reports a playback of > 0 frames, the
> corpus gate's liveness predicate rejects the rest, and the gate runs its
> own controls on that predicate every time (`selftest/test_inp_corpus.sh`
> exercises every verdict on a stub emulator).

**[BBH-79]** **Every literal in the instrument layer is in one of three bins:** a BOARD fact goes in the profile (the template carries it, a census test demands it), a POLICY value is an environment variable whose default is stated in the script's header, and a CONFIG value is the consumer's — with no silent default where the value names a machine.

> **Incident** (`docs/lua.md` › *5. The defaults census — every literal, and which bin it is in*):
>
> The rule the table encodes: a BOARD fact goes in the profile (the TEMPLATE
> carries it, the census test demands it), a POLICY value is an environment
> variable whose default is stated in the script's header, and a CONFIG
> value is the consumer's — with no silent default where the value names a
> machine.

**[BBH-80]** **Two implementations of one machine traverse identical states on different frame indices,** so the comparable thing is the MAPPED state at anchors each side finds on its own — the debounced rising edge of a predicate on the dumped state — and because the comparator GLOBS, the producer asserts the dump set is complete first: a hole silently moves an anchor.

> **Incident** (`README.md` › *What it gives a consumer project*):
>
> | **mapped-field comparison at anchors, and dump completeness** (`bbh compare-fields`, `bbh check-dumps`) | the dual-implementation protocol: two implementations traverse identical states on different frame indices, so the comparable thing is the MAPPED state (a fields TSV) at the debounced rising edge of a predicate on the dumped RAM, at the anchor and at offsets after it — `--exact` for same-implementation runs; the predicate, the bases and the debounce are the consumer's `[fields]`; and because the comparator GLOBS, the producer asserts the dump set is complete first (a hole silently moves an anchor) | H7 |

## 8. Fidelity and conventions

**[BBH-81]** **An extraction is PROVED by running the generic tool and the original over the SAME input and diffing the verdict TEXT** — never by re-deriving expected values by hand, never by a re-implementation's opinion; where the original prints a number, the generic prints the same number in the same place, or the diff is not empty.

> **Incident** (`docs/doctrine.md` › *4. How an extraction is proved*):
>
> The extraction is PROVED, never asserted: the generic tool and the
> original are run over the SAME input and their verdict TEXT is diffed —
> never expected values re-derived by hand, never a re-implementation's
> opinion of what the answer should be. Where the original prints a number,
> the generic prints the same number in the same place, or the diff is not
> empty; a fidelity row that goes red names a change on one side that the
> other did not make. (`selftest/test_fidelity_vampire.sh` is the lineage's
> contract, F1-F11; `docs/rebaselines.md` is where its text is allowed to
> move, loudly.)

**[BBH-82]** **The generic classifier is the STRONGER copy, and a consumer's delta against it is a FINDING about the consumer** — recorded, never a fidelity failure, and never fixed by weakening the classifier.

> **Incident** (`docs/conventions.md` › *Conventions — the harness's ruled defaults, and what each would cost to change*):
>
> 7. **ONE verdict classifier, `lib/sh/classify.sh`, the STRONGER of the two
>    copies the lineage carried** (the timeout exits, exit 0 after the
>    shell's own error line as FAIL, the SKIP marker last), its regexes and
>    exit list `[classify]` config. Ruled 2026-09-07 as RESOLVED rather than
>    defaulted: the lineage adopted the same one copy in all three of its
>    runners the same day, and F2 — the whole live portable tier through both
>    static runners — measured identical (65 rows).

**[BBH-83]** **A verdict-text or classifier change is never silent:** it lands on both sides in one sitting, the fidelity rows it moves re-baselined in the same commits, the harness's commit pushed before the consumer's, and a dated line in the re-baseline record — whose newest line every fidelity run prints at its head.

> **Incident** (`docs/conventions.md` › *Conventions — the harness's ruled defaults, and what each would cost to change*):
>
> 8. **The fidelity contract's text is never changed silently.** Ruled
>    2026-09-07, replacing the extraction-era rule "no verdict-string change
>    before the last slice is green" (expired by its own terms at H9). A
>    verdict-text or classifier change lands on BOTH sides in one sitting,
>    the fidelity rows it moves re-baselined in the same commits, the harness
>    commit pushed BEFORE the consumer's — and it is LOUD: a dated line in
>    `docs/rebaselines.md`, whose newest line every fidelity run prints at
>    its head. The maintainer's word: *"such a change needs to be loud though,
>    I wouldn't want it to be silent."*

**[BBH-84]** **A default that is not written down is a default nobody can veto:** the harness keeps a register of its ruled defaults — where it lives, what travels, which drivers, one classifier, the loud re-baseline rule — and a change to any row is a dated ruling, never a silent edit.

> **Incident** (`docs/conventions.md` › *Conventions — the harness's ruled defaults, and what each would cost to change*):
>
> The harness was extracted under stated assumptions, each open to veto until
> its maintainer ruled on it (2026-09-07). This page is the register: what
> each default IS, why, and the alternative that was declined. A default that
> is not written down is a default nobody can veto; a change to any row here
> is a ruling, dated in place, never a silent edit. (The license is NOT a
> row: GPL-3.0 is load-bearing on legal and use scope, not a technical
> default — `README.md` states it.)

**[BBH-85]** **The harness is found by an environment variable and never pinned as a submodule,** because it is a test of the harness and not an instrument of any consumer's artifact; the two repositories move TOGETHER instead, under the loud re-baseline rule.

> **Incident** (`docs/conventions.md` › *Conventions — the harness's ruled defaults, and what each would cost to change*):
>
> 2. **A consumer finds the harness by `$BBH_HOME`, and by convention beside
>    its tree or its tree's parent; it is never a submodule.** Ruled
>    2026-09-07. A submodule would pin a version and make the pairing
>    explicit, at the price of a pin-bump ritual and a push-order trap (a pin
>    bump pushed ahead of the commit it names breaks every fresh clone's
>    `git submodule update`). The harness is a test of the harness, not an
>    instrument of any consumer's artifact, so it does not need pinning. The
>    cost that stays: the two repositories move TOGETHER — see 10.

**[BBH-86]** **Lifted comments keep their incident citations as history lines and carry no consumer's rule anchor;** a bare rule ID from another project dangles for a reader here and is worded in place.

> **Incident** (`docs/conventions.md` › *Conventions — the harness's ruled defaults, and what each would cost to change*):
>
> 3. **Lifted comments keep their incident citations (`14z-N` session tags,
>    `GitHub #N`) as history lines; no consumer's rule anchor travels.** Ruled
>    2026-09-07. The citations name dated incidents that make a guard legible,
>    and the archive that resolves them is public. Bare rule IDs from the
>    lineage (three `[CPE-N]` references at the ruling) dangle for a reader
>    here; they are translated into words when the harness skill is written,
>    which decides which IDs exist in the harness's world.

**[BBH-87]** **A driver for a lane one consumer has stays with that consumer until a second consumer exists;** a generic thing needs two instances.

> **Incident** (`docs/conventions.md` › *Conventions — the harness's ruled defaults, and what each would cost to change*):
>
> 4. **Drivers: `fake`, `mame`, `mame_guarded`, `fbneo`. An FPGA/Verilator
>    driver stays with its consumer.** Ruled 2026-09-07. The lineage's
>    Verilator lane produces per-frame RAM dumps rather than the replay log
>    grammar, needs a forked core and a generated ROM image, and runs at about
>    a second per frame; a contract driver would synthesise the checksum log
>    and refuse most of the replay family. About one session — spent when a
>    SECOND jtframe consumer exists. A generic thing needs two instances.
