#!/bin/sh
# test_skills.sh — ground truth for the skills lock (bbh check-skills) and the
# guide generator (bbh skill-guide), H10. ROM-free, ~2 s.
#
# WHY. A skill loads BEFORE the work, so a stale one is a confidently wrong
# instruction; the lock exists so a deleted paragraph, an unanchored rule, a
# forbidden token, an uncited number or a dangling cross-reference FAILS
# instead of being loaded. A lock that does not fire is worse than none, so
# every check below is a MUST-FIRE control on a perturbed copy of a
# synthetic consumer (the lineage's gate, tests/test_checkskills.sh, runs
# the same shapes on copies of its real tree).
#
# Then, when the harness's own skill exists (skill/skills.toml), the real
# lock runs on this tree and its guide must be current.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM

# ── a synthetic consumer: two skills, a doc, a log, a history twin ──────────
mk() {  # mk <dir>
    mkdir -p "$1/skills/aa" "$1/skills/bb" "$1/docs"
    cat > "$1/bbh.toml" <<'EOF'
[project]
root = "."
[skills]
prefixes = ["AA", "BB"]
history_exempt = ["docs/archive_history.md"]
guided = ["AA"]
guide_origin = "a synthetic project"
[skill_AA]
path = "skills/aa/SKILL.md"
docs = ["docs/ref.md", "docs/rolling.md"]
logs = ["docs/ref.md", "docs/ref_history.md", "docs/archive_history.md"]
forbid = ["vsav", "[ZZ-"]
sections = [["docs/rolling.md", "## Standing"]]
[skill_BB]
path = "skills/bb/SKILL.md"
docs = ["docs/ref.md"]
logs = ["docs/ref.md"]
forbid = []
EOF
    printf -- '---\nname: aa\ndescription: the first\n---\n# The first skill\n\n## 1. Rules\n\n- [AA-1] rule one quotes 0x600000 and cites [BB-1].\n- [AA-2] rule two, anchored in the rolling file.\n' > "$1/skills/aa/SKILL.md"
    printf -- '---\nname: bb\ndescription: the second\n---\n# The second skill\n\n## 1. Rules\n\n- [BB-1] rule one of the second.\n' > "$1/skills/bb/SKILL.md"
    printf -- '# Ref\n\n## Things\n\nThe first paragraph. **[AA-1]** The rule one paragraph, with its incident.\n\nAnother. **[BB-1]** The second skill'"'"'s rule.\n' > "$1/docs/ref.md"
    printf -- '# Rolling\n\n## Standing\n\n**[AA-2]** The standing paragraph.\n\n## Sessions\n\nsession notes that roll over\n' > "$1/docs/rolling.md"
    printf -- '# Ref history\n\n2026-01-01 measured 0x600000.\n' > "$1/docs/ref_history.md"
    printf -- '# Archive\n\nold sessions, no anchors\n' > "$1/docs/archive_history.md"
}
run() { _d="$1"; shift; (cd "$_d" && "$BBH_HOME/bin/bbh" check-skills --config bbh.toml "$@" 2>&1); }

echo "== 1. a matched synthetic consumer PASSES, and the guide generates and checks current =="
mk "$T/base"
o="$(run "$T/base" -v)" && ok "check-skills PASS: $(printf '%s\n' "$o" | tail -1)" || { fail "the matched tree FAILS:"; printf '%s\n' "$o" | sed 's/^/        /'; }
printf '%s\n' "$o" | grep -q '^  AA: 2 rules defined in skills/aa/SKILL.md$' && ok "-v lists each skill's rule count in [skills].prefixes order" || fail "-v listing: $(printf '%s\n' "$o" | head -2 | tr '\n' '|')"
(cd "$T/base" && "$BBH_HOME/bin/bbh" skill-guide --config bbh.toml >/dev/null 2>&1) && [ -s "$T/base/skills/aa/GUIDE.md" ] && ok "skill-guide wrote skills/aa/GUIDE.md" || fail "skill-guide did not write the guide"
grep -q '^# The first skill — the guide$' "$T/base/skills/aa/GUIDE.md" && grep -q 'Origin: a synthetic project' "$T/base/skills/aa/GUIDE.md" && ok "the guide's header carries the title and the configured origin" || fail "guide header wrong: $(head -8 "$T/base/skills/aa/GUIDE.md" | tr '\n' '|')"
grep -q '^> The first paragraph. The rule one paragraph, with its incident.$' "$T/base/skills/aa/GUIDE.md" && ok "the incident is the anchored paragraph with the marker stripped" || fail "incident block wrong: $(grep -n '^>' "$T/base/skills/aa/GUIDE.md" | head -3 | tr '\n' '|')"
grep -q '\*\*\[AA-' "$T/base/skills/aa/GUIDE.md" && grep -qv 'AA-1\]\*\* ' "$T/base/skills/aa/GUIDE.md" && :; grep -q '^\*\*\[AA-1\]\*\* rule one' "$T/base/skills/aa/GUIDE.md" && ok "the rule is quoted verbatim under its ID" || fail "the rule line is not in the guide"
gc="$(cd "$T/base" && "$BBH_HOME/bin/bbh" skill-guide --config bbh.toml --check 2>&1)" && ok "skill-guide --check: $gc" || fail "--check on a fresh guide: $gc"

