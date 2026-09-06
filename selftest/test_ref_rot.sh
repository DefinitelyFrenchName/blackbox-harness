#!/bin/sh
# test_ref_rot.sh — ground truth for lib/py/bbh/ref_rot.py: a hard-coded
# path default must not have ROTTED, absent is not rotted, only a default
# the script READS as an image is judged, and currency is reported, never
# failed. ROM-free, ~2 s.
#
# A synthetic root with every default idiom the lineage closed a hole on
# (positional, named env, plain, root-prefixed image dir) and every outcome
# (live, unbuilt, ROTTED, not read as an image, a dir with no image dir);
# the ordered image preference; the currency report over a synthetic
# registry (SUPERSEDED, no row, a family at two generations). MUST-FIRE:
# the stale image made current flips the verdict; a [ref_rot].predicate
# command replaces the member rule and its exit decides.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
R="$T/r"; mkdir -p "$R/tests" "$R/tests/expected" "$R/build/live/rompath" "$R/build/live2/rompath" "$R/build/stale/rompath" "$R/build/norompath"
cat > "$R/bbh.toml" <<'EOF'
[fingerprint]
program_member_regex = '\.(0[1-9])$'
[ref_rot]
token_regex = 'build/[a-z0-9_]+'
rompath_suffix = "/rompath"
image_glob = "*.zip"
image_prefer = ["pref"]
stale_marker = ["m.", "m.z01", "no m.z01 (old)"]
family_regex = '^([a-z]+)-m([0-9]+)$'
no_row_note = "no registry row"
rotted_advice = ["ADVICE LINE ONE", "ADVICE LINE TWO"]
EOF
python3 - "$R" <<'EOF'
import sys, zipfile, os
R = sys.argv[1]
def mk(path, members):
    with zipfile.ZipFile(path, "w") as z:
        for n, v in members: z.writestr(n, v)
mk(f"{R}/build/live/rompath/set.zip", [("m.01", b"LIVE"), ("m.z01", b"z")])
mk(f"{R}/build/live2/rompath/a.zip", [("m.01", b"OLD")])                     # rotted shape, NOT preferred
mk(f"{R}/build/live2/rompath/pref.zip", [("m.01", b"L2"), ("m.z01", b"z")])  # preferred by name
mk(f"{R}/build/stale/rompath/set.zip", [("m.01", b"STALE")])
EOF
g() { printf '#!/bin/sh\n# %s.sh — a stub.\n%s\n' "$1" "$2" > "$R/tests/$1.sh"; }
g g_live    'BUILD="${BUILD:-build/live}"
ls "$BUILD/rompath"'
g g_pos     'B="${1:-build/gone}"
ls "$B/rompath"'
g g_plain   'REF=build/stale
ls $REF/rompath'
g g_notread 'E="${E:-build/live}"
ls "$E/extract"'
g g_repo    'RP="${1:-$REPO/build/live2/rompath}"
ls "$RP"'
g g_empty   'Q="${Q:-build/norompath}"
ls "${Q}/rompath"'
sha="$(python3 -m bbh.fingerprint "$R/build/live/rompath" --set set --sha-only --config "$R/bbh.toml")"
printf '%s\tfoo-m1\tthe live image\n0000000000000000000000000000000000000000\tfoo-m2\tnewer\n' "$sha" > "$R/tests/expected/registry.tsv"
RR="python3 -m bbh.ref_rot --config $R/bbh.toml"
out="$($RR 2>&1)" && st=0 || st=$?

echo "== 1. the verdict lines =="
[ "$st" = 1 ] && ok "exit 1: one reference has ROTTED" || fail "exit $st"
line() { printf '%s\n' "$out" | grep -qF "$1" && ok "$2" || fail "$2 — missing: $1"; }
line '== 2 live, 2 unbuilt, 1 ROTTED (1 not romset refs)' "the count line"
line '  ok      build/live             g_live.sh ($BUILD) — 2 members' "named env, read as an image: live"
line '  ok      build/live2            g_repo.sh ($RP) — 2 members' "root-prefixed image dir: live, and judged by the PREFERRED image (the rotted-shaped a.zip beside it is ignored)"
line '  unbuilt build/gone             g_pos.sh ($B) — not built here; not a failure' "positional default, dir absent: unbuilt"
line '  unbuilt build/norompath        g_empty.sh ($Q) — not built here; not a failure' "a dir with no image dir: unbuilt"
line '  ROTTED  build/stale            g_plain.sh ($REF) — 1 members, no m.z01 (old)' "plain default, read as an image, too old: ROTTED with the consumer's reason"
printf '%s\n' "$out" | sed '/^== currency/,$d' | grep -q 'g_notread' && fail "a default not read as an image was judged" || ok "a default read for another dir is not judged (counted as not-romset)"
line '  ADVICE LINE ONE' "the advice lines are the consumer's"

