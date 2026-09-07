# The MAME Lua layer — the replay engine, the guards and the taps, under a machine profile

Everything under `lua/mame/` runs inside MAME's Lua (`-autoboot_script`).
It was lifted from Project VAMPIRE SAVED's `tests/lua/` by moving every
literal about the BOARD into one table — the MACHINE PROFILE — and the
replay grammar into one module. The scripts know a CPU tag, an address
space, a RAM window, a port map and an exception-frame layout only through
that table; the cps2 profile is proved by fidelity F8 (the lineage's driver
and `drivers/mame.sh` produce byte-identical logs on the same replay), not
by inspection.

## 1. The machine profile (`lua/mame/profile.lua`, `profiles/*.lua`)

**[BBH-71]** `BBH_PROFILE` names it — a bare name (`cps2`) resolves to
`lua/mame/profiles/<name>.lua`, a path is used as is. `profile.load()`
REFUSES a profile missing a required key, and every guard script refuses
one missing a `crash.*` key it reads; a script never runs on an implied
board. `profiles/TEMPLATE.lua` carries every key with a comment;
`selftest/test_profiles.sh` keeps the template complete (every `P.x` / `C.x`
a script reads is in it) and the loader's required list in step.

| key | read by | meaning |
|---|---|---|
| `cpu`, `space`, `screen` | all | the device tags: `manager.machine.devices[cpu].spaces[space]` is where RAM, pokes and dumps live; `screen` serves `VIDEO_OUT` and snapshots |
| `ram = {lo, hi}` | all | the checksum window, inclusive; `MASK_RANGES` offsets count from `lo`; crash dumps cover it |
| `active_low` | replay, guard | a press CLEARS the field's bits (the lineage's CPS-2); the idle value of every controlled bit is a KNOWN CONSTANT the integrity assertion asserts on frame 1 rather than adopting from a live read |
| `sides` | all | the replay grammar's sides: `who = { width, tokens = { tok = {port tag, field name} } }` |
| `ports` | replay, guard | the input ports the integrity assertion reads and `INPUT_OUT` logs, in log order |
| `inject`, `inject_bit` | replay, guard | `INPUT_INJECT_TEST`'s phantom press: a side/token (replay.lua presses it for one frame) and a bit of `ports[1]` (the guard flips it on its read) |
| `crash.vectors`, `vector_base`, `vector_stride` | guard | which exception vectors to trap under `-debug`, and where the table lives |
| `crash.group0`, `pc_at_sp`, `addr_at_sp` | guards | the exception frame: which vectors carry a fault address, and where the pushed PC and address sit from SP |
| `crash.code = {lo, hi}` | guards | **[BBH-72]** a ROM-plausible long: handler addresses, the STACK sketch. `cps2` (4 MB) and `cps2w` (6 MB) differ ONLY here — the lineage's two guards carried different values and drew different sketches of the same crash |
| `crash.stack_top`, `pc_mask`, `regs`, `sp` | guards | the sketch's ceiling, the address width, the REGS line's register names, the stack pointer's name(s) |
| `crash.exception_store`, `store_to_vector`, `store_code_max`, `arm_frame` | inp_guard | the machine's OWN exception-code store (every handler begins with a store there), `vector = code + store_to_vector`, the filters |
| `crash.match`, `crash.alive` | guard, inp_guard | `GUARD_MATCH`'s in-match flag; the recording guard's ALIVE line |
| `crash.probe_regs`, `trace_regs`, `tap_regs` | guard, taps | optional register lists (68000-shaped defaults) |
| `port_hex_digits` | replay, guard | how wide a port value prints (INPUT_OUT, the violation lines); PC widths derive from `crash.pc_mask` |
| `collect = {stride, offset, width}` | tap_writes | the COLLECT mode's sprite-list record layout (env `COLLECT_*` overrides) |
| `crash.store_width` | inp_guard | the exception store's width — the tap range and the code mask follow it |

## 2. The grammar (`lua/mame/rpl_parse.lua` == `lib/py/bbh/rpl.py`)

