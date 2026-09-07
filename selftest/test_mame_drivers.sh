#!/bin/sh
# test_mame_drivers.sh — the sh half of the contract for drivers/mame.sh,
# mame_guarded.sh, fbneo.sh and bin/bbh-inp-play, ROM-FREE: a STUB emulator
# records the argv and environment it was launched with and writes a canned
# log, so every refusal, every path made absolute, every isolation flag, the
# profile resolution, the stale-artifact rule, the exit codes and the
# playback terminator are asserted without MAME. The Lua half is proved by
# fidelity F8. ~3 s.
#
# MUST-FIRE controls: a canned INPUT-VIOLATION must make mame.sh exit 1; a
# canned CRASH must make mame_guarded.sh exit 2; a zero-frame playback must
# stay UN-terminated.
set -eu
BBH_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export BBH_HOME
rc=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT INT TERM
unset MASK_RANGES DUMPS POKES SNAP_FRAMES VIDEO_OUT INPUT_OUT TAIL_FRAMES INPUT_INJECT_TEST NO_INPUT_CHECK \
      GUARD_DEBUG GUARD_PROBE CRASH_VECTORS CODE_RANGES GUARD_MATCH BBH_PROFILE MAME_ROMPATH ROMDIR FBNEO_ROMPATH FBNEO_BIN 2>/dev/null || true

# THE STUB: records argv + the harness environment, writes the canned log
# named by STUB_LOG to CHECKSUM_OUT (or to the -hout path), prints STUB_OUT.
cat > "$T/stub_mame" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "${STUB_ARGV:?}"
printf 'cwd=%s\nREPLAY=%s\nBBH_PROFILE=%s\nMASK_RANGES=%s\nDUMPS=%s\nFBNEO_HPOKE=%s\nFBNEO_HVIDEO=%s\nHOME=%s\n' \
    "$(pwd)" "${REPLAY:-}" "${BBH_PROFILE:-}" "${MASK_RANGES:-}" "${DUMPS:-}" "${FBNEO_HPOKE:-}" "${FBNEO_HVIDEO:-}" "${HOME:-}" > "${STUB_ARGV}.env"
out="${CHECKSUM_OUT:-}"
i=0; for a in "$@"; do i=$((i+1)); [ "$a" = "-hout" ] && out="$(eval echo \${$((i+1))})"; done
[ -n "${STUB_LOG:-}" ] && [ -n "$out" ] && cp "$STUB_LOG" "$out"
[ -n "${STUB_OUT:-}" ] && printf '%s\n' "$STUB_OUT"
exit "${STUB_RC:-0}"
EOF
chmod +x "$T/stub_mame"
export MAME_BIN="$T/stub_mame" STUB_ARGV="$T/argv"
printf '1 0000000000000001\n2 0000000000000002\nEND 2\n' > "$T/clean.log"
printf '1 0000000000000001\nINPUT-VIOLATION 1 frame 2 port :IN0 expected ff got fe\nEND 2\n' > "$T/viol.log"
printf '1 0000000000000001\nCRASH 2 vec4 PC 0bf800 SP 00ff7f00 ADDR -\nREGS D0=0\nSTACK 00ff7f04 00001234\nEND-CRASH 2\n' > "$T/crash.log"
mkdir -p "$T/ref" "$T/build" "$T/out"; : > "$T/ref/vsavj.zip"; : > "$T/build/vsavj.zip"; : > "$T/build/x.zip"
printf '10 p1=U\n' > "$T/r.rpl"
M="$BBH_HOME/drivers/mame.sh"; G="$BBH_HOME/drivers/mame_guarded.sh"; FB="$BBH_HOME/drivers/fbneo.sh"; IP="$BBH_HOME/bin/bbh-inp-play"

