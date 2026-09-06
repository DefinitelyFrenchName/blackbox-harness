# prologue.sh — helpers for gate AUTHORS. Source it after `set -eu`:
#
#     . "$BBH_HOME/lib/sh/prologue.sh"
#
#   bbh_demand VAR "message"   an explicit demand that is SAFE AFTER A TRAP:
#                              prints `FAIL: message`, exits 1 — never the
#                              `${VAR:?}` form, which exits 0 on macOS bash
#                              3.2 once an EXIT trap is armed
#   bbh_work                   W=$(mktemp -d) + `trap 'rm -rf "$W"' EXIT INT TERM`
#   bbh_skip "reason"          the SKIP contract: `SKIP: reason` on its own
#                              line, exit 0 — the ONLY shape a runner reads as
#                              a skip; a skip that must be loud under a
#                              release policy uses bbh_fail instead
#   bbh_fail "reason"          `FAIL: reason`, exit 1
#   bbh_absolutise VAR         make a path variable absolute (a relative
#                              input dir failed two gates that resolve it
#                              from another working directory)
#
# THE GATE CONTRACT these serve is docs/gate_contract.md: line 2 is
# `# <name>.sh — <claim>`; demands BEFORE the trap or through bbh_demand;
# one verdict line of the gate's own; exit status decides first.

bbh_demand() {
    eval "_v=\${$1:-}"
    if [ -z "$_v" ]; then
        echo "FAIL: $2"
        exit 1
    fi
}

bbh_work() {
    W="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$W'" EXIT INT TERM
    export W
}

bbh_skip() {
    echo "SKIP: $*"
    exit 0
}

bbh_fail() {
    echo "FAIL: $*"
    exit 1
}

bbh_absolutise() {
    eval "_p=\${$1:-}"
    [ -n "$_p" ] || return 0
    _a="$(CDPATH= cd "$_p" 2>/dev/null && pwd)" || {
        echo "FAIL: $1 '$_p' does not resolve from $(pwd)" >&2
        exit 2
    }
    eval "$1=\"\$_a\""
    export "$1"
}