**[BBH-73]** One strict parser for every script (the lineage had one strict copy and
five lenient ones that silently DROPPED an unknown token — a malformed
replay now fails loudly, with the lineage's own error texts, on both
sides). Two copies of a grammar are the harness's own rot risk, so their
canonical parses are diffed: `selftest/test_rpl_lua.sh` under a standalone
`lua` (SKIP with the reason when none is present), and fidelity F8 under
MAME's own interpreter over every lineage replay — the production one.
`lua/mame/rpl_dump.lua` and `bbh rpl dump` print that canonical text.

## 3. The scripts

| script | driver | what it measures |
|---|---|---|
| `replay.lua` | `drivers/mame.sh` | THE ORACLE ENGINE: stage inputs per frame, hash the RAM window (FNV-1a64) at the end of every frame, honour `MASK_RANGES` (masked bytes are SKIPPED, so a mask is a BASIS), `DUMPS`, `POKES`, `SNAP_FRAMES`, `VIDEO_OUT`, `INPUT_OUT`; the always-on INPUT-INTEGRITY assertion with its must-fire control (`INPUT_INJECT_TEST`) |
| `replay_guard.lua` | `drivers/mame_guarded.sh` | the same log plus crash detection — authoritative (`-debug`, breakpoints on the vectors: `CRASH … REGS … STACK … END-CRASH`) or cheap (`CODE_RANGES` / `GUARD_MATCH`: `PCWEEDS` / `SOFTRESET`); the probe family (`GUARD_PROBE*`, `GUARD_BREAK`, `GUARD_TRACE`, `GUARD_PC_LOG`, `GUARD_FORCE`). Refuses `MASK_RANGES`: its log is unmasked and a masked expectation compared against it would be a phantom regression |
| `inp_guard.lua` | `bbh inp-play` | crash capture for a RECORDING's playback, no debugger (faithful timeslicing): a write tap on the machine's own exception store fires while the faulting frame is still on the stack |
| `snapshot_frames.lua` | (direct) | PNG snapshots at named frames — "look at it" as a scripted, rerunnable measurement |
| `trace_writes.lua` | (direct, `-debug`) | a debugger watchpoint over a range — hits with PC and registers; `WATCH`'s 4th field selects the address SPACE (a pc-relative read may go through the opcode space and a plain watchpoint is silently blind) |
| `tap_writes.lua` | (direct) | a non-debug PC-attributed WRITE tap (replay-exact frame counting); `REGLOG`, `STACKLOG`, the COLLECT mode |
| `read_tap.lua` | (direct) | **[BBH-76]** a non-debug READ+WRITE tap — serialise a state-dependent value's writes and reads in ONE run (never correlate one across runs) |

**[BBH-74]** Two things every instrument shares and a consumer copying one must keep:
INPUT STAGING IS CANONICAL — parse `held[fr]`, stage for the NEXT frame
(`held[frame + 1]`), so a frame number in any log IS a replay.lua frame
number (the lineage's ten `+1` deviants were one variant copied by every
later file until a census pinned the split).

**[BBH-75]** A memory TAP is dropped silently whenever the machine re-installs handlers
in the space — every tap script re-installs on the space's change
notifier, or it logs boot writes only and reads as "nobody writes this
field".

## 4. The recording corpus (`bbh inp-play`, `bbh inp-corpus`)

The lineage's law: a field report is a RECORDING before it is a theory. A
win-fast rig never gives a CPU opponent the time to reach the script that
crashes; the maintainer's first hand-played recording found in an evening
what three sessions of rig-derived fixes had not. **[BBH-77]** So: every reproducible
crash is captured as the emulator's own input recording with the fresh
nvram it started from, tracked under `[inp].corpus_dir/<name>/` with a
one-line NOTE, named `<what>-<freeze>-NN` after the freeze it was PLAYED on;
`bbh inp-corpus` replays every one under `inp_guard.lua` at every freeze and
fails on the first exception; a captured-but-unfixed crash is declared by a
DEFECT file naming the `vec<n> PC <pc6>` the gate then asserts (so the
capture cannot rot) and lists as OPEN.