echo "== 1. drivers/mame.sh =="
"$M" vsavj "$T/r.rpl" "$T/out/a.log" > "$T/o" 2>&1 && fail "ran with no BBH_PROFILE" || { grep -q "set BBH_PROFILE" "$T/o" && ok "no BBH_PROFILE: refused, the variable named" || fail "$(cat "$T/o")"; }
BBH_PROFILE=nosuch "$M" vsavj "$T/r.rpl" "$T/out/a.log" > "$T/o" 2>&1 && fail "an unknown profile ran" || { grep -q "machine profile not found" "$T/o" && ok "an unknown profile name is refused" || fail "$(cat "$T/o")"; }
BBH_PROFILE=cps2 "$M" vsavj "$T/r.rpl" "$T/out/a.log" > "$T/o" 2>&1 && fail "ran with no rompath" || { grep -q "set MAME_ROMPATH" "$T/o" && ok "no MAME_ROMPATH and no ROMDIR: refused" || fail "$(cat "$T/o")"; }
STUB_LOG="$T/clean.log" BBH_PROFILE=cps2 MAME_ROMPATH="$T/build;$T/ref" "$M" vsavj "$T/r.rpl" "$T/out/a.log" "$T/sb" > "$T/o" 2>&1 && ok "a clean canned run: exit 0" || fail "clean run: $(cat "$T/o")"
grep -q "^BBH_PROFILE=$BBH_HOME/lua/mame/profiles/cps2.lua$" "$T/argv.env" && ok "a bare profile name resolves to lua/mame/profiles/cps2.lua and reaches the emulator's environment" || fail "profile env: $(grep BBH_PROFILE "$T/argv.env")"
grep -q "^REPLAY=$T/r.rpl$" "$T/argv.env" && ok "REPLAY is the absolute replay path" || fail "REPLAY: $(grep REPLAY "$T/argv.env")"
for flag in "-keyboardprovider" "-mouseprovider" "-joystickprovider" "-lightgunprovider" "-video" "-sound" "-nothrottle" "-skip_gameinfo"; do grep -qx -- "$flag" "$T/argv" || fail "isolation flag $flag missing"; done
ok "every isolation flag (four input providers none, -video none, -sound none, -nothrottle, -skip_gameinfo)"
grep -qx -- "$T/build;$T/ref" "$T/argv" && ok "-rompath carries the chain as given" || fail "rompath: $(grep -A1 rompath "$T/argv")"
grep -qx -- "$T/sb/cfg" "$T/argv" && grep -qx -- "$T/sb/nvram" "$T/argv" && grep -qx -- "$T/sb/snap" "$T/argv" && grep -qx -- "$T/sb" "$T/argv" && ok "cfg/nvram/diff/snap/sta/homepath all inside the sandbox" || fail "sandbox dirs: $(cat "$T/argv")"
grep -qx -- "$BBH_HOME/lua/mame/replay.lua" "$T/argv" && ok "-autoboot_script is the harness's replay.lua" || fail "autoboot: $(grep -A1 autoboot "$T/argv")"
[ -f "$T/sb/mame_replay.log" ] && ok "the emulator's own output lands in the sandbox" || fail "no mame_replay.log in the sandbox"
(cd "$T/out" && STUB_LOG="$T/clean.log" BBH_PROFILE=cps2 ROMDIR="$T/ref" "$M" vsavj ../r.rpl rel.log > /dev/null 2>&1) && [ -f "$T/out/rel.log" ] && grep -qx -- "$T/ref" "$T/argv" && ok "relative out path made absolute; ROMDIR is the rompath fallback" || fail "relative/fallback"
printf 'END 999\n' > "$T/out/stale.log"
STUB_RC=1 BBH_PROFILE=cps2 ROMDIR="$T/ref" "$M" vsavj "$T/r.rpl" "$T/out/stale.log" > "$T/o" 2>&1 && fail "a failed emulator run exited 0" || { [ ! -f "$T/out/stale.log" ] && ok "a failed run leaves NO artifact (the stale log was removed first) and exits 1" || fail "stale log survived"; }
STUB_LOG="$T/viol.log" BBH_PROFILE=cps2 ROMDIR="$T/ref" "$M" vsavj "$T/r.rpl" "$T/out/v.log" > "$T/o" 2>&1 && fail "MUST-FIRE: an INPUT-VIOLATION log was accepted" || { [ $? = 1 ] && grep -q "INPUT INTEGRITY VIOLATION" "$T/o" && ok "MUST-FIRE: an INPUT-VIOLATION line -> exit 1, the run discarded" || fail "violation: $(cat "$T/o")"; }
for v in GUARD_DEBUG GUARD_PROBE CRASH_VECTORS CODE_RANGES GUARD_MATCH GUARD_FORCE; do
    env "$v=1" BBH_PROFILE=cps2 ROMDIR="$T/ref" "$M" vsavj "$T/r.rpl" "$T/out/g.log" > "$T/o" 2>&1 && fail "$v was ignored" || { [ $? = 3 ] && grep -q "^REFUSED: drivers/mame.sh cannot honour $v" "$T/o" || fail "$v: $(cat "$T/o")"; }