echo "== 2. MUST-FIRE — each perturbation fails for its stated reason =="
control() {  # control <label> <dir> <expected substring>
    if o="$(run "$2" --no-selftest)"; then
        fail "$1: the perturbed copy PASSED — the check is not checking"
    elif printf '%s\n' "$o" | grep -q "$3"; then
        ok "$1: fires ($3)"
    else
        fail "$1: failed for the wrong reason:"; printf '%s\n' "$o" | sed 's/^/        /'
    fi
}
mk "$T/a"; printf -- '- [AA-9] a rule nobody anchored\n' >> "$T/a/skills/aa/SKILL.md"
control "unanchored rule" "$T/a" "ANCHORED NOWHERE: AA-9"
mk "$T/b"; sed -i.bak 's/\*\*\[AA-1\]\*\* //' "$T/b/docs/ref.md"
control "stripped anchor" "$T/b" "ANCHORED NOWHERE: AA-1"
mk "$T/c"; printf -- '\n**[AA-7]** an orphan anchor\n' >> "$T/c/docs/ref.md"
control "orphan anchor" "$T/c" "NOT DEFINED in the skill: AA-7"
mk "$T/d"; printf -- '\nA note that names vsav by name.\n' >> "$T/d/skills/aa/SKILL.md"
control "forbidden token" "$T/d" "level-1 skill names 'vsav'"
mk "$T/e"; printf -- '\nThe magic figure is 0xDEADBEEF1.\n' >> "$T/e/skills/aa/SKILL.md"
control "number in no log" "$T/e" "in NO log: 0xDEADBEEF1"
mk "$T/f"; printf -- '- [AA-3] cites [BB-8], which BB never defined.\n' >> "$T/f/skills/aa/SKILL.md"; printf -- '\n**[AA-3]** anchor three.\n' >> "$T/f/docs/ref.md"
control "dangling cross-reference" "$T/f" "cross-reference \[BB-8\]"
mk "$T/g"; printf -- '- [AA-3] cites [ZZ-1], a skill outside the table.\n' >> "$T/g/skills/aa/SKILL.md"; printf -- '\n**[AA-3]** anchor three.\n' >> "$T/g/docs/ref.md"
control "a foreign prefix barred by a forbid token" "$T/g" "level-1 skill names '\[ZZ-'"
mk "$T/h"; printf -- '\n**[AA-2]** moved into the twin\n' >> "$T/h/docs/ref_history.md"; sed -i.bak 's/\*\*\[AA-2\]\*\* //' "$T/h/docs/rolling.md"
control "anchor in a history twin" "$T/h" "anchored in HISTORY file docs/ref_history.md"
mk "$T/i"; printf -- '\n**[AA-5]** an anchor in the rolling part\n' >> "$T/i/docs/rolling.md"; printf -- '- [AA-5] a rule anchored where the file rolls\n' >> "$T/i/skills/aa/SKILL.md"
control "anchor outside the named sections" "$T/i" "AA-5 anchored in docs/rolling.md OUTSIDE"
mk "$T/j"; (cd "$T/j" && "$BBH_HOME/bin/bbh" skill-guide --config bbh.toml >/dev/null 2>&1); printf -- '\nA sentence appended to the doc after the guide was generated.\n' >> "$T/j/docs/ref.md"
# the appended sentence joins the anchored paragraph? no — a blank line separates; perturb the RULE instead
sed -i.bak 's/rule two, anchored/rule two, REWORDED, anchored/' "$T/j/skills/aa/SKILL.md"
if (cd "$T/j" && "$BBH_HOME/bin/bbh" skill-guide --config bbh.toml --check >"$T/j/gc.log" 2>&1); then fail "stale guide: --check PASSED after the skill changed"
else grep -q "is STALE" "$T/j/gc.log" && ok "stale guide: --check fires (is STALE)" || { fail "stale guide: wrong reason:"; sed 's/^/        /' "$T/j/gc.log"; }; fi

echo "== 3. the tool's own synthetic selftest runs by default and passes =="
o="$(run "$T/base")" && ok "check-skills without --no-selftest: $(printf '%s\n' "$o" | tail -1)" || { fail "the internal selftest failed:"; printf '%s\n' "$o" | sed 's/^/        /'; }

echo "== 4. a config with no skill is refused, not passed =="
mkdir -p "$T/none"; printf '[project]\nroot = "."\n' > "$T/none/bbh.toml"
if run "$T/none" >"$T/none/log" 2>&1; then fail "an empty [skills] PASSED"; else grep -q "names no skill" "$T/none/log" && ok "no skill configured: refused (exit $?)" || { fail "empty config: wrong reason"; sed 's/^/        /' "$T/none/log"; }; fi

echo "== 5. the harness's OWN skill, when it exists =="
if [ -f "$BBH_HOME/skill/skills.toml" ]; then
    o="$("$BBH_HOME/bin/bbh" check-skills --config "$BBH_HOME/skill/skills.toml" -v 2>&1)" && ok "skill/skills.toml: $(printf '%s\n' "$o" | tail -1)" || { fail "the harness's own skill is NOT locked:"; printf '%s\n' "$o" | sed 's/^/        /'; }
    o="$("$BBH_HOME/bin/bbh" skill-guide --config "$BBH_HOME/skill/skills.toml" --check 2>&1)" && ok "$o" || { fail "the harness's own guide is stale:"; printf '%s\n' "$o" | sed 's/^/        /'; }
else
    echo "  (no skill/skills.toml yet — the harness's own skill is not written; sections 1-4 are the lock's ground truth)"
fi

echo
[ "$rc" = 0 ] && echo "PASS: the skills lock fires on every perturbation and the guide follows the docs" || { echo "FAIL: see above"; exit 1; }
