# The doctrine — the long form of the README's seven sentences, and why each is law

The README states the doctrine in seven sentences. This page is the long
form: for each, the rule, the incident that made it law in the lineage
(Project VAMPIRE SAVED, a CPS-2 ROM hack with 304 gates and 4,000 frozen
expectations), and the MECHANISM in this harness that enforces it — because
a doctrine that is only prose is a doctrine nobody runs. It is lean on
purpose: every paragraph carries one rule, and the incidents' full record
is the lineage's own history, not this page.

## 1. The extraction question, and the four bins

Everything here passed one test, asked of every piece of the lineage's
harness: *would this still be true if the thing under test were not that
ROM, not that board, not even a game?* What survived is CODE (true for
anything: the classifier, the runners, the grammars, the comparison
classes, the driver contract); what a consumer must DECLARE is CONFIG (a
path, a regex naming its instruments, a threshold it ratified); what is
true of one CPU or board is a MACHINE PROFILE (one table per board); and
what is true of one system only STAYS with that consumer. The bins are not
a filing convention: they are the reason a consumer can adopt the harness
without inheriting the lineage's game.

## 2. The seven sentences

**No untested change survives.** Every change to a gate, a driver, a
comparator or an expectation is run through the harness before it is
committed — "it should be equivalent" is not a test result. The lineage
inherited this from an earlier project where systematic in-emulator
verification was the difference between working and shipping. Mechanism:
the harness's own gate chain (`selftest/run.sh`) is classified by the same
classifier the runners use, and the fidelity checks re-run the lineage's
tools beside this harness's on every change to a lifted piece.

**Every in-instrument measurement becomes a rerunnable case.** A probe run
during development — a measurement, a sanity check, a "let me just look" —
is captured as a scripted gate before the session ends; the suite only
grows. The lineage's most valuable artifact is that suite, above every
unit test. Mechanism: the registries (`docs/gate_contract.md` §6) and the
anti-orphan reports of `bbh run-static` and `bbh run-sweep`, which name
every gate that exists and is registered nowhere.

**Verdict logic is itself tested.** A classifier's verdicts are validated
against known ground-truth cases before they are trusted, in BOTH
directions — a gate born against a live defect has never exercised PASS.
The lineage's predecessor shipped a wrong conclusion from a verdict bug,
not a game bug. Mechanism: every selftest here carries a MUST-FIRE control
(`docs/gate_contract.md` §5) — an input perturbed so the check must fail
for the stated reason — and a control that passes for the wrong reason is
itself a failure.

**A field report is a RECORDING before it is a theory.** A reproducible
crash a human can produce is captured first as the machine's own input
recording with the fresh state it started from, and replayed under a guard
at every freeze; mechanism theories come after. The lineage spent three
sessions and two shipped fixes on a rig-derived mechanism that was never
the field crash; the first hand-played recording found the real one in an
evening, because a win-fast rig never gives an AI opponent time to reach
its rarer scripts. Mechanism: `bbh inp-play`, `bbh inp-corpus` and the
recording guard (`docs/lua.md` §4), with a liveness predicate so a dead
playback is never read as clean.

**SKIP is not PASS.** A gate whose inputs are absent prints a `SKIP:` line
and exits 0; counting that as a pass is how a clean checkout that runs 3%
of its gates reports itself green. Exit status decides first, the SKIP
marker is read only on exit 0, and `--strict` makes a skip fatal.
Mechanism: `lib/sh/classify.sh` — the ONE classifier, sourced by every
runner, because the lineage carried two copies that DIFFERED and a crash
read PASS under one of them for five sessions.

**A red gate is a QUESTION whose first question is which side rests on a
measurement.** Before choosing fix-the-gate / fix-what-it-caught / delete,
establish which side's expectation was MEASURED; a frozen number whose
provenance cannot be named is a claim with a number in it. The lineage
found a gate green on a constant of playtest testimony presented as
measured — right by luck. Mechanism: `bbh provenance` (`docs/hygiene.md`)
demands a row with a CLOSED evidence class for every frozen expectation
file, complete both ways.

**When a claim changes, grep for the claim.** A finding does not live in
one place: it propagates into headers, summary lines, registry rows and
gate comments, and the copies outlive the correction. Fixing "where I
remember writing it" is how a document asserts the opposite of the
subsection beneath it. The procedure: grep the wording and its paraphrases
across the whole tree, fix the header and the summary line first, keep
the superseded text marked with what replaced it, re-grep and show the
empty result. Mechanism: none can replace the grep; what the harness adds
is that a stale claim about a VERDICT is loud — a re-baseline of the
fidelity contract is a dated line every run prints (`docs/rebaselines.md`).

## 3. The documentation convention (ruled by the lineage's maintainer, 2026-09-07)

The docs stay LEAN and are searched by KEY: a reference page carries one
rule per paragraph, and a rule that a skill distils is ANCHORED there with
a stable ID (`**[BBH-N]**`) at the paragraph that records it, so the skill,
the page and the guide generated from the page cannot drift apart
(`docs/hygiene.md`, the skills lock). The complete LOG — dated
measurements, superseded figures, the narrative of an incident — lives in
the page's `<name>_history.md` twin, never in the page: a twin carries no
anchor, and the lock reads it as a log (a number a skill quotes must
appear in a page or its twin). Two records and one rule: the page says
what is true, the twin says how it came to be known, and nothing is
deleted from either — a corrected claim is marked in place with what
replaced it.

## 4. What the doctrine is not

It is not a tuning guide. The thresholds, the masks, the evidence classes
and the scopes are the consumer's RATIFIED policy (`docs/config.md`), and
the harness's job is to make a change to any of them a reviewed edit
rather than a knob turned to make a red green. And it is not a claim about
correctness: the harness proves that a system under test behaves as its
frozen reference did, under the classes its consumer ratified — which
side of a red is right is the question it makes askable, not the one it
answers.
