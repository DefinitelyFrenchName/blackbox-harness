# The gate contract — what a gate looks like so the runners can read it

A GATE is one executable script under the consumer's gates dir (default
`tests/*.sh`). The runners do not read its code; they read its NAME, its
EXIT STATUS and its OUTPUT. The contract is what makes those three mean the
same thing in every gate.

## 1. The verdict contract (what `bbh run-static` and `bbh run-sweep` read)

| the gate | the runner says |
|---|---|
| exits non-zero | **FAIL** — whatever it printed. A `SKIP:` line plus a non-zero exit is a FAILURE: the gate ran, could not complete, and said so. |
| exits 124 or 137 (the timeout wrapper's) | **TIMEOUT** — never FAIL, so a killed gate is not read as a defect in the artifact. |
| exits 0 and its output carries the shell's own `<script>.sh: line N: NAME: message` | **FAIL** — "exit 0 after a shell error". macOS bash 3.2 exits 0 for a `${VAR:?}` abort once an EXIT trap is armed; a 65-minute gate was once recorded `PASS 0s` on four lines of log. A driver's teardown segfault line (`line N:  <pid> Segmentation fault`) has digits where the NAME would be and is not this. |
| exits 0 and prints a line matching `^ *SKIP` | **SKIP** — the reason is that line. The word SKIP in PROSE is not a marker. |
| exits 0 otherwise | **PASS** |

Both regexes and the exit list are the consumer's `[classify]` section.
`--strict` makes SKIP fatal: a skipped gate asserts NOTHING, and a clean
checkout that skips 97% of its gates and reports green is its own false
green.

## 2. The prologue (how a gate begins)

```sh
#!/bin/sh
# <name>.sh — <one sentence: the claim this gate locks>. <tier phrase>, ~<runtime>.
#
# WHY. <the incident or the rule this gate exists for — a gate's WHY lives in the gate>
# MUST-FIRE CONTROL: <what is perturbed and what must then fail>
#
# Usage: tests/<name>.sh [ARGS]    (a header names the default the CODE uses)
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO"
: "${ROMDIR:?set ROMDIR}"            # demands BEFORE any trap — this shape exits 1 everywhere
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT INT TERM
```

After the trap is armed, a demand is an EXPLICIT TEST, never `${VAR:?}`:

```sh
[ -n "${X:-}" ] || { echo "FAIL: set X"; exit 1; }      # or: bbh_demand X "set X"
```

`bbh demand-after-trap <gates-dir>` lints for the forbidden shape; the
example consumer's gates and the harness's own selftests pass it.
`lib/sh/prologue.sh` offers `bbh_work`, `bbh_demand`, `bbh_skip`, `bbh_fail`,
`bbh_absolutise` for gates that want them; nothing requires them.

## 3. The header (line 2 is an API)

Line 1 is `#!/bin/sh`. Line 2 is `# <name>.sh — <claim>`, and the header
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

A gate prints its findings and ends with ONE line that states its verdict
in its own words — `PASS: <what held>` or `FAIL: <what did not>`. The runner
does not grep for those words (it reads the exit status), but a human
reading a log does, and a PASS row whose log has NO verdict line of the
gate's own is read as a crash until proven otherwise.

## 5. The must-fire control (a check that cannot fail is not a check)

Every gate that asserts a property PERTURBS an input and requires its own
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

## 6. Registration (a gate that is not in a registry is not run)

A gate that needs no instrument is in `ci_portable.txt` (runs on a clean
checkout) or `ci_static.txt` (needs the input the consumer names in
`[registries].static_needs_env`, or a build dir, but no instrument). A gate
that reaches an instrument — directly, or through a sourced lib — belongs to
the sweep registry (H4) and to neither plain one. `bbh run-static` reports
every instrument-free gate that is in neither; `bbh run-sweep --strict`
fails on an unregistered instrument gate and on a registered gate that no
longer exists. That report is the anti-orphan mechanism: without it a runner
is just a smaller thing to forget to update.

## 7. What the harness will NOT do

It will not read a gate's code to decide anything, will not guess a skip
from prose, will not count a self-skipping gate as a pass, will not edit a
running script (the shell reads by byte offset), and will not weaken the
classifier to make a consumer green: a delta between this classifier and
a consumer's older one is a FINDING about the consumer.
