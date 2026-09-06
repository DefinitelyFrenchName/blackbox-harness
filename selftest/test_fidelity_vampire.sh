#!/bin/sh
# test_fidelity_vampire.sh — FIDELITY against the lineage: the generic runner
# and this harness's tier classifier reproduce Project VAMPIRE SAVED's
# verdicts over the SAME input (harness_scope.md §5 there). SKIPs when that
# tree is not beside this one. ROM-free, ~65 s with F5 sampled (F5 at every
# spec ~4 min; F2 opt-in, ~2 min).
#
#   F1  both static runners over one synthetic fake repo of stub gates:
#       output identical (durations normalised); with a gate that exits 0
#       after a shell error, the diff is EXACTLY the known delta — this
#       classifier is the STRONGER copy (the lineage's static runner has no
#       shell-error branch; its sweep runner does).
#   F3  the tier classifier over the lineage's 304 gates: the INSTRUMENT set
#       minus the plain registries minus `run_` names == its sweep registry;
#       every PLAIN gate is in a plain registry; every sweep row exists.
#   F5  every .masked spec of the lineage through both masked_compare
#       implementations, verdict text to the character (1,891/1,891 at H2).
#   F6  the fingerprint: both tools over the same images with every flag —
#       a synthetic dual-key twin always, the real reference set and a
#       sample of build dirs when ROMDIR is set (BBH_FIDELITY_F6=all: every
#       build dir).
#   F7  the suite's dispatch: both suite runners over the lineage's real
#       expectation trees in a shadow root with a STUB driver (no MAME),
#       every verdict line diffed (BBH_FIDELITY_F7=all: every set).
#   F4  the sweep runner: --list (always) and --dry-run (with ROMDIR) over
#       the lineage's whole registry through both runners, diffed.
#   F9  the hygiene tools: header-defaults, gate-index (--check, and the
#       rendered index against the committed file), provenance (the
#       lineage gate's first two sections), ref-rot (the lineage gate's
#       report) and demand-after-trap — the generic tool with the consumer
#       config against the lineage's, full stdout + exit status diffed.
#   F10 the field comparator and the dump checker over SYNTHETIC dump
#       directories shaped like the lineage's (its addresses, its fields
#       table, a driver-prefixed copy): every mode and every failure, stdout
#       + stderr + exit diffed.
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

echo "== F6. the fingerprint: both tools over the same images, every flag =="
# The synthetic twin (always): the dual-key shape on fabricated zips. The
# real images (when ROMDIR is set): the reference set and a SAMPLE of
# build/*/rompath dirs, BBH_FIDELITY_F6=all for every one. stdout + stderr +
# exit status, diffed — the NOTE and UNREGISTERED texts included.
LFP="python3 $V/tools/build_fingerprint.py"; GFP="python3 -m bbh.fingerprint"
REG6="$V/tests/expected/registry.tsv"; n6=0; d6=0
fp_pair() {  # fp_pair <rompath> <set> <registry> [flag]
    # set +e inside: an expected non-zero exit (an unregistered image) must be
    # RECORDED, not abort the capture under the test's own errexit
    a6="$( (set +e; $LFP "$1" --set "$2" --registry "$3" ${4:-} 2>&1; echo "rc=$?") )"
    b6="$( (set +e; cd "$V" && $GFP "$1" --set "$2" --registry "$3" ${4:-} 2>&1; echo "rc=$?") )"
    n6=$((n6 + 1))
    [ "$a6" = "$b6" ] || { d6=$((d6 + 1)); [ $d6 -le 3 ] && { echo "  DIFF $1 $2 ${4:-lookup}"; printf '%s\n' "$a6" | sed 's/^/        lineage| /'; printf '%s\n' "$b6" | sed 's/^/        bbh    | /'; }; }
}
python3 - "$T" <<'EOF'
import sys, zipfile, os
T = sys.argv[1]
def mk(d, s, members):
    os.makedirs(d, exist_ok=True)
    with zipfile.ZipFile(os.path.join(d, s + ".zip"), "w") as z:
        for n, v in members: z.writestr(n, v)