done
[ ! -f "$T/out/g.log" ] && ok "the guard family is REFUSED (exit 3, the variable named) and no log is written" || fail "a refused run wrote a log"
MASK_RANGES=7f00-8000 STUB_LOG="$T/clean.log" BBH_PROFILE=cps2 ROMDIR="$T/ref" "$M" vsavj "$T/r.rpl" "$T/out/m.log" > /dev/null 2>&1 && grep -q "^MASK_RANGES=7f00-8000$" "$T/argv.env" && ok "MASK_RANGES reaches the engine (it is the engine that masks)" || fail "mask env"

echo "== 2. drivers/mame_guarded.sh =="
for v in MASK_RANGES NO_INPUT_CHECK VIDEO_OUT INPUT_OUT; do
    env "$v=1" BBH_PROFILE=cps2 ROMDIR="$T/ref" "$G" vsavj "$T/r.rpl" "$T/out/g2.log" > "$T/o" 2>&1 && fail "$v was ignored by the guard" || { [ $? = 3 ] && grep -q "^REFUSED: drivers/mame_guarded.sh cannot honour $v" "$T/o" || fail "$v: $(cat "$T/o")"; }
done
ok "MASK_RANGES / NO_INPUT_CHECK / VIDEO_OUT / INPUT_OUT are REFUSED by the guard (exit 3)"
STUB_LOG="$T/clean.log" BBH_PROFILE=cps2 ROMDIR="$T/ref" "$G" vsavj "$T/r.rpl" "$T/out/c.log" "$T/gsb" > "$T/o" 2>&1 && ok "a clean guarded run: exit 0" || fail "guarded clean: $(cat "$T/o")"
grep -qx -- "-debug" "$T/argv" && grep -qx -- "-debugscript" "$T/argv" && [ "$(cat "$T/gsb/guard_go.dbs")" = "go" ] && ok "authoritative mode by default: -debug -debugger none -debugscript <go>" || fail "debug flags: $(cat "$T/argv")"
grep -qx -- "$BBH_HOME/lua/mame/replay_guard.lua" "$T/argv" && ok "-autoboot_script is replay_guard.lua" || fail "guard autoboot"
GUARD_DEBUG=0 STUB_LOG="$T/clean.log" BBH_PROFILE=cps2 ROMDIR="$T/ref" "$G" vsavj "$T/r.rpl" "$T/out/c0.log" > /dev/null 2>&1 && ! grep -qx -- "-debug" "$T/argv" && ok "GUARD_DEBUG=0: cheap mode, no -debug" || fail "cheap mode"
STUB_LOG="$T/crash.log" BBH_PROFILE=cps2 ROMDIR="$T/ref" "$G" vsavj "$T/r.rpl" "$T/out/cr.log" > "$T/o" 2>&1 && fail "MUST-FIRE: a CRASH log exited 0" || { [ $? = 2 ] && grep -q "^GUARD TRIPPED:" "$T/o" && grep -q "^CRASH 2 vec4" "$T/o" && grep -q "^STACK" "$T/o" && ok "MUST-FIRE: a CRASH log -> exit 2, 'GUARD TRIPPED:' with the CRASH/STACK/END-CRASH lines" || fail "crash: $(cat "$T/o")"; }
STUB_LOG="$T/viol.log" BBH_PROFILE=cps2 ROMDIR="$T/ref" "$G" vsavj "$T/r.rpl" "$T/out/gv.log" > "$T/o" 2>&1 && fail "the guard accepted an INPUT-VIOLATION" || { [ $? = 2 ] && ok "INPUT-VIOLATION joins the guard's trip set (exit 2)" || fail "guard violation rc=$?"; }

