# The gate contract — what a gate looks like so the runners can read it

A GATE is one executable script under the consumer's gates dir (default
`tests/*.sh`). **[BBH-11]** The runners do not read its code; they read its NAME, its
EXIT STATUS and its OUTPUT. The contract is what makes those three mean the
same thing in every gate.

## 1. The verdict contract (what `bbh run-static` and `bbh run-sweep` read)

| the gate | the runner says |
|---|---|
| **[BBH-12]** exits non-zero | **FAIL** — whatever it printed. A `SKIP:` line plus a non-zero exit is a FAILURE: the gate ran, could not complete, and said so. |
| **[BBH-13]** exits 124 or 137 (the timeout wrapper's) | **TIMEOUT** — never FAIL, so a killed gate is not read as a defect in the artifact. |
| **[BBH-14]** exits 0 and its output carries the shell's own `<script>.sh: line N: NAME: message` | **FAIL** — "exit 0 after a shell error". macOS bash 3.2 exits 0 for a `${VAR:?}` abort once an EXIT trap is armed; a 65-minute gate was once recorded `PASS 0s` on four lines of log. A driver's teardown segfault line (`line N:  <pid> Segmentation fault`) has digits where the NAME would be and is not this. |
| **[BBH-15]** exits 0 and prints a line matching `^ *SKIP` | **SKIP** — the reason is that line. The word SKIP in PROSE is not a marker. |
| exits 0 otherwise | **PASS** |

Both regexes and the exit list are the consumer's `[classify]` section.
**[BBH-16]** `--strict` makes SKIP fatal: a skipped gate asserts NOTHING, and a clean
checkout that skips 97% of its gates and reports green is its own false
green.

## 2. The prologue (how a gate begins)

```sh
#!/bin/sh
# <name>.sh — <one sentence: the claim this gate locks>. <tier phrase>, ~<runtime>.
#
# WHY. <the incident or the rule this gate exists for — a gate's WHY lives in the gate>
#
# MUST-FIRE: perturbed-copy: <name> — <what must fail, and why that proves the gate can fail>
#
# Usage: tests/<name>.sh [ARGS]    (a header names the default the CODE uses)
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO"
: "${ROMDIR:?set ROMDIR}"            # demands BEFORE any trap — this shape exits 1 everywhere
. "$BBH_HOME/lib/sh/controls.sh"; bbh_ctl_mode "$0"   # optional: the CONTROL=<name> mode (§5)
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT INT TERM
```

**[BBH-17]** After the trap is armed, a demand is an EXPLICIT TEST, never `${VAR:?}`:

```sh
[ -n "${X:-}" ] || { echo "FAIL: set X"; exit 1; }      # or: bbh_demand X "set X"
```

`bbh demand-after-trap <gates-dir>` lints for the forbidden shape; the
example consumer's gates and the harness's own selftests pass it.
`lib/sh/prologue.sh` offers `bbh_work`, `bbh_demand`, `bbh_skip`, `bbh_fail`,
`bbh_absolutise` for gates that want them; nothing requires them.

## 3. The header (line 2 is an API)

**[BBH-18]** Line 1 is `#!/bin/sh`. Line 2 is `# <name>.sh — <claim>`, and the header
continues until the first bare `#` line. The gate index generator (`bbh
gate-index`) reads exactly that first paragraph as the gate's index
sentence, so it is written as the CLAIM the gate locks, not as a description
of its mechanics. A `Usage:` line names the gate's defaults, and the
header-defaults check (`bbh header-defaults`) asserts every path default the
header shows is one the CODE uses — a header that says `build/m11` while the
code says `build/m21` is how a reader runs the wrong measurement. The
parser is one module, `lib/py/bbh/gate_header.py`; the checks that read
the header are `docs/hygiene.md`.

## 4. The output (one verdict line of the gate's own)

**[BBH-20]** A gate prints its findings and ends with ONE line that states its verdict
in its own words — `PASS: <what held>` or `FAIL: <what did not>`. The runner
does not grep for those words (it reads the exit status), but a human
reading a log does, and a PASS row whose log has NO verdict line of the
gate's own is read as a crash until proven otherwise.

## 5. The must-fire control (a check that cannot fail is not a check)

**[BBH-21]** Every gate that asserts a property PERTURBS an input and requires its own
check to fail for the stated reason. Three shapes, in order of how often
they fit:

1. **perturb one byte** — copy the artifact, flip one byte, re-run the
   comparator, require non-zero;
2. **shadow copy of a tool with a line stripped** — a writable copy of the
   tool in a throwaway root whose siblings are symlinks
   (`lib/sh/shadow_tools.sh`), so the perturbation never touches the
   tracked tree;
3. **a synthetic tree or a known-bad reference** — a fabricated input the
   checker must reject.

A control that passed for the WRONG reason is a failure. A dead control
refuses a verdict.

### 5.1 The declaration (the header line the runners read)

**[BBH-88]** A control is DECLARED as one line in the gate's HEADER — the leading
comment block, every `#` line after the shebang up to the first non-comment
line, a bare `#` continuing it — in exactly this grammar, and the four
regexes of `lib/sh/controls.sh` are the only reader:

```
# MUST-FIRE: <shape>: <name> — <what must fail, and why that proves the gate can fail>
# MUST-FIRE: none — <why this gate asserts no property>
```

`<shape>` is `perturbed-copy` | `shadow-tool` | `known-bad` (the three shapes
above); `<name>` is `[a-z0-9-]+`, unique within the gate; the separator is
the em dash. A malformed line — a wrong shape, a name with a capital or an
underscore, a hyphen where the em dash belongs, a line below the first code
line — declares NOTHING, so the census of a tree is what the regex counts
and nothing looser. A gate that asserts nothing (a fixture generator, a
registry lister) says `none` so silence is distinguishable from omission.
The lineage adopted this grammar (its 14z-147) as a hand-kept copy of a
sibling project's, independent but compatible; this harness carries the same
copy, never a dependency on either.

### 5.2 The firing (what the classifier compares)

**[BBH-89]** When a declared control fails for its stated reason the gate prints, at
column 0, `CONTROL FIRED: <name> — <evidence>`; when it does not — it
passed, or failed for another reason — `CONTROL DEAD: <name> — <what
happened>`. An indented line is prose. Every runner hands the classifier
the gate SCRIPT beside the log (`bbh_classify <exit> <log> <width> <script>`),
and for a PASSING gate the classifier compares declared against fired: a
declared control that did not fire, a `CONTROL DEAD:` line, or a firing no
header declares turns the verdict into plain **FAIL** — there is no fourth
verdict, and the FAIL row names it (`controls RED: <name>(not fired)`). A
gate with no declaration is left alone and COUNTED as undeclared (a
consumer's gates may predate the grammar); a `none` declaration is counted
as such. SKIP and FAIL are never touched: a skipped gate ran nothing, a
failed gate is already red.

### 5.3 The executable form (`CONTROL=<name>`)

**[BBH-90]** `CONTROL FIRED` is the gate's SELF-report, and a control can print it while
testing nothing — it wrote a value and asserted the value was not something
else. So a declared name is also a MODE: `CONTROL=<name> tests/<gate>.sh`
applies that control's perturbation to the gate's REAL input and runs to the
gate's OWN verdict, which must be FAIL. The gate announces the mode
(`CONTROL MODE: <name> — …`, `bbh_ctl_mode "$0"`) and REFUSES a name its
header does not declare (`REFUSED: CONTROL=<name> is not a mode of this
gate`, exit 3). The runner's verdict on a control run (`bbh_classify_control`,
one copy, so no runner carries a second shell-error regex):

| verdict | when | meaning |
|---|---|---|
| HONOURED | exit non-zero, no crash | the perturbation was caught |
| LIES | exit 0, or a SKIP | the perturbation left the gate green — the control tests nothing |
| REFUSED | the gate printed `REFUSED: CONTROL=` | declared in the header, never read by the gate |
| DIED | the shell's own error line, or a traceback | a crash is not a verdict |
| TIMEOUT | the wrapper's exits | as for any gate |

Anything but HONOURED is a failure of the run, named
`<gate>(control:<name>:<verdict>)`. Where a prerequisite is absent on the
host (a build not present, an instrument not installed) the mode REFUSES
rather than self-skipping: a mode that would SKIP or exit 0 is LIES. And a
gate must not use `CONTROL` as its own environment variable — the name is
the mode selector, and a gate that read it for something else was refused
on every plain run until renamed.

### 5.4 The pattern, and the runners

**[BBH-91]** Write each perturbation as ONE function the control section and the mode
both call (`perturb <name> <copy>`); under the mode the perturbed copy
becomes the INPUT the main check reads, while the control section still
builds its own copy and prints the FIRED/DEAD line — so what the mode
proves is exactly what the control claims, and the two cannot drift.
`bbh run-static` reads every gate's block for free and EXECUTES each declared
control after a PASS (`--exec-controls all|portable|none`, default `all`,
because a lying control must not pass a pre-commit; `none` is the
developer's iteration knob), printing a readout — `fired N / declared N`,
the none and undeclared counts, `executed N honoured N lies N refused N
died N` — only when the tier declared or executed anything, so a consumer
that has not adopted the grammar sees the runner it always had, byte for
byte. `bbh run-sweep` reads every block on every run and executes under
`--controls` (one more row per declared name, `<gate>@<name>`, PASS =
honoured, in the tally and under `--strict`); it is off by default because
it multiplies a tier measured in hours, and when it runs is the consumer's
release policy. `example/tests/g_control.sh` is the worked instance; the
ground truth is `selftest/test_controls.sh` with the runners' selftests.

## 6. Registration (a gate that is not in a registry is not run)

**[BBH-22]** A gate that needs no instrument is in `ci_portable.txt` (runs on a clean
checkout) or `ci_static.txt` (needs the input the consumer names in
`[registries].static_needs_env`, or a build dir, but no instrument). A gate
that reaches an instrument — directly, or through a sourced lib — belongs to
the sweep registry and to neither plain one. `bbh run-static` reports
every instrument-free gate that is in neither; `bbh run-sweep --strict`
fails on an unregistered instrument gate and on a registered gate that no
longer exists. That report is the anti-orphan mechanism: without it a runner
is just a smaller thing to forget to update.

## 7. What the harness will NOT do

**[BBH-24]** It will not read a gate's code to decide anything, will not guess a skip
from prose, will not count a self-skipping gate as a pass, will not edit a
running script (the shell reads by byte offset), and will not weaken the
classifier to make a consumer green: a delta between this classifier and
a consumer's older one is a FINDING about the consumer.
