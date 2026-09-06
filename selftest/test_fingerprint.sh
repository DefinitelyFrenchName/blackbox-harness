#!/bin/sh
# test_fingerprint.sh — ground truth for lib/py/bbh/fingerprint.py on
# SYNTHETIC images (no ROM): the registered/unregistered verdicts, THE DUAL
# KEY (a non-program delta gives the same program key and a different
# whole-set key; whole-set resolves silently, program loudly, whole-set wins,
# a whole-set-only row is unreachable by the program fallback, the key does
# not move with the search-path chain), --full's region rules, the
# [fingerprint] config keys, the file-sha1 and command kinds, and the
# example's committed images against their generator and registry. ~3 s.
#
# Lineage: VampireSaved's test_suite_dispatch.sh §1/1b, whose synthetic half
# needed no ROM either. MUST-FIRE: the whole-set-only row reached by the
# program fallback would be the merged-vs-blanks-instrument hazard; a
# perturbed image must fail the generator's --check.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
unset BBH_CONFIG
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
FP="python3 -m bbh.fingerprint"

mkzip() {  # mkzip <dir> <set> name=content ...
    python3 - "$@" <<'PY'
import sys, zipfile, os
d, s = sys.argv[1], sys.argv[2]
os.makedirs(d, exist_ok=True)
with zipfile.ZipFile(os.path.join(d, s + ".zip"), "w") as z:
    for kv in sys.argv[3:]:
        n, v = kv.split("=", 1); z.writestr(n, v.encode())
PY
}
sha1_of() { python3 -c 'import hashlib,sys; print(hashlib.sha1(sys.argv[1].encode()).hexdigest())' "$1"; }

echo "== 1. registered / unregistered =="
mkzip "$T/rp1" vsavj "vsavj.04=BBBB" "vsavj.03=AAAA" "vsavj.13m=GFX1" "vsavj.key=K"
prog=$($FP "$T/rp1" --set vsavj --sha-only)
[ "$prog" = "$(sha1_of AAAABBBB)" ] && ok "program key = sha1 of the program members in MEMBER ORDER (03 then 04, not zip order)" || fail "program key $prog"
printf '%s\tMYSET\n' "$prog" > "$T/reg.tsv"
out=$($FP "$T/rp1" --set vsavj --registry "$T/reg.tsv" 2>"$T/err") && ok "a registered image resolves: '$out'" || fail "registered lookup rc=$?"
[ "$out" = MYSET ] || fail "resolved to '$out'"
: > "$T/empty.tsv"
out=$($FP "$T/rp1" --set vsavj --registry "$T/empty.tsv" 2>"$T/err") && st=0 || st=$?
[ "$st" = 2 ] && grep -q "^UNREGISTERED build: whole-set" "$T/err" && grep -q "add a row to $T/empty.tsv" "$T/err" && [ "$out" = "$prog" ] \
    && ok "an unregistered image: exit 2, UNREGISTERED on stderr naming the registry, the program key on stdout" || fail "unregistered: rc=$st out='$out' err='$(cat "$T/err")'"
$FP "$T/nowhere" --set vsavj --sha-only >/dev/null 2>"$T/err" && fail "a missing image was accepted" || { grep -q "vsavj.zip not found in rompath" "$T/err" && ok "a missing image is named" || fail "missing image message: $(cat "$T/err")"; }

