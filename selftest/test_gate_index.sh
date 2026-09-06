#!/bin/sh
# test_gate_index.sh — ground truth for lib/py/bbh/gen_gate_index.py and the
# header parser it reads through (gate_header.py): the index FOLLOWS the
# tree. ROM-free, ~2 s.
#
# The lineage's four controls (VampireSaved test_gate_index_current.sh) on a
# synthetic root: a fresh generation passes --check; a gate without a family
# row fails and the row clears it; a dead TSV row fails; a hand-edit fails
# the cmp. Then what the lineage never asserted: the RENDERED rows (kind,
# tier labels from the registries and the instrument word, needs derived
# from the header, the claim cut at the first paragraph, since from the
# session token), a family absent from the config is a PROBLEM (the
# must-fire on config), --stdout renders without writing, and the shipped
# example's committed index is current.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
W="$T/w"; mkdir -p "$W/tests" "$W/docs"
cat > "$W/bbh.toml" <<'EOF'
[project]
instrument_word = "emulator"
[registries]
portable = "tests/ci_portable.txt"
static = "tests/ci_static.txt"
static_needs_env = "ROMDIR"
[gate_header]
index_out = "docs/gate_index.md"
families_tsv = "tests/gate_index.tsv"
families = [["docs", "the docs"], ["platform", "the platform"]]
index_preamble = ["# Index", "", "generated."]
EOF
GI="python3 -m bbh.gen_gate_index --config $W/bbh.toml"
printf '#!/bin/sh\n# test_alpha.sh — a synthetic gate that locks the alpha law (14z-999). ROM-free, ~1 s.\n#\n# Usage: tests/test_alpha.sh\n# second paragraph, not the claim.\necho PASS\n' > "$W/tests/test_alpha.sh"
printf 'test_alpha\n' > "$W/tests/ci_portable.txt"; : > "$W/tests/ci_static.txt"
printf 'tests/test_alpha.sh\tdocs\n' > "$W/tests/gate_index.tsv"
$GI >/dev/null 2>&1 || fail "control setup: generation on the synthetic root failed"

echo "== 1. the lineage's four controls =="
$GI --check >/dev/null 2>&1 && ok "a: a freshly generated index passes --check" || fail "a: a fresh index FAILS --check"
printf '#!/bin/sh\n# audit_beta.sh — a synthetic audit with no family row; runs MAME on build/x for ~5 min.\n#\necho PASS\n' > "$W/tests/audit_beta.sh"
$GI --check >/dev/null 2>&1 && fail "b: a script with NO family row passed --check" || ok "b: a script with no family row fails --check"
printf 'tests/audit_beta.sh\tplatform\n' >> "$W/tests/gate_index.tsv"
$GI >/dev/null 2>&1
if $GI --check >/dev/null 2>&1 && grep -q 'audit_beta.sh.*audit.*emulator' "$W/docs/gate_index.md"; then
    ok "b: with the row the index passes and lists the audit (kind audit, tier emulator)"
else fail "b: the row did not clear the check / the row is missing"; fi
printf 'tests/test_gone.sh\tdocs\n' >> "$W/tests/gate_index.tsv"
$GI --check >/dev/null 2>&1 && fail "c: a TSV row for a missing script passed --check" || ok "c: a TSV row whose script is gone fails --check"
sed -i.bak '$d' "$W/tests/gate_index.tsv"; rm -f "$W/tests/gate_index.tsv.bak"
printf '| `tests/hand.sh` | test | x | x | x | x |\n' >> "$W/docs/gate_index.md"
$GI --check >/dev/null 2>&1 && fail "d: a hand-edited index passed --check" || ok "d: a hand-edited index fails --check"

echo "== 2. the rendered rows =="
$GI >/dev/null
IDX="$W/docs/gate_index.md"
row() { grep -F "$1" "$IDX" >/dev/null && ok "$2" || { fail "$2 — got: $(grep -F "$(printf '%s' "$1" | cut -c1-30)" "$IDX" || echo '(no such row)')"; }; }
row '| `tests/test_alpha.sh` | test | ci_portable | — | a synthetic gate that locks the alpha law (14z-999). ROM-free, ~1 s. | 14z-999 |' \
    "a portable gate: kind test, tier from the registry's name, needs —, the FIRST paragraph as the claim, since from the session token"
row '| `tests/audit_beta.sh` | audit | emulator | MAME, a build dir, ~5 min | a synthetic audit with no family row; runs MAME on build/x for ~5 min. | — |' \
    "an instrument gate: kind audit, tier = the instrument word, needs DERIVED (the instrument named, a build dir, the runtime), since —"
grep -q '^\*\*2 scripts\*\* — 1 ci_portable, 0 ci_static, 1 emulator-tier (run by name).$' "$IDX" && ok "the count line names the tiers by their registry stems and the instrument word" || fail "count line: $(grep scripts "$IDX" | head -1)"
grep -q '^| \[docs\](#docs) | 1 | the docs |$' "$IDX" && ok "the family table comes from [gate_header].families" || fail "family table"
head -3 "$IDX" | grep -q '^# Index$' && ok "the preamble is [gate_header].index_preamble" || fail "preamble"
$GI --stdout > "$T/so.md" && cmp -s "$T/so.md" "$IDX" && ok "--stdout renders the same text without writing" || fail "--stdout differs from the written file"

echo "== 3. MUST-FIRE on the config =="
sed 's/\["platform", "the platform"\]/["other", "x"]/' "$W/bbh.toml" > "$W/bbh2.toml"
o="$(python3 -m bbh.gen_gate_index --config "$W/bbh2.toml" --stdout 2>&1)" && fail "a family missing from the config passed" \
    || { printf '%s\n' "$o" | grep -q "PROBLEM UNKNOWN FAMILY 'platform'" && printf '%s\n' "$o" | grep -q '^## UNASSIGNED' && ok "a family the config does not define is a PROBLEM and the gate lands in UNASSIGNED" || fail "unknown family: $(printf '%s\n' "$o" | head -2)"; }
sed 's/instrument_word = "emulator"/instrument_word = "driver"/' "$W/bbh.toml" > "$W/bbh3.toml"
printf '#!/bin/sh\n# test_bare.sh — a bare gate.\n#\necho PASS\n' > "$W/tests/test_bare.sh"; printf 'tests/test_bare.sh\tdocs\n' >> "$W/tests/gate_index.tsv"
o3="$(python3 -m bbh.gen_gate_index --config "$W/bbh3.toml" --stdout)"
printf '%s\n' "$o3" | grep -q '| audit | driver | MAME, a build dir, ~5 min |' && ok "the instrument word renames the tier (needs still names the instrument the header does)" || fail "instrument word not applied to the tier"
printf '%s\n' "$o3" | grep -q '| `tests/test_bare.sh` | test | driver | driver | a bare gate. | — |' && ok "…and is the fallback of needs when the header names nothing" || fail "needs fallback: $(printf '%s\n' "$o3" | grep test_bare)"

echo "== 4. the shipped example =="
"$BBH_HOME/bin/bbh" gate-index --config "$BBH_HOME/example/bbh.toml" --check | grep -q '^ok    docs/gate_index.md is current' \
    && ok "example/docs/gate_index.md is current" || fail "the example's index is stale: regenerate it (bbh gate-index --config example/bbh.toml)"

echo
[ "$rc" = 0 ] && echo "PASS: the gate index follows the tree" || { echo "FAIL: see above"; exit 1; }
