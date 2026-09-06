#!/bin/sh
# make_expected.sh — (re)generate the example's expectation tree from its
# fake ROM images, so every frozen file here has a producer and a command.
#
# Usage: example/make_expected.sh            (from anywhere; ~5 s)
#
# What it writes, in order, and why in that order:
#   1. expected/registry.tsv    base and attract by PROGRAM key; build-a and
#                               build-b by WHOLE-SET key (the dual-key case);
#                               `hook` deliberately absent (the loud exit 2)
#   2. expected/base/           `bbh run-suite --freeze`: every replay's
#                               .sha1 + logs/<name>.log (unmasked)
#   3. expected/base/masked/    THE MASKED BASIS: MASK + logs/ under the
#                               example's mask, each log produced twice and
#                               compared (a basis is frozen only from a
#                               deterministic pair)
#   4. expected/attract/        --freeze WITHOUT 05 (SUITE_ONLY), then the
#                               AUTHORED `05_attract.diverge` = "base 900" —
#                               authored after, because --freeze RETIRES a
#                               .diverge it finds (dispatch consults it first)
#   5. expected/build-a/        AUTHORED .masked specs in the ratified
#                               vocabulary — the proposals of
#                               `bbh describe-shape` over the measured pairs,
#                               written here as literals so a change in the
#                               machine is a red suite, not a silent re-freeze
#                               — plus the per-set `mask` and 06's `.skip`
#   6. expected/build-b/        a copy of build-a's (same program, so the
#                               same behaviour; only the whole-set key differs)
# Ground truth: selftest/test_suite_dispatch.sh runs the suite over the
# result and expects SUITE GREEN on base, attract, build-a and build-b.
set -eu
EX="$(cd "$(dirname "$0")" && pwd)"
BBH_HOME="$(cd "$EX/.." && pwd)"; export BBH_HOME
PYTHONPATH="$BBH_HOME/lib/py"; export PYTHONPATH
cd "$EX"
BBH="$BBH_HOME/bin/bbh"
MASK="$(python3 -m bbh.config bbh.toml get suite.mask_default)"
export FAKE_ROOT="$EX"

echo "== 1. the registry =="
mkdir -p expected
{
    echo "# registry.tsv — build fingerprint -> expectation set. Rows are added only at"
    echo "# freeze time, as a build decision. base and attract are keyed on the PROGRAM"
    echo "# key (bbh fingerprint --sha-only); build-a and build-b on the WHOLE-SET key"
    echo "# (--set-key), because they share a program key and differ in fake.gfx only —"
    echo "# the shape of a gfx-only freeze. roms/hook has NO row on purpose."
    echo "# sha1	expectation-set	notes"
    printf '%s\tbase\tthe base machine (no features); program key\n' "$($BBH fingerprint roms/base --config bbh.toml --sha-only)"
    printf '%s\tattract\tfeatures=attract; program key\n' "$($BBH fingerprint roms/attract --config bbh.toml --sha-only)"
    printf '%s\tbuild-a\tfeatures=hook,select,attract + fake.gfx v1; WHOLE-SET key\n' "$($BBH fingerprint roms/build-a --config bbh.toml --set-key)"
    printf '%s\tbuild-b\tfeatures=hook,select,attract + fake.gfx v2; WHOLE-SET key\n' "$($BBH fingerprint roms/build-b --config bbh.toml --set-key)"
} > expected/registry.tsv
cat expected/registry.tsv | grep -v '^#'

echo "== 2. base: --freeze =="
rm -rf expected/base; mkdir -p expected/base
FAKE_ROMPATH=roms/base "$BBH" run-suite --config bbh.toml --freeze | tail -1

echo "== 3. base/masked: the basis, each log produced twice =="
mkdir -p expected/base/masked/logs
printf '%s' "$MASK" > expected/base/masked/MASK
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
for r in replays/*.rpl; do
    n="$(basename "$r" .rpl)"
    FAKE_ROMPATH=roms/base MASK_RANGES="$MASK" "$BBH_HOME/drivers/fake.sh" fake "$r" "$W/$n.1.log" > /dev/null
    FAKE_ROMPATH=roms/base MASK_RANGES="$MASK" "$BBH_HOME/drivers/fake.sh" fake "$r" "$W/$n.2.log" > /dev/null
    cmp -s "$W/$n.1.log" "$W/$n.2.log" || { echo "FAIL: $n is not deterministic — no basis frozen"; exit 1; }
    cp "$W/$n.1.log" "expected/base/masked/logs/$n.log"
done
echo "  $(ls expected/base/masked/logs | wc -l | tr -d ' ') logs under MASK $MASK"

echo "== 4. attract: --freeze without 05, then the authored .diverge =="
rm -rf expected/attract; mkdir -p expected/attract
FAKE_ROMPATH=roms/attract SUITE_ONLY="01_idle 02_coin_start 03_press 04_both 06_other_set" \
    "$BBH" run-suite --config bbh.toml --freeze | tail -1
printf 'base 900' > expected/attract/05_attract.diverge

echo "== 5. build-a: the authored masked specs =="
rm -rf expected/build-a; mkdir -p expected/build-a
printf '%s' "$MASK" > expected/build-a/mask
printf 'exact base/masked -\n'               > expected/build-a/01_idle.masked
printf 'window base/masked 260 359\n'        > expected/build-a/02_coin_start.masked
printf 'flicker base/masked 2 100,250\n'     > expected/build-a/03_press.masked
printf 'composite base/masked 220 260-359\n' > expected/build-a/04_both.masked
printf 'diverge base/masked 900\n'           > expected/build-a/05_attract.masked
printf 'targets the other image; covered by its own suite' > expected/build-a/06_other_set.skip

echo "== 6. build-b: build-a's expectations, copied =="
rm -rf expected/build-b; cp -R expected/build-a expected/build-b

echo "== the four registered images, verified =="
for b in base attract build-a build-b; do
    out="$(FAKE_ROMPATH="roms/$b" "$BBH" run-suite --config bbh.toml 2>&1)" || { echo "$out"; echo "FAIL: $b is not green"; exit 1; }
    printf '  %-8s %s\n' "$b" "$(printf '%s' "$out" | tail -1)"
done
echo "PASS: the expectation tree is regenerated"
