#!/bin/sh
# test_shadow_tools.sh — ground truth for lib/sh/shadow_tools.sh: a
# perturbation control edits a COPY under a shadow root and the tracked tool
# is never written. ROM-free, ~1 s.
#
# A synthetic repo whose tool resolves its root from its own location and
# imports a sibling by path: run through the shadow it reads the real
# inputs; perturbed, only the copy changes (the real file is byte-identical
# to a pristine copy); restored, the copy is pristine again; the siblings
# are symlinks; the tools dir and the linked dirs come from the environment
# a runner exports from [project]; no root set is an error, not a guess.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
R="$T/repo"; mkdir -p "$R/tools" "$R/build" "$T/work"
cat > "$R/tools/a.py" <<'EOF'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import b
root = Path(__file__).resolve().parent.parent
print("b says", b.hi(), "; data =", (root / "build" / "data.txt").read_text().strip(), "; MARK=original")
EOF
printf 'def hi():\n    return "hi"\n' > "$R/tools/b.py"
echo 42 > "$R/build/data.txt"
cp "$R/tools/a.py" "$T/pristine_a.py"

. "$BBH_HOME/lib/sh/shadow_tools.sh"
echo "== 1. the shadow resolves the real inputs =="
REPO="$R"; export REPO
GEN="$(bbh_shadow_tool "$T/work" a.py)"
[ "$GEN" = "$T/work/shadow/tools/a.py" ] && ok "the copy is <work>/shadow/tools/a.py" || fail "path: $GEN"
o="$(python3 "$GEN")"
[ "$o" = "b says hi ; data = 42 ; MARK=original" ] && ok "the copy imports its sibling and reads build/ through the links: $o" || fail "$o"
[ -L "$T/work/shadow/tools/b.py" ] && [ -L "$T/work/shadow/build" ] && ok "the sibling and the linked dir are SYMLINKS to the real ones" || fail "not symlinked"
[ -L "$GEN" ] && fail "the tool itself is a symlink (a perturbation would hit the real file)" || ok "the tool itself is a real copy"

echo "== 2. MUST-FIRE: the perturbation reaches the copy and nothing else =="
sed -i.bak 's/MARK=original/MARK=PERTURBED/' "$GEN"; rm -f "$GEN.bak"
python3 "$GEN" | grep -q 'MARK=PERTURBED' && ok "the perturbed copy runs perturbed" || fail "perturbation not seen"
cmp -s "$R/tools/a.py" "$T/pristine_a.py" && ok "the tracked tool is byte-identical to its pristine copy" || fail "THE TRACKED TOOL WAS WRITTEN"
bbh_shadow_restore "$T/work" a.py
python3 "$GEN" | grep -q 'MARK=original' && ok "bbh_shadow_restore re-copies the pristine tool over the shadow" || fail "restore"
GEN2="$(bbh_shadow_tool "$T/work" a.py)"; [ "$GEN2" = "$GEN" ] && python3 "$GEN2" | grep -q 'MARK=original' && ok "a second bbh_shadow_tool on the same work dir re-copies (idempotent)" || fail "second call"

echo "== 3. the tools dir and the linked dirs are configuration =="
R2="$T/repo2"; mkdir -p "$R2/bin" "$R2/data" "$T/work2"
printf 'from pathlib import Path\nprint((Path(__file__).resolve().parent.parent / "data" / "v.txt").read_text().strip())\n' > "$R2/bin/t.py"
echo seven > "$R2/data/v.txt"
G2="$(REPO="$R2" BBH_TOOLS_DIR=bin BBH_SHADOW_LINK_DIRS="data" bbh_shadow_tool "$T/work2" t.py)"
[ "$G2" = "$T/work2/shadow/bin/t.py" ] && [ "$(python3 "$G2")" = seven ] && ok "BBH_TOOLS_DIR=bin and BBH_SHADOW_LINK_DIRS=data: the copy lives under shadow/bin and reads data/ through the link" || fail "config: $G2 -> $(python3 "$G2" 2>&1)"
unset REPO
o3="$(BBH_ROOT="$R" bbh_shadow_tool "$T/work3" a.py)" && [ -f "$o3" ] && ok "BBH_ROOT serves as the root when REPO is unset" || fail "BBH_ROOT"
o4="$(bbh_shadow_tool "$T/work4" a.py 2>&1)" && fail "no root set was accepted" || { printf '%s\n' "$o4" | grep -q 'needs REPO or BBH_ROOT' && ok "no root set is an error, not a guess" || fail "error text: $o4"; }

echo
[ "$rc" = 0 ] && echo "PASS: a perturbation control cannot touch the tracked tree" || { echo "FAIL: see above"; exit 1; }