echo "== 3. drivers/fbneo.sh =="
mkdir -p "$T/fb"; cp "$T/stub_mame" "$T/fb/fbneo"; export FBNEO_BIN="$T/fb/fbneo"
for v in MASK_RANGES SNAP_FRAMES INPUT_OUT INPUT_INJECT_TEST NO_INPUT_CHECK GUARD_DEBUG CRASH_VECTORS; do
    env "$v=1" ROMDIR="$T/ref" "$FB" vsavj "$T/r.rpl" "$T/out/f.log" > "$T/o" 2>&1 && fail "fbneo ignored $v" || { [ $? = 3 ] && grep -q "^REFUSED: drivers/fbneo.sh cannot honour $v" "$T/o" || fail "$v: $(cat "$T/o")"; }
done
ok "MASK_RANGES / SNAP_FRAMES / INPUT_OUT / INPUT_INJECT_TEST / NO_INPUT_CHECK / the guard family are REFUSED"
TAIL_FRAMES=5 ROMDIR="$T/ref" "$FB" vsavj "$T/r.rpl" "$T/out/f.log" > "$T/o" 2>&1 && fail "TAIL_FRAMES=5 accepted" || { grep -q "cannot honour TAIL_FRAMES=5" "$T/o" && ok "TAIL_FRAMES other than the frontend's 120 is REFUSED" || fail "$(cat "$T/o")"; }
env -u FBNEO_BIN ROMDIR="$T/ref" "$FB" vsavj "$T/r.rpl" "$T/out/f.log" > "$T/o" 2>&1 && fail "no FBNEO_BIN ran" || { grep -q "set FBNEO_BIN" "$T/o" && ok "no FBNEO_BIN: refused, the variable named" || fail "$(cat "$T/o")"; }
STUB_LOG="$T/clean.log" ROMDIR="$T/ref" FBNEO_ROMPATH="$T/build" "$FB" vsavj "$T/r.rpl" "$T/out/f.log" "$T/fsb" > "$T/o" 2>&1 && ok "a clean canned run through the overlay: exit 0" || fail "fbneo clean: $(cat "$T/o")"
[ "$(readlink "$T/fsb/roms/vsavj.zip")" = "$T/build/vsavj.zip" ] && [ "$(readlink "$T/fsb/roms/x.zip")" = "$T/build/x.zip" ] && ok "the overlay: the FIRST component's zip wins by name, the reference fills the rest" || fail "overlay: $(ls -l "$T/fsb/roms")"
grep -q "^cwd=$T/fsb$" "$T/argv.env" && grep -q "^HOME=$T/fsb$" "$T/argv.env" && ok "the frontend runs from inside the sandbox with HOME there (it reads roms/ under its cwd)" || fail "cwd/HOME: $(cat "$T/argv.env")"
grep -qx -- "-hinput" "$T/argv" && grep -qx -- "$T/r.rpl" "$T/argv" && grep -qx -- "-hout" "$T/argv" && ok "-hinput <abs rpl> -hout <abs log>" || fail "hinput/hout: $(cat "$T/argv")"
DUMPS="100:ff8000-ff8100" POKES="50:ff8100:01" VIDEO_OUT="$T/out/v.log" STUB_LOG="$T/clean.log" ROMDIR="$T/ref" "$FB" vsavj "$T/r.rpl" "$T/out/f2.log" > /dev/null 2>&1
grep -qx -- "-hdump" "$T/argv" && grep -qx -- "100:ff8000-ff8100" "$T/argv" && grep -q "^FBNEO_HPOKE=50:ff8100:01$" "$T/argv.env" && grep -q "^FBNEO_HVIDEO=$T/out/v.log$" "$T/argv.env" && ok "DUMPS -> -hdump, POKES -> FBNEO_HPOKE, VIDEO_OUT -> FBNEO_HVIDEO" || fail "mapping: $(cat "$T/argv" "$T/argv.env")"
printf 'END 5\n' > "$T/out/fs.log"; STUB_RC=0 ROMDIR="$T/ref" "$FB" vsavj "$T/r.rpl" "$T/out/fs.log" > "$T/o" 2>&1 && fail "a run that wrote no log exited 0" || { [ ! -f "$T/out/fs.log" ] && grep -q "no END line" "$T/o" && ok "the frontend's unconditional exit 0 is not trusted: the artifact is removed first and its absence is the failure" || fail "fbneo stale: $(cat "$T/o")"; }