echo "== 1b. THE DUAL KEY =="
mkzip "$T/rp2" vsavj "vsavj.04=BBBB" "vsavj.03=AAAA" "vsavj.13m=GFX2" "vsavj.key=K"
prog2=$($FP "$T/rp2" --set vsavj --sha-only); set1=$($FP "$T/rp1" --set vsavj --set-key); set2=$($FP "$T/rp2" --set vsavj --set-key)
[ "$prog" = "$prog2" ] && [ "$set1" != "$set2" ] && ok "a non-program delta: SAME program key, DIFFERENT whole-set key" || fail "program $prog/$prog2 whole-set $set1/$set2"
printf '%s\tSETKEY-HIT\n' "$set1" > "$T/reg.tsv"
out=$($FP "$T/rp1" --set vsavj --registry "$T/reg.tsv" 2>"$T/err") || out="<rc$?>"
[ "$out" = SETKEY-HIT ] && ! grep -q 'PROGRAM KEY' "$T/err" && ok "whole-set key resolves, and silently" || fail "whole-set lookup '$out' err '$(cat "$T/err")'"
printf '%s\tPROGKEY-HIT\n' "$prog" > "$T/reg.tsv"
out=$($FP "$T/rp1" --set vsavj --registry "$T/reg.tsv" 2>"$T/err") || out="<rc$?>"
[ "$out" = PROGKEY-HIT ] && grep -q "^NOTE: $T/rp1 resolved to 'PROGKEY-HIT' by PROGRAM KEY $prog" "$T/err" && ok "program key resolves and ANNOUNCES itself on stderr" || fail "program lookup '$out' err '$(cat "$T/err")'"
printf '%s\tPROGKEY-HIT\n%s\tSETKEY-HIT\n' "$prog" "$set1" > "$T/reg.tsv"
out=$($FP "$T/rp1" --set vsavj --registry "$T/reg.tsv" 2>/dev/null) || out="<rc$?>"
[ "$out" = SETKEY-HIT ] && ok "whole-set key WINS when both are present" || fail "precedence gave '$out'"
printf '%s\tWHOLESET-ONLY\n' "$set1" > "$T/reg.tsv"
st=0; out=$($FP "$T/rp2" --set vsavj --registry "$T/reg.tsv" 2>/dev/null) || st=$?
[ "$st" = 2 ] && ok "MUST-FIRE: a whole-set-ONLY row is unreachable by the program fallback from the twin (exit 2)" || fail "the twin reached a whole-set-only row: rc=$st out='$out'"
chain=$($FP "$T/rp1;$T/rp2" --set vsavj --set-key)
[ "$chain" = "$set1" ] && ok "the whole-set key does not move with the search-path chain" || fail "chain key $chain vs $set1"

echo "== 1c. --full: the resolved chain and the region rules =="
mkzip "$T/parent" vsav "vsav.05=PPPP" "vsav.14m=PGFX"
f1=$($FP "$T/rp1" --set vsavj --full); f2=$($FP "$T/rp1;$T/parent" --set vsavj --full)
[ "$(printf '%s' "$f1" | head -1)" != "$(printf '%s' "$f2" | head -1)" ] && ok "--full IS chain-dependent (folds in the parent set along the path) — which is why it is not the dispatch key" || fail "--full ignored the parent"
printf '%s' "$f2" | grep -q "zips: vsavj.zip, vsav.zip" && ok "…and names the images it resolved" || fail "zips line: $(printf '%s' "$f2" | tail -1)"
printf '%s' "$f1" | grep -q "^  prg        2 members" && printf '%s' "$f1" | grep -q "^  key        1 members" && printf '%s' "$f1" | grep -q "^  gfx/qsnd   1 members" \
    && ok "the lineage's region rules: prg 2 / key 1 / gfx-qsnd 1 (a .13m is not program: the regex excludes 'm')" || fail "regions: $(printf '%s' "$f1" | tr '\n' '|')"

echo "== 2. [fingerprint] config: the program regex and the region rules are the consumer's =="
mkzip "$T/rpf" fake "fake.01=features=" "fake.02=seed=1" "fake.gfx=GGG" "fake.key=K"
$FP "$T/rpf" --set fake --sha-only >/dev/null 2>"$T/err" && fail "the lineage's regex accepted fake.01/.02 as program members" || { grep -q "no program members" "$T/err" && ok "under the lineage's regex a fake image has no program members (refused)" || fail "$(cat "$T/err")"; }
cat > "$T/cfg.toml" <<EOF
[project]
root = "."
[suite]
registry = "reg.tsv"
default_set = "fake"
[fingerprint]
program_member_regex = '\.(0[1-9])$'
region_rules = [['\.key$', 'key'], ['\.gfx$', 'gfx'], ['@program', 'prg']]
region_default = "other"
parent_sets = []
EOF
want=$(sha1_of "features=seed=1")
got=$($FP "$T/rpf" --config "$T/cfg.toml" --sha-only)
[ "$got" = "$want" ] && ok "a consumer regex selects fake.01+fake.02 as the program, in order" || fail "config regex: $got vs $want"
printf '%s\tFAKESET\n' "$got" > "$T/reg.tsv"
out=$($FP "$T/rpf" --config "$T/cfg.toml" 2>/dev/null) && [ "$out" = FAKESET ] && ok "the config's registry and default_set are used (no --set, no --registry)" || fail "config lookup: '$out'"
out=$(BBH_CONFIG="$T/cfg.toml" $FP "$T/rpf" 2>/dev/null) && [ "$out" = FAKESET ] && ok "…and BBH_CONFIG selects the same config" || fail "BBH_CONFIG lookup: '$out'"
full=$($FP "$T/rpf" --config "$T/cfg.toml" --full)
printf '%s' "$full" | grep -q "^  gfx        1 members" && printf '%s' "$full" | grep -q "^  prg        2 members" && ok "--full uses the consumer's region rules" || fail "regions: $(printf '%s' "$full" | tr '\n' '|')"