mk(f"{T}/s1", "vsavj", [("vsavj.04", b"BBBB"), ("vsavj.03", b"AAAA"), ("vsavj.13m", b"GFX1"), ("vsavj.key", b"K")])
mk(f"{T}/s2", "vsavj", [("vsavj.04", b"BBBB"), ("vsavj.03", b"AAAA"), ("vsavj.13m", b"GFX2"), ("vsavj.key", b"K")])
mk(f"{T}/s3", "vsav",  [("vsav.05", b"PPPP"), ("vsav.14m", b"PG")])
EOF
sk="$($GFP "$T/s1" --set vsavj --set-key)"; pk="$($GFP "$T/s1" --set vsavj --sha-only)"
printf '%s\tSETKEY\n' "$sk" > "$T/r_set.tsv"; printf '%s\tPROGKEY\n' "$pk" > "$T/r_prog.tsv"; printf '%s\tP\n%s\tS\n' "$pk" "$sk" > "$T/r_both.tsv"; : > "$T/r_none.tsv"
for rp in "$T/s1" "$T/s2" "$T/s1;$T/s3" "$T/s2;$T/s1"; do
    for fl in --sha-only --set-key --full; do fp_pair "$rp" vsavj "$T/r_none.tsv" "$fl"; done
    for r in r_set r_prog r_both r_none; do fp_pair "$rp" vsavj "$T/$r.tsv"; done
done
[ "$d6" = 0 ] && ok "F6 synthetic: $n6 invocations over the dual-key twin (3 flags + 4 registries x 4 search paths), text and exit identical" || fail "F6 synthetic: $d6 of $n6 differ"
if [ -n "${ROMDIR:-}" ] && [ -d "$ROMDIR" ]; then
    n6=0; d6=0
    if [ "${BBH_FIDELITY_F6:-}" = all ]; then dirs="$(ls -d "$V"/build/*/rompath 2>/dev/null)"
    else dirs="$V/build/m3b_merged23/rompath $V/build/don_stage4_m20/rompath $V/build/merged1/rompath"; fi
    for rp in "$ROMDIR" $dirs; do
        [ -d "$rp" ] || continue
        set6=vsavj; [ -f "$rp/vsavjw.zip" ] && set6=vsavjw
        for fl in --sha-only --set-key --full; do fp_pair "$rp" "$set6" "$REG6" "$fl"; done
        fp_pair "$rp" "$set6" "$REG6"; fp_pair "$rp;$ROMDIR" "$set6" "$REG6"
    done
    [ "$n6" -gt 0 ] && [ "$d6" = 0 ] && ok "F6 real: $n6 invocations over \$ROMDIR and $(printf '%s\n' $dirs | wc -l | tr -d ' ') build dir(s) (BBH_FIDELITY_F6=all for every one), identical" || fail "F6 real: $d6 of $n6 differ"
else
    echo "  (F6 real images not run: set ROMDIR)"
fi