**[BBH-78]** A playback that ran ZERO frames executes no code and can raise no
exception: `bbh inp-play` terminates a
log only when the emulator itself reports a playback of > 0 frames, the
corpus gate's liveness predicate rejects the rest, and the gate runs its
own controls on that predicate every time (`selftest/test_inp_corpus.sh`
exercises every verdict on a stub emulator).

## 5. The defaults census — every literal, and which bin it is in

Asked by the lineage's maintainer after the code-window finding (§1): does
the Lua layer carry other constants that are really per-project? It did.
Every literal in `lua/mame/` is now in one of three bins, and this table is
the register (H6b; `selftest/test_profiles.sh` keeps the profile bin
complete against what the scripts read):

| literal | bin | where it lives now |
|---|---|---|
| the code window (`0x400000` / `0x600000`) | **board** | `crash.code` — `cps2` vs `cps2w` (§1) |
| the exception store's width (the guard read `data & 0xFFFF`) | **board** | `crash.store_width` (the tap range and the code mask follow it) |
| the COLLECT record layout (stride 8, tile code 2 bytes at offset 4 — the CPS-2 sprite entry) | **board** | `collect = { stride, offset, width }`; env `COLLECT_STRIDE` / `COLLECT_OFFSET` / `COLLECT_WIDTH` override |
| printed widths (`%04x` ports, `%06x` PCs and offsets) | **board** | `port_hex_digits`; PC digits derived from `crash.pc_mask` |
| the STACK sketch: 64 longs walked, 16 listed | **policy** | env `GUARD_STACK_DEPTH` / `GUARD_STACK_SHOWN` (both guards) |
| PCWEEDS suppressed after 10 lines | **policy** | env `GUARD_WEEDS_MAX` |
| GUARD_BREAK stops before frame 100 are "the boot pass" | **policy** | env `GUARD_BREAK_AFTER` |
| the ALIVE heartbeat every 600 frames | **policy** | env `ALIVE_EVERY` |
| `TAIL_FRAMES` 120, `GUARD_PROBE_MAX` 400, `MAX_FRAMES` 200000, `STOP_AFTER` 600, `WATCH_KEEP` 60, `FRAMES` 3600 | **policy** (the lineage's values, stated in each header) | env, as before; `read_tap.lua`'s `FRAMES` default was 5450 — one lineage replay's length — and is 3600 like the other taps |
| `[machine].profile` | **config, NO default** | a consumer names a board or omits the section; nothing is exported and a MAME driver refuses to run without `BBH_PROFILE`. The example omits it (its fake driver runs no Lua) |
| `[inp].*` (`vsavjw`, a build dir, the pinned MAME) | **config, the lineage's literals** | documented as such in `docs/config.md`; `[inp].profile` `""` falls back to `[machine].profile` |
| a maximum replay length | **none on the MAME side** | the lineage's FBNeo frontend caps at 10,000,000 frames in its C patch; a cap here would be a `[suite]` policy key, not a profile key |

**[BBH-79]** The rule the table encodes: a BOARD fact goes in the profile (the TEMPLATE
carries it, the census test demands it), a POLICY value is an environment
variable whose default is stated in the script's header, and a CONFIG
value is the consumer's — with no silent default where the value names a
machine.

## 6. What stayed with the lineage

`run_sim_jtcps2.sh` (the Verilator driver: jtframe-shaped, the download
offset, the per-core RAM-dump offset); every gate that names an address of
one game; the COLLECT mode's bucketing constants (now `COLLECT_STRIDE` /
`COLLECT_OFFSET` / `COLLECT_PORTED` in the environment, the lineage's values
documented in `tap_writes.lua`); the lineage's own `tests/lua/*.lua`, which
stay as they are (`docs/conventions.md` 6 — that tree never consumes this
harness; its own scope document says the same).
