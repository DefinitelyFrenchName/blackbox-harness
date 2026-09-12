# Conventions — the harness's ruled defaults, and what each would cost to change

The harness was extracted under stated assumptions, each open to veto until
its maintainer ruled on it (2026-09-07). **[BBH-84]** This page is the register: what
each default IS, why, and the alternative that was declined. A default that
is not written down is a default nobody can veto; a change to any row here
is a ruling, dated in place, never a silent edit. (The license is NOT a
row: GPL-3.0 is load-bearing on legal and use scope, not a technical
default — `README.md` states it.)

1. **A separate repository, this one; the CLI prefix is `bbh`.** Ruled at
   the plan stage (2026-09-06). A consumer clones or forks it; nothing here
   depends on any consumer's tree.

2. **[BBH-85]** **A consumer finds the harness by `$BBH_HOME`, and by convention beside
   its tree or its tree's parent; it is never a submodule.** Ruled
   2026-09-07. A submodule would pin a version and make the pairing
   explicit, at the price of a pin-bump ritual and a push-order trap (a pin
   bump pushed ahead of the commit it names breaks every fresh clone's
   `git submodule update`). The harness is a test of the harness, not an
   instrument of any consumer's artifact, so it does not need pinning. The
   cost that stays: the two repositories move TOGETHER — see 10.

3. **[BBH-86]** **Lifted comments keep their incident citations (`14z-N` session tags,
   `GitHub #N`) as history lines; no consumer's rule anchor travels.** Ruled
   2026-09-07. The citations name dated incidents that make a guard legible,
   and the archive that resolves them is public. Bare rule IDs from the
   lineage (three `[CPE-N]` references at the ruling) dangle for a reader
   here; they are translated into words when the harness skill is written,
   which decides which IDs exist in the harness's world.

4. **[BBH-87]** **Drivers: `fake`, `mame`, `mame_guarded`, `fbneo`. An FPGA/Verilator
   driver stays with its consumer.** Ruled 2026-09-07. The lineage's
   Verilator lane produces per-frame RAM dumps rather than the replay log
   grammar, needs a forked core and a generated ROM image, and runs at about
   a second per frame; a contract driver would synthesise the checksum log
   and refuse most of the replay family. About one session — spent when a
   SECOND jtframe consumer exists. A generic thing needs two instances.

5. **Documentation tools are OUT.** Ruled 2026-09-07. Their subject is a
   documentation discipline, not a test harness; they might join a
   TOP-LAYER package that handles documentation, if one is ever built, and
   not before.

6. **[BBH-66]** **A consumer that does not consume the harness keeps its config HERE
   (`example/consumers/<name>.toml`), and that config's `[project].root` is
   one host's layout — so the consumer's own gate passes its location as
   `BBH_FIDELITY_ROOT`, and `selftest/test_fidelity_vampire.sh` derives a
   private copy of the config with that absolute root.** Ruled 2026-09-07,
   with the input added the same day: before it, the lineage's fidelity
   gate failed on any clone whose directory layout differed from the
   author's, for a reason that was not fidelity. Deliberately NOT an
   environment override inside the config resolver: that would leak into
   every other config the same run opens (the fake repo of F1, the example).

7. **[BBH-82]** **ONE verdict classifier, `lib/sh/classify.sh`, the STRONGER of the two
   copies the lineage carried** (the timeout exits, exit 0 after the
   shell's own error line as FAIL, the SKIP marker last), its regexes and
   exit list `[classify]` config. Ruled 2026-09-07 as RESOLVED rather than
   defaulted: the lineage adopted the same one copy in all three of its
   runners the same day, and F2 — the whole live portable tier through both
   static runners — measured identical (65 rows).

8. **[BBH-83]** **The fidelity contract's text is never changed silently.** Ruled
   2026-09-07, replacing the extraction-era rule "no verdict-string change
   before the last slice is green" (expired by its own terms when the last one landed). A
   verdict-text or classifier change lands on BOTH sides in one sitting,
   the fidelity rows it moves re-baselined in the same commits, the harness
   commit pushed BEFORE the consumer's — and it is LOUD: a dated line in
   `docs/rebaselines.md`, whose newest line every fidelity run prints at
   its head. The maintainer's word: *"such a change needs to be loud though,
   I wouldn't want it to be silent."*

9. **The docs stay LEAN and anchored; the complete LOG lives in
   `<name>_history.md` twins.** Ruled 2026-09-07 with decision 5 of the
   skill's scope, in the maintainer's words: *"to avoid the logging part
   becoming too big, the harness should use the anchored key system to
   keep the docs lean and quick to search through and have `_HISTORY`
   files with the complete LOG separately for completeness of
   information."* A reference page carries one rule per paragraph, anchored
   `**[BBH-N]**` where a skill distils it; its twin carries the dated
   measurements and the incident narrative, no anchor, and is read as a
   LOG by the skills lock (`docs/doctrine.md` §3). This page's twin is
   `docs/conventions_history.md`.
