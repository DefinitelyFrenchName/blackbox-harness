#!/bin/sh
# test_profiles.sh — the machine profiles: every shipped profile declares
# every REQUIRED key (statically, so it runs on a host with no lua), the
# TEMPLATE carries every key any script reads, cps2w derives from cps2, and
# — under a standalone lua — profile.lua LOADS each one and REFUSES a
# profile missing a required key (the must-fire). ~1 s.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
L="$BBH_HOME/lua/mame"

echo "== 1. every profile declares the required keys (static) =="
REQ="name cpu space ram sides ports"
CRASH="vectors vector_stride group0 pc_at_sp addr_at_sp code stack_top pc_mask regs sp"
for p in "$L"/profiles/*.lua; do
    n="$(basename "$p")"
    case "$n" in cps2w.lua) continue ;; esac   # derives from cps2 (checked below)
    miss=""
    for k in $REQ; do grep -Eq "^\s*$k\s*=" "$p" || miss="$miss $k"; done
    [ -z "$miss" ] && ok "$n: the required keys" || fail "$n: missing$miss"
    miss=""
    for k in $CRASH; do grep -Eq "^\s*$k\s*=" "$p" || miss="$miss $k"; done
    [ -z "$miss" ] && ok "$n: the guard's crash keys" || fail "$n: crash. missing$miss"
done
# every key any lua/mame script reads from the profile (P.x / C.x) is in the TEMPLATE
keys="$(grep -ohE '\b(P|C)\.[a-z_0-9]+' "$L"/*.lua | sed 's/^[PC]\.//' | sort -u | grep -Ev '^(path|crash)$')"
miss=""
for k in $keys; do grep -Eq "^\s*$k\s*=" "$L/profiles/TEMPLATE.lua" || miss="$miss $k"; done
[ -z "$miss" ] && ok "TEMPLATE.lua carries every key a script reads ($(printf '%s\n' $keys | wc -l | tr -d ' ') keys)" || fail "TEMPLATE.lua lacks$miss"
grep -q 'cps2.lua' "$L/profiles/cps2w.lua" && grep -q 'code = { lo = 0x000100, hi = 0x600000 }' "$L/profiles/cps2w.lua" && ok "cps2w.lua derives from cps2.lua and widens only the code window" || fail "cps2w derivation"
# profile.lua's REQUIRED list equals this test's (so neither rots alone)
for k in $REQ; do grep -q "\"$k\"" "$L/profile.lua" || fail "profile.lua's REQUIRED lacks '$k'"; done
ok "profile.lua's REQUIRED list agrees with this test's"

echo "== 2. under a standalone lua: the loader loads each profile and refuses a broken one =="
LUA=""; for l in lua lua5.4 lua5.3 luajit; do command -v "$l" >/dev/null 2>&1 && { LUA="$l"; break; }; done
if [ -z "$LUA" ]; then
    echo "  (not run: no standalone lua on this host — the loader is exercised under MAME by fidelity F8)"
else
    for p in "$L"/profiles/*.lua; do
        n="$(basename "$p")"
        o="$($LUA -e "local pr = dofile('$L/profile.lua'); local P = pr.load('$p'); pr.require_crash(P); print(P.name, #P.ports)" 2>&1)" \
            && ok "$n loads: $o" || fail "$n: $o"
    done
    sed 's/^\s*ports\s*=.*$//' "$L/profiles/cps2.lua" > "$T/noports.lua"
    o="$($LUA -e "dofile('$L/profile.lua').load('$T/noports.lua')" 2>&1)" && fail "MUST-FIRE: a profile without 'ports' loaded" \
        || { printf '%s' "$o" | grep -q "missing required key 'ports'" && ok "MUST-FIRE: a profile missing 'ports' is refused by name" || fail "refusal text: $o"; }
    o="$($LUA -e "BBH_PROFILE=nil; dofile('$L/profile.lua').load()" 2>&1)" && fail "no BBH_PROFILE loaded something" \
        || { printf '%s' "$o" | grep -q "set BBH_PROFILE" && ok "no BBH_PROFILE: refused, the variable named" || fail "$o"; }
fi

echo
[ "$rc" = 0 ] && echo "PASS: the machine profiles" || { echo "FAIL: see above"; exit 1; }