echo "== 3. the other kinds =="
mkdir -p "$T/fs"; printf 'IMAGE' > "$T/fs/img.bin"; printf 'aux' > "$T/fs/other.dat"
printf '[fingerprint]\nkind = "file-sha1"\nfile_pattern = "{set}.bin"\n' > "$T/fs.toml"
p=$($FP "$T/fs" --set img --config "$T/fs.toml" --sha-only); w=$($FP "$T/fs" --set img --config "$T/fs.toml" --set-key)
[ "$p" = "$(sha1_of IMAGE)" ] && ok "file-sha1: the program key is the file's SHA-1" || fail "file-sha1 program key $p"
printf 'aux2' > "$T/fs/other.dat"; w2=$($FP "$T/fs" --set img --config "$T/fs.toml" --set-key); p2=$($FP "$T/fs" --set img --config "$T/fs.toml" --sha-only)
[ "$w" != "$w2" ] && [ "$p" = "$p2" ] && ok "file-sha1: the whole-set key covers the directory's other files; the program key does not" || fail "file-sha1 dual key: $w/$w2 $p/$p2"
printf '[fingerprint]\nkind = "command"\nprogram_command = "printf prog-{set}-%%s {rompath}"\nwholeset_command = "printf whole-{set}"\n' > "$T/cmd.toml"
p=$($FP "$T/fs" --set img --config "$T/cmd.toml" --sha-only); w=$($FP "$T/fs" --set img --config "$T/cmd.toml" --set-key)
[ "$p" = "prog-img-$T/fs" ] && [ "$w" = "whole-img" ] && ok "command: {set} and {rompath} substituted, the commands' output is the key" || fail "command kind: '$p' '$w'"
$FP "$T/fs" --set img --config "$T/cmd.toml" --full >/dev/null 2>&1 && fail "--full accepted for kind command" || ok "--full is refused for a non-zip kind"

echo "== 4. the example's images and registry =="
python3 "$BBH_HOME/example/fakesys/make_roms.py" --check > "$T/chk" && ok "make_roms.py --check: every committed image is what the generator produces" || { fail "make_roms.py --check:"; sed 's/^/        /' "$T/chk"; }
cp -R "$BBH_HOME/example/roms" "$T/roms_p"; printf 'X' >> "$T/roms_p/base/fake.zip"
python3 "$BBH_HOME/example/fakesys/make_roms.py" --check --out "$T/roms_p" >/dev/null 2>&1 && fail "MUST-FIRE: a perturbed image passed --check" || ok "MUST-FIRE: a perturbed image fails --check"
EXC="$BBH_HOME/example/bbh.toml"; REGX="$BBH_HOME/example/expected/registry.tsv"
for row in base:sha-only attract:sha-only build-a:set-key build-b:set-key; do
    n="${row%%:*}"; fl="${row#*:}"
    k=$(cd "$BBH_HOME/example" && $FP "roms/$n" --config "$EXC" "--$fl")
    grep -q "^$k	$n	" "$REGX" && ok "registry row for $n is the image's $fl key" || fail "registry row for $n does not match the image ($k)"
done
k=$(cd "$BBH_HOME/example" && $FP roms/hook --config "$EXC" --sha-only)
grep -q "$k" "$REGX" && fail "roms/hook has a registry row (it must not)" || ok "roms/hook is unregistered by design"
pa=$(cd "$BBH_HOME/example" && $FP roms/build-a --config "$EXC" --sha-only); pb=$(cd "$BBH_HOME/example" && $FP roms/build-b --config "$EXC" --sha-only)
[ "$pa" = "$pb" ] && ok "build-a and build-b share a program key (the dual-key case is real in the example)" || fail "example builds differ in program key"

echo
[ "$rc" = 0 ] && echo "PASS: fingerprint dispatch validated on synthetic images" || { echo "FAIL: see above"; exit 1; }
