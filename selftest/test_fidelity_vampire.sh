#!/bin/sh
# test_fidelity_vampire.sh — FIDELITY against the lineage: the generic runner
# and this harness's tier classifier reproduce Project VAMPIRE SAVED's
# verdicts over the SAME input (harness_scope.md §5 there). SKIPs when that
# tree is not beside this one. ROM-free, ~5 s (F2 opt-in, ~2 min).
#
#   F1  both static runners over one synthetic fake repo of stub gates:
#       output identical (durations normalised); with a gate that exits 0
#       after a shell error, the diff is EXACTLY the known delta — this
#       classifier is the STRONGER copy (the lineage's static runner has no
#       shell-error branch; its sweep runner does).
#   F3  the tier classifier over the lineage's 304 gates: the INSTRUMENT set
#       minus the plain registries minus `run_` names == its sweep registry;
#       every PLAIN gate is in a plain registry; every sweep row exists.
#   F2  (BBH_FIDELITY_F2=1) the lineage's whole portable tier through both
#       runners, verdict columns diffed — never alongside another gate run
#       in that tree.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
CFG="$BBH_HOME/example/consumers/bbh.vampire.toml"
V="$(python3 -m bbh.config "$CFG" root 2>/dev/null || true)"
[ -n "$V" ] && [ -x "$V/tests/run_all_static.sh" ] || { echo "SKIP: the lineage tree is not at $V (fidelity needs it)"; exit 0; }
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
norm() { sed -E 's/ +[0-9]+s( |$)/ Ns\1/g'; }

echo "== F1. both static runners over one synthetic fake repo =="
FR="$T/fake"; mkdir -p "$FR/tests"; ln -s "$V/tests/run_all_static.sh" "$FR/tests/run_all_static.sh"
printf '[project]\nroot = "."\n' > "$FR/bbh.toml"
mk() { n="$1"; st="$2"; shift 2; { echo "#!/bin/sh"; for l in "$@"; do echo "echo '$l'"; done; echo "exit $st"; } > "$FR/tests/$n.sh"; chmod +x "$FR/tests/$n.sh"; }
mk g_pass 0 "all good" "PASS: fine"; mk g_fail 1 "something broke" "FAIL: nope"; mk g_skip 0 "SKIP: no build at build/nope"
mk g_skip_indent 0 "  SKIP: indented skip marker"; mk g_prose 0 "checked 3 things, none had to be skipped" "PASS: prose only"
mk g_skip_fail 2 "  SKIPPED: no reference binary" "PARTIAL: the invariant was NOT run"
mk g_segv 0 "PASS: summary" "tests/g_segv.sh: line 64:  2444 Segmentation fault: 11  REPLAY=x"
mk g_exit3 3 "boom"; mk g_orphan 0 "PASS: nobody registered me"
printf '#!/bin/sh\nMAME_BIN=x tools/run_mame.sh vsavj\n' > "$FR/tests/g_emu.sh"; chmod +x "$FR/tests/g_emu.sh"
printf 'g_pass\ng_fail\ng_skip\ng_skip_indent\ng_prose\ng_skip_fail\ng_segv\ng_exit3\nno_such\n' > "$FR/tests/ci_portable.txt"; : > "$FR/tests/ci_static.txt"
(cd "$FR" && sh tests/run_all_static.sh --tier portable 2>&1; echo "exit=$?") | norm > "$T/a.txt"
(cd "$FR" && "$BBH_HOME/bin/bbh-run-static" --config bbh.toml --tier portable 2>&1; echo "exit=$?") | norm > "$T/b.txt"
if diff "$T/a.txt" "$T/b.txt" > "$T/d.txt"; then ok "F1: identical output over 9 stub gates + a MISSING + an orphan + an emulator gate"
else fail "F1: the runners differ:"; sed 's/^/        /' "$T/d.txt"; fi
mk g_shellcrash 0 "tests/g_shellcrash.sh: line 3: FOO: set FOO to a dir OUTSIDE the repo"; echo g_shellcrash >> "$FR/tests/ci_portable.txt"
(cd "$FR" && sh tests/run_all_static.sh --tier portable 2>&1; echo "exit=$?") | norm > "$T/a2.txt"
(cd "$FR" && "$BBH_HOME/bin/bbh-run-static" --config bbh.toml --tier portable 2>&1; echo "exit=$?") | norm > "$T/b2.txt"
diff "$T/a2.txt" "$T/b2.txt" > "$T/d2.txt" || true
if grep -q '^<   g_shellcrash .*PASS' "$T/d2.txt" && grep -q '^>   g_shellcrash .*FAIL Ns  (exit 0 after a shell error)' "$T/d2.txt" \
   && [ "$(grep -c '^[<>]' "$T/d2.txt")" = 7 ]; then
    ok "F1: with a shell-crash gate the diff is EXACTLY the known delta (lineage PASS, generic FAIL; 7 diff lines: the row, its tail, the tally, the failed list)"
else fail "F1: unexpected delta with the shell-crash gate:"; sed 's/^/        /' "$T/d2.txt"; fi