echo "== F7. the suite's dispatch: both runners over the lineage's expectation trees, no MAME =="
# A SHADOW ROOT: the lineage's tests/ and tools/ symlinked in, except (a) a
# STUB driver that copies a candidate log (a DIFFERENT set's frozen log of
# the same stem, so most verdicts are FAILs with numbers in them, or the
# set's own logs for the PASS shapes), (b) COPIES of build_fingerprint.py
# and cps2_decrypt.py so `__file__` resolves inside the shadow, and (c) a
# synthetic registry mapping one fabricated zip per set to that set. Both
# runners then dispatch the real .masked / .skip / .pending / .sha1 files.
# BBH_FIDELITY_F7=all runs every set (~39, several minutes); the default
# three cover the .pending, .skip, every masked class and the .sha1 kinds.
S="$T/shadow"; mkdir -p "$S/tools" "$S/tests/expected"
for f in "$V"/tools/*; do ln -s "$f" "$S/tools/$(basename "$f")"; done
rm -f "$S/tools/run_replay_mame.sh" "$S/tools/build_fingerprint.py" "$S/tools/cps2_decrypt.py"
cp "$V/tools/build_fingerprint.py" "$V/tools/cps2_decrypt.py" "$S/tools/"
cat > "$S/tools/run_replay_mame.sh" <<'EOF'
#!/bin/sh
# the F7 stub driver: <set> <replay> <out> — copies the candidate log
n="$(basename "$2" .rpl)"
if [ -f "$F7_CAND/$n.log" ]; then cp "$F7_CAND/$n.log" "$3"; else printf '1 deadbeefdeadbeef\nEND 1\n' > "$3"; fi
EOF
chmod +x "$S/tools/run_replay_mame.sh"
ln -s "$V/tests/lib" "$S/tests/lib"; ln -s "$V/tests/replays" "$S/tests/replays"; ln -s "$V/tests/run_suite.sh" "$S/tests/run_suite.sh"
for d in "$V"/tests/expected/*; do [ "$(basename "$d")" = registry.tsv ] || ln -s "$d" "$S/tests/expected/$(basename "$d")"; done
printf '[project]\nroot = "."\n[suite]\ndriver = "tools/run_replay_mame.sh"\n' > "$S/bbh.toml"
: > "$S/tests/expected/registry.tsv"
if [ "${BBH_FIDELITY_F7:-}" = all ]; then sets7="$(cd "$V/tests/expected" && ls -d */ | tr -d / | grep -v '^vsavj$' | tr '\n' ' ') vsavj"
else sets7="donovan-m20 huitzil-m13 vsavj"; fi
n7=0; d7=0; t7=$(date +%s)
for set7 in $sets7; do
    [ -d "$V/tests/expected/$set7" ] || continue
    # a set with ANY dispatchable kind (ls fails when either glob is empty)
    { ls "$V/tests/expected/$set7"/*.masked >/dev/null 2>&1 || ls "$V/tests/expected/$set7"/*.sha1 >/dev/null 2>&1; } || continue
    python3 - "$S/rp_$set7" "$set7" <<'EOF'
import sys, zipfile, os
d, s = sys.argv[1], sys.argv[2]; os.makedirs(d, exist_ok=True)
with zipfile.ZipFile(os.path.join(d, "vsavj.zip"), "w") as z: z.writestr("vsavj.03", ("set:" + s).encode()); z.writestr("vsavj.key", b"K")
EOF
    printf '%s\t%s\n' "$(python3 -m bbh.fingerprint "$S/rp_$set7" --set vsavj --sha-only)" "$set7" >> "$S/tests/expected/registry.tsv"
    # candidate logs: the set's own (PASS shapes) for vsavj, else a sibling set's
    case "$set7" in
        vsavj) cand7="$V/tests/expected/vsavj/logs" ;;
        donovan-*) cand7="$V/tests/expected/donovan-m19/logs" ;;
        huitzil-*) cand7="$V/tests/expected/huitzil-m27/logs" ;;
        pyron-*) cand7="$V/tests/expected/pyron-m21/logs" ;;
        *) cand7="$V/tests/expected/donovan-m20/logs" ;;
    esac
    [ "$cand7" = "$V/tests/expected/$set7/logs" ] && [ "$set7" != vsavj ] && cand7="$V/tests/expected/vsavj/masked-v2/logs"
    a7="$(set +e; cd "$S" && ROMDIR="$S" MAME_ROMPATH="$S/rp_$set7" F7_CAND="$cand7" sh tests/run_suite.sh 2>&1; echo "exit=$?")"
    b7="$(set +e; cd "$S" && ROMDIR="$S" MAME_ROMPATH="$S/rp_$set7" F7_CAND="$cand7" "$BBH_HOME/bin/bbh-run-suite" --config "$S/bbh.toml" 2>&1; echo "exit=$?")"
    n7=$((n7 + 1))
    if [ "$a7" != "$b7" ]; then
        d7=$((d7 + 1)); [ $d7 -le 2 ] && { echo "  DIFF set $set7:"; printf '%s\n' "$a7" > "$T/a7.txt"; printf '%s\n' "$b7" > "$T/b7.txt"; diff "$T/a7.txt" "$T/b7.txt" | head -12 | sed 's/^/        /'; }
    fi
done
lines7="$(printf '%s\n' "$a7" | wc -l | tr -d ' ')"
[ "$n7" -gt 0 ] && [ "$d7" = 0 ] && ok "F7: $n7 expectation set(s) through both suite runners with the stub driver — every verdict line identical ($lines7 lines in the last, $(( $(date +%s) - t7 )) s; BBH_FIDELITY_F7=all for every set)" || fail "F7: $d7 of $n7 sets differ"

echo "== F4. the sweep registry: --list and --dry-run through both runners =="
# --list needs no input; --dry-run walks the preconditions (the ROM audit),
# the banners (builds fingerprinted, instruments) and every lane, so it needs
# ROMDIR. Both sides run with MAME_BIN unset so the env-default line reads
# "(runner default)" on both; the log dir differs by argument and is
# normalised.
LSW="sh $V/tests/run_all_emulator.sh"; GSW="$BBH_HOME/bin/bbh-run-sweep --config $CFG"
a4="$(set +e; cd "$V" && unset MAME_BIN && $LSW --list --scope all --lane all 2>&1; echo "exit=$?")"
b4="$(set +e; cd "$V" && unset MAME_BIN && $GSW --list --scope all --lane all 2>&1; echo "exit=$?")"
[ "$a4" = "$b4" ] && ok "F4 --list: identical over the whole registry ($(printf '%s\n' "$a4" | wc -l | tr -d ' ') lines, --scope all --lane all)" \
    || { fail "F4 --list differs:"; printf '%s\n' "$a4" > "$T/a4.txt"; printf '%s\n' "$b4" > "$T/b4.txt"; diff "$T/a4.txt" "$T/b4.txt" | head -10 | sed 's/^/        /'; }
if [ -n "${ROMDIR:-}" ] && [ -d "$ROMDIR" ]; then
    a4d="$(set +e; cd "$V" && unset MAME_BIN && $LSW --dry-run --scope all --lane all --log "$T/sw_a" 2>&1; echo "exit=$?")"
    b4d="$(set +e; cd "$V" && unset MAME_BIN && $GSW --dry-run --scope all --lane all --log "$T/sw_b" 2>&1; echo "exit=$?")"
    a4d="$(printf '%s\n' "$a4d" | sed "s|$T/sw_a|LOG|g")"; b4d="$(printf '%s\n' "$b4d" | sed "s|$T/sw_b|LOG|g")"
    [ "$a4d" = "$b4d" ] && ok "F4 --dry-run: identical — the precondition, the fingerprinted builds, the instruments, every lane's resolved command, the coverage report ($(printf '%s\n' "$a4d" | wc -l | tr -d ' ') lines)" \
        || { fail "F4 --dry-run differs:"; printf '%s\n' "$a4d" > "$T/a4d.txt"; printf '%s\n' "$b4d" > "$T/b4d.txt"; diff "$T/a4d.txt" "$T/b4d.txt" | head -12 | sed 's/^/        /'; }
else
    echo "  (F4 --dry-run not run: set ROMDIR)"
fi

echo "== F9. the hygiene tools: the generic tool with the consumer config against the lineage's =="
# Each pair: the lineage tool or gate over its own tree, the harness tool
# with bbh.vampire.toml over the same tree; stdout + exit status diffed.
# ROM-free: every one reads the tree, never an image's content (ref-rot
# reads member NAMES of whatever build dirs are present — the same set on
# both sides).
f9_pair() {  # f9_pair <label> <lineage command> <harness command>
    a9="$( (set +e; cd "$V" && sh -c "$2" 2>&1; echo "exit=$?") )"
    b9="$( (set +e; cd "$V" && sh -c "$3" 2>&1; echo "exit=$?") )"
    if [ "$a9" = "$b9" ]; then ok "F9 $1: identical ($(printf '%s\n' "$a9" | wc -l | tr -d ' ') lines, exit $(printf '%s\n' "$a9" | tail -1 | sed 's/exit=//'))"
    else fail "F9 $1 differs:"; printf '%s\n' "$a9" > "$T/a9.txt"; printf '%s\n' "$b9" > "$T/b9.txt"; diff "$T/a9.txt" "$T/b9.txt" | head -12 | sed 's/^/        /'; fi
}
f9_pair header-defaults "python3 tools/audit_header_defaults.py" "$BBH_HOME/bin/bbh header-defaults --config $CFG"
f9_pair "gate-index --check" "python3 tools/gen_gate_index.py --check" "$BBH_HOME/bin/bbh gate-index --config $CFG --check"
"$BBH_HOME/bin/bbh" gate-index --config "$CFG" --stdout > "$T/gi9.md" 2>/dev/null || true
cmp -s "$T/gi9.md" "$V/docs/project/gate_index.md" && ok "F9 gate-index render: the regenerated index is byte-identical to the lineage's committed file" || fail "F9 gate-index render differs from the committed file"
f9_pair provenance "sh tests/test_expectation_provenance.sh | sed -n '/^== 1\./,/^== 3\./p' | sed '\$d'" "$BBH_HOME/bin/bbh provenance --config $CFG"
f9_pair ref-rot "sh tests/test_build_ref_rot.sh | sed '\$d' | sed '\$d'; exit 0" "$BBH_HOME/bin/bbh ref-rot --config $CFG; exit 0"
f9_pair demand-after-trap "sh tests/test_demand_after_trap.sh >/dev/null; echo checked" "$BBH_HOME/bin/bbh demand-after-trap tests --lib lib --skip test_demand_after_trap.sh; echo checked"

echo "== F10. the field comparator and the dump checker over synthetic lineage-shaped dumps =="
# Fabricated: two sides whose match-start predicate ($FF8004/$FF8008 .l ==
# 0x40000, both HPs 0x120) rises on DIFFERENT frames (2340 vs 2343), every
# field of tests/fields_m2a.tsv filled deterministically, one settled field
# differing after the anchor, a driver-prefixed copy, a side with a hole,
# a side whose window starts true. Both tools over every mode; the dump
# checker over every verdict. ROM-free.
python3 - "$T" <<'EOF'
import os, sys, shutil
T = sys.argv[1]
def side(name, edge, tweak=None, prefix="", frames=range(2300, 2420), hole=None, startstrue=False):
    d = f"{T}/f10_{name}"; os.makedirs(d, exist_ok=True)
    for f in frames:
        if f == hole: continue
        on = startstrue or f >= edge
        g = bytearray(0x300); p = bytearray(0x800)
        if on:
            g[4:8] = (0x40000).to_bytes(4, "big"); g[8:12] = (0x40000).to_bytes(4, "big")
        g[0x109] = (99 - (f - edge) // 60) & 0xFF if on else 0
        for base in (0, 0x400):
            p[base + 0x50:base + 0x52] = (0x120 if on else 0).to_bytes(2, "big"); p[base + 0x52:base + 0x54] = (0x120).to_bytes(2, "big")
            p[base + 0x60:base + 0x64] = (0xB0D2E + base).to_bytes(4, "big"); p[base + 0x64:base + 0x68] = (0x123456).to_bytes(4, "big")
            p[base + 0x132:base + 0x134] = (0x77).to_bytes(2, "big"); p[base + 0x109] = 3; p[base + 0x10A:base + 0x10C] = (0x40).to_bytes(2, "big")
            p[base + 0x10:base + 0x12] = (300 + base // 0x400 * 200).to_bytes(2, "big"); p[base + 0x14:base + 0x16] = (0).to_bytes(2, "big")
            p[base + 0x0A] = 0; p[base + 0x0B] = base // 0x400; p[base + 0x1C:base + 0x20] = (0x50000 + f).to_bytes(4, "big")
            p[base + 0x94:base + 0x98] = (f & 0xFF).to_bytes(4, "big"); p[base + 0x98] = 1
        if tweak: tweak(f, edge, g, p)
        open(f"{d}/{prefix}dump_{f}_ff8000.bin", "wb").write(g); open(f"{d}/{prefix}dump_{f}_ff8400.bin", "wb").write(p)
def tw(f, edge, g, p):
    if f >= edge + 120: p[0x10:0x12] = (301).to_bytes(2, "big")     # p1_x differs once settled
side("a", 2340); side("b", 2343, tw); side("c", 2343, tw, prefix="out.")
side("h", 2340, hole=2400); side("s", 2340, startstrue=True); side("t", 2340, frames=range(2300, 2352))
EOF
FT="$V/tests/fields_m2a.tsv"; n10=0; d10=0
f10_pair() {  # f10_pair <label> <lineage args…> -- <harness args…>  (same args both sides)
    lbl="$1"; shift
    a10="$( (set +e; cd "$V" && python3 tools/compare_fields.py "$@" 2>&1; echo "rc=$?") )"
    b10="$( (set +e; cd "$V" && python3 -m bbh.compare_fields --config "$CFG" "$@" 2>&1; echo "rc=$?") )"
    n10=$((n10 + 1)); [ "$a10" = "$b10" ] || { d10=$((d10 + 1)); [ $d10 -le 3 ] && { echo "  DIFF compare-fields $lbl"; printf '%s\n' "$a10" | sed 's/^/        lineage| /' | head -6; printf '%s\n' "$b10" | sed 's/^/        bbh    | /' | head -6; }; }
}
f10_pair anchors-a "$T/f10_a" --list-anchors
f10_pair anchors-starts-true "$T/f10_s" --list-anchors
f10_pair anchors-transient "$T/f10_t" --list-anchors
f10_pair anchor-mode "$T/f10_a" "$T/f10_b" --fields "$FT" --follow 0,30,60 --label-a mame --label-b fbneo
f10_pair anchor-settled "$T/f10_a" "$T/f10_b" --fields "$FT" --follow 0,120,240 --label-a mame --label-b fbneo
f10_pair anchor-prefixed "$T/f10_a" "$T/f10_c" --fields "$FT" --follow 0,120 --settle 100
f10_pair anchor-hole "$T/f10_a" "$T/f10_h" --fields "$FT" --follow 0,60
f10_pair exact "$T/f10_a" "$T/f10_b" --fields "$FT" --exact
f10_pair exact-skip "$T/f10_a" "$T/f10_b" --fields "$FT" --exact --skip-fields p1_anim_ptr,p2_anim_ptr,p1_box_ids,p2_box_ids
f10_pair no-dumps "$T/f10_none" --list-anchors
[ "$d10" = 0 ] && ok "F10 compare-fields: $n10 invocations (anchors, anchor mode with settled fields and a driver-prefixed side, a hole, --exact, --skip-fields, the errors), text and exit identical" || fail "F10 compare-fields: $d10 of $n10 differ"
n10=0; d10=0
f10_dumps() {  # f10_dumps <label> <args…>
    lbl="$1"; shift
    a10="$( (set +e; cd "$V" && python3 tools/check_wram_dumps.py "$@" 2>&1; echo "rc=$?") )"
    b10="$( (set +e; cd "$V" && python3 -m bbh.check_dumps --config "$CFG" "$@" 2>&1; echo "rc=$?") )"
    n10=$((n10 + 1)); [ "$a10" = "$b10" ] || { d10=$((d10 + 1)); [ $d10 -le 3 ] && { echo "  DIFF check-dumps $lbl"; printf '%s\n' "$a10" | sed 's/^/        lineage| /' | head -6; printf '%s\n' "$b10" | sed 's/^/        bbh    | /' | head -6; }; }
}
f10_dumps ok "$T/f10_a" --first 2300 --last 2419
f10_dumps ok-quiet "$T/f10_a" --first 2300 --last 2419 --quiet
f10_dumps contiguous "$T/f10_a" --contiguous
f10_dumps two-sizes "$T/f10_a" --contiguous --size 0x300
f10_dumps hole "$T/f10_h" --first 2300 --last 2419
f10_dumps hole-contig "$T/f10_h" --contiguous
f10_dumps outside "$T/f10_a" --first 2300 --last 2400
f10_dumps addr "$T/f10_a" --first 2300 --last 2419 --addr 0xFF8000
f10_dumps prefixed "$T/f10_c" --contiguous
f10_dumps nodir "$T/f10_none" --contiguous
f10_dumps empty "$V/tests/replays" --contiguous
[ "$d10" = 0 ] && ok "F10 check-dumps: $n10 invocations (complete, --quiet, --contiguous, mixed sizes, a hole both ways, outside, --addr, a prefixed side, no dir, no dumps), text and exit identical" || fail "F10 check-dumps: $d10 of $n10 differ"

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
