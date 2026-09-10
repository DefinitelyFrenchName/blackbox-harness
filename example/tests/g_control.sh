#!/bin/sh
# g_control.sh — a gate under THE MUST-FIRE CONTRACT: its control is DECLARED
# in this header, FIRED at run time as a column-0 line, and EXECUTABLE as a
# mode (`CONTROL=flip tests/g_control.sh` must reach this gate's own FAIL).
# The property: the registry's first entry is a gate that exists. ROM-free,
# ~0 s.
#
# MUST-FIRE: perturbed-copy: flip — a copy of the registry whose first entry names a gate that does not exist must FAIL the check; the plain copy must pass
#
# THE PATTERN. One `perturb` function writes the perturbed copy; the control
# section and the mode both call it, so what the mode proves is exactly what
# the control claims. Under the mode the perturbed copy becomes the INPUT the
# main check reads.
#
# Usage: tests/g_control.sh
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO"
BBH_HOME="${BBH_HOME:-$(cd "$REPO/.." && pwd)}"
. "$BBH_HOME/lib/sh/controls.sh"
bbh_ctl_mode "$0"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT INT TERM

check() {  # check <registry> — the property: the first entry names an existing gate
    _first="$(grep -v '^#' "$1" | awk 'NF{print; exit}')"
    [ -n "$_first" ] && [ -f "tests/$_first.sh" ]
}
perturb() {  # perturb <copy> — the first entry becomes a gate that does not exist
    { echo "no_such_gate"; cat tests/ci_portable.txt; } > "$1"
}

REG=tests/ci_portable.txt
if bbh_ctl_is flip; then perturb "$W/reg.mode"; REG="$W/reg.mode"; fi

# the control: the perturbed copy must FAIL the check
perturb "$W/reg.ctl"
if check "$W/reg.ctl"; then bbh_ctl_dead flip "the perturbed registry passed the check" || exit 1
else bbh_ctl_fired flip "the perturbed registry fails the check (first entry no_such_gate)"; fi

check "$REG" || { echo "FAIL: the registry's first entry does not name an existing gate ($REG)"; exit 1; }
echo "PASS: the registry's first entry names an existing gate"