echo "== 2. the currency report =="
line '== currency (REPORT ONLY — a superseded reference is often correct)' "the report header"
line '  build/live             g_live.sh                          SUPERSEDED — foo-m1; newest is foo-m2' "a registered image behind its family's newest generation is SUPERSEDED"
line '  build/live             g_notread.sh                       SUPERSEDED — foo-m1; newest is foo-m2' "currency covers a reference NOT read as an image too"
line '  build/live2            g_repo.sh                          no registry row' "an unregistered image gets the consumer's note"
line '      build/live*        build/live, build/live2' "a family referenced at two generations is listed"
line '  2 registered reference(s) point at a superseded set.' "the closing count (per REFERENCE: two gates name the superseded image)"

echo "== 3. MUST-FIRE: the stale image made current flips the verdict =="
python3 - "$R" <<'EOF'
import sys, zipfile
with zipfile.ZipFile(f"{sys.argv[1]}/build/stale/rompath/set.zip", "w") as z:
    z.writestr("m.01", b"STALE"); z.writestr("m.z01", b"z")
EOF
$RR >/dev/null 2>&1 && ok "with m.z01 present the same tree exits 0" || fail "still red after the image was made current"
$RR | grep -q '== 3 live, 2 unbuilt, 0 ROTTED (1 not romset refs)' && ok "…and counts 3 live, 0 ROTTED" || fail "count after the fix"

echo "== 4. MUST-FIRE: a predicate command replaces the member rule =="
printf '[ref_rot]\ntoken_regex = %s\nimage_prefer = ["pref"]\npredicate = %s\n' "'build/[a-z0-9_]+'" "'echo \"probe \$(basename \"\$1\")\"; exit 1'" > "$R/bbh_pred.toml"
o4="$(python3 -m bbh.ref_rot --config "$R/bbh_pred.toml" 2>&1)" && fail "a predicate exiting 1 did not rot" \
    || { printf '%s\n' "$o4" | grep -q '== 0 live, 2 unbuilt, 3 ROTTED' && printf '%s\n' "$o4" | grep -q 'g_repo.sh ($RP) — probe pref.zip' \
         && ok "every image is ROTTED by the predicate, and its stdout is the description" || fail "predicate: $(printf '%s\n' "$o4" | head -3)"; }
printf '[ref_rot]\ntoken_regex = %s\nimage_prefer = ["pref"]\npredicate = %s\n' "'build/[a-z0-9_]+'" "'echo fine'" > "$R/bbh_pred2.toml"
o5="$(python3 -m bbh.ref_rot --config "$R/bbh_pred2.toml")" && printf '%s\n' "$o5" | grep -q '== 3 live, 2 unbuilt, 0 ROTTED' && ok "a predicate exiting 0 reads every image live" || fail "predicate exit 0"
printf '%s\n' "$o5" | grep -q '  build/live             g_live.sh                          no registry row (by design' \
    && ok "no [fingerprint] section here, so the images have no program members: the fingerprint's EXIT is caught and the image reads as unregistered, the verdict untouched" || fail "SystemExit guard: $(printf '%s\n' "$o5" | grep g_live)"

echo "== 5. the shipped example =="
"$BBH_HOME/bin/bbh" ref-rot --config "$BBH_HOME/example/bbh.toml" | grep -q '^== 3 live, 0 unbuilt, 0 ROTTED' && ok "example/: its three image defaults are live" || fail "the example's references"

echo
[ "$rc" = 0 ] && echo "PASS: a rotted reference is named, an absent one is not a failure, currency is a report" || { echo "FAIL: see above"; exit 1; }