echo "== 4. bin/bbh-inp-play =="
mkdir -p "$T/inp/rec-01/nvram"; : > "$T/inp/rec-01/rec-01.inp"; echo "a note" > "$T/inp/rec-01/NOTE"
printf 'ALIVE 600 match=00040000\n' > "$T/play.log"
"$IP" --set vsavjw --rompath "$T/build;$T/ref" --inp "$T/inp/rec-01" --out "$T/ip1" > "$T/o" 2>&1 && fail "inp-play ran with no BBH_PROFILE" || { grep -q "set BBH_PROFILE" "$T/o" && ok "no BBH_PROFILE: refused" || fail "$(cat "$T/o")"; }
STUB_LOG="$T/play.log" STUB_OUT="Total playback frames: 500" BBH_PROFILE=cps2w "$IP" --set vsavjw --rompath "$T/build;$T/ref" --inp "$T/inp/rec-01" --out "$T/ip1" > "$T/o" 2>&1 && ok "a canned playback of 500 frames: exit 0" || fail "inp-play: $(cat "$T/o")"
grep -q "^PLAYBACK 500$" "$T/ip1/inp_guard.log" && grep -q "^END 500$" "$T/ip1/inp_guard.log" && ok "PLAYBACK <n> and END <n> appended from MAME's own frame count" || fail "terminator: $(cat "$T/ip1/inp_guard.log")"
grep -qx -- "-playback" "$T/argv" && grep -qx -- "rec-01.inp" "$T/argv" && grep -qx -- "-input_directory" "$T/argv" && grep -qx -- "-exit_after_playback" "$T/argv" && grep -qx -- "$BBH_HOME/lua/mame/inp_guard.lua" "$T/argv" && ok "-playback <name>.inp -input_directory <dir> -exit_after_playback, inp_guard.lua" || fail "playback argv: $(cat "$T/argv")"
grep -q "^BBH_PROFILE=$BBH_HOME/lua/mame/profiles/cps2w.lua$" "$T/argv.env" && grep -q "^cwd=$T/ip1$" "$T/argv.env" && ok "the cps2w profile resolved; the emulator runs from the output dir (crash dumps land there)" || fail "$(cat "$T/argv.env")"
nv="$(grep -A1 -- '-nvram_directory' "$T/argv" | tail -1)"; case "$nv" in "$T/inp/rec-01/nvram") fail "playback ran against the CANONICAL nvram" ;; *) ok "playback runs against a throwaway COPY of the recorded nvram, never the canonical one" ;; esac
STUB_LOG="$T/play.log" STUB_OUT="Total playback frames: 0" BBH_PROFILE=cps2w "$IP" --set vsavjw --rompath "$T/build;$T/ref" --inp "$T/inp/rec-01" --out "$T/ip0" > "$T/o" 2>&1 && fail "a zero-frame playback exited 0" || { ! grep -q "^END" "$T/ip0/inp_guard.log" && ! grep -q "^PLAYBACK" "$T/ip0/inp_guard.log" && ok "MUST-FIRE: a ZERO-frame playback stays UN-terminated (no END, no PLAYBACK) so a corpus gate's dead-run check can fail" || fail "dead run terminated: $(cat "$T/ip0/inp_guard.log")"; }
BBH_PROFILE=cps2w "$IP" --set vsavjw --rompath "nosuch/dir;$T/ref" --inp "$T/inp/rec-01" --out "$T/ip2" > "$T/o" 2>&1 && fail "a nonexistent rompath component ran" || { grep -q "rompath component does not exist" "$T/o" && ok "a relative or missing rompath component is refused BEFORE the run (it would resolve against the output dir and play zero frames)" || fail "$(cat "$T/o")"; }
BBH_PROFILE=cps2w "$IP" --set vsavjw --rompath "$T/ref" --inp "$T/inp/nosuch" > "$T/o" 2>&1 && fail "a missing recording ran" || { grep -q "no recording dir" "$T/o" && ok "a missing recording dir is refused" || fail "$(cat "$T/o")"; }

echo
[ "$rc" = 0 ] && echo "PASS: the MAME/FBNeo drivers and the playback tool honour the contract (sh half)" || { echo "FAIL: see above"; exit 1; }