echo "== F3. the tier classifier over the lineage's gates =="
python3 - "$CFG" "$V" <<'EOF' || rc=1
import subprocess, os, sys
cfg, root = sys.argv[1], sys.argv[2]
kind = {l.split("\t")[0]: l.split("\t")[1] for l in subprocess.check_output(["python3", "-m", "bbh.tier", cfg, "--list"], text=True).splitlines()}
reg = lambda p: {l.split("#")[0].strip() for l in open(os.path.join(root, p))} - {""}
plain_reg = reg("tests/ci_portable.txt") | reg("tests/ci_static.txt")
sweep = {l.split("\t")[0] for l in open(os.path.join(root, "tests/ci_emulator.tsv")) if l.strip() and not l.startswith("#")}
runners = {g for g in kind if g.startswith("run_")}
inst = {g for g, k in kind.items() if k == "INSTRUMENT"} - plain_reg - runners
plain = {g for g, k in kind.items() if k == "PLAIN"} - runners
bad = 0
def chk(cond, msg, extra):
    global bad
    print(("  ok    " if cond else "  FAIL  ") + msg + ("" if cond else ": " + ", ".join(sorted(extra))))
    bad |= not cond
chk(inst == sweep, f"F3a: INSTRUMENT − plain registries − run_ == the sweep registry ({len(sweep)} rows)", inst ^ sweep)
chk(plain <= plain_reg, f"F3b: every PLAIN gate ({len(plain)}) is in a plain registry", plain - plain_reg)
chk(sweep <= set(kind), "F3d: every sweep row names an existing gate", sweep - set(kind))
sys.exit(1 if bad else 0)
EOF
un="$(python3 -m bbh.tier "$CFG" --unregistered)"
[ "$un" = "  ok: every emulator-free gate is registered" ] && ok "F3c: --unregistered prints the lineage's ok line verbatim" || fail "F3c: '$un'"

echo "== F5. the masked vocabulary: every .masked spec through BOTH implementations =="
# Each spec is paired with a DIFFERENT set's frozen log of the same stem
# (mostly FAIL verdicts, which is the point: the text and the class
# arithmetic must match to the character), else with its own basis log.
# BBH_FIDELITY_F5=<N> samples every Nth spec; the default 4 (~60 s) keeps
# the routine gate short, and a slice's pre-commit runs 1 (all 1,891, ~4 min).
step="${BBH_FIDELITY_F5:-4}"; n5=0; same5=0; diff5=0; k=0; t5=$(date +%s)
for spec in "$V"/tests/expected/*/*.masked; do
    k=$((k + 1)); [ $((k % step)) = 0 ] || continue
    set5="$(dirname "$spec")"; name5="$(basename "$spec" .masked)"; text5="$(cat "$spec")"
    base5="$(printf '%s' "$text5" | awk '{print $2}')"
    cand=""
    for d in "$V"/tests/expected/*/logs/"$name5".log "$V"/tests/expected/*/*/logs/"$name5".log; do
        [ -f "$d" ] || continue
        case "$d" in "$V/tests/expected/$base5/logs/"*) continue ;; esac
        cand="$d"; break
    done
    [ -n "$cand" ] || cand="$V/tests/expected/$base5/logs/$name5.log"
    [ -f "$cand" ] || continue
    n5=$((n5 + 1))
    a5="$(cd "$V" && REPO="$V" sh -c '. tests/lib/masked_compare.sh; m=$(masked_mask_for "$1"); masked_check "$1" "$2" "$3" "$m" "$4"; echo "rc=$?"' _ "$set5" "$name5" "$text5" "$cand" 2>&1)"
    b5="$(sh -c '. "$BBH_HOME/lib/sh/masked_compare.sh"; m=$(masked_mask_for "$1"); masked_check "$1" "$2" "$3" "$m" "$4"; echo "rc=$?"' _ "$set5" "$name5" "$text5" "$cand" 2>&1)"
    if [ "$a5" = "$b5" ]; then same5=$((same5 + 1)); else
        diff5=$((diff5 + 1)); [ $diff5 -le 3 ] && { echo "  DIFF $spec vs $cand"; printf '%s\n' "$a5" | sed 's/^/        lineage| /'; printf '%s\n' "$b5" | sed 's/^/        bbh    | /'; }
    fi
done
[ "$n5" -gt 0 ] && [ "$diff5" = 0 ] && ok "F5: $n5 spec(s) (every ${step}th), verdict text identical to the character, $(( $(date +%s) - t5 )) s" \
    || fail "F5: $n5 specs, $diff5 differ"

echo "== F2. the lineage's portable tier through both runners (opt-in) =="
if [ "${BBH_FIDELITY_F2:-0}" = 1 ]; then
    (cd "$V" && sh tests/run_all_static.sh --tier portable 2>&1; echo "exit=$?") | norm > "$T/p_a.txt"
    (cd "$V" && "$BBH_HOME/bin/bbh-run-static" --config "$CFG" --tier portable 2>&1; echo "exit=$?") | norm > "$T/p_b.txt"
    if diff "$T/p_a.txt" "$T/p_b.txt" > "$T/p_d.txt"; then ok "F2: the whole portable tier — identical output ($(grep -c ' PASS Ns' "$T/p_a.txt") PASS rows)"
    else fail "F2: the portable tier differs:"; sed 's/^/        /' "$T/p_d.txt" | head -20; fi
else
    echo "  (not run: set BBH_FIDELITY_F2=1 — ~2 min, and never beside another gate run in the lineage tree)"
fi

echo
[ "$rc" = 0 ] && echo "PASS: the generic harness reproduces the lineage's verdicts" || { echo "FAIL: see above"; exit 1; }
