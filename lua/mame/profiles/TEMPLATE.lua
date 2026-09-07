-- profiles/TEMPLATE.lua — every key a machine profile may carry, with what
-- reads it. Copy to profiles/<board>.lua, fill in, point BBH_PROFILE at it.
-- profile.lua REFUSES a profile missing a REQUIRED key; the guard scripts
-- refuse one missing a crash.* key they read. A profile is proved the way
-- cps2.lua was: the harness driver and a hand-written driver produce the
-- same log on the same replay (fidelity F8) — never by inspection.
return {
    -- REQUIRED — replay.lua and every instrument
    name   = "template",       -- printed in messages
    cpu    = ":maincpu",       -- the CPU device tag (manager.machine.devices[cpu])
    space  = "program",        -- the address space the RAM window and pokes live in
    screen = ":screen",        -- the screen device for VIDEO_OUT / SNAP_FRAMES (nil = no video)
    ram    = { lo = 0x0000, hi = 0xFFFF },   -- the checksum window, inclusive; MASK_RANGES offsets count from lo
    active_low = true,         -- true: idle input bits read 1, a press clears them (the lineage's CPS-2)

    -- REQUIRED — the replay grammar's sides: token -> { port tag, field name }
    sides = {
        p1  = { width = 1, tokens = { U = { ":IN0", "P1 Up" } } },
        sys = { width = 2, tokens = { S1 = { ":IN2", "1 Player Start" } } },
    },
    -- REQUIRED — the ports the integrity assertion reads and INPUT_OUT logs, in log order
    ports = { ":IN0", ":IN1", ":IN2" },

    -- INPUT_INJECT_TEST: the must-fire control of the integrity assertion
    inject     = { "p1", "U" },   -- replay.lua presses this side/token for one frame
    inject_bit = 0x01,            -- replay_guard.lua clears this bit of ports[1] on its read

    -- the crash guard (replay_guard.lua, -debug) and the recording guard (inp_guard.lua)
    crash = {
        vectors       = "2,3,4",                  -- CRASH_VECTORS default: vector numbers to trap
        vector_base   = 0,                        -- where the vector table lives
        vector_stride = 4,                        -- bytes per vector entry
        group0        = { [2] = true, [3] = true },   -- vectors whose exception frame carries a fault address
        pc_at_sp      = { group0 = 10, other = 2 },   -- offset of the pushed PC from SP, per frame kind
        addr_at_sp    = 2,                        -- offset of the fault address (group-0 frames)
        code          = { lo = 0x100, hi = 0x400000 },   -- a ROM-plausible long: handler addresses, the stack sketch
        stack_top     = 0xFFFFFC,                 -- the stack sketch stops at this address
        pc_mask       = 0xFFFFFF,                 -- the CPU's address width
        regs          = { "D0", "A0" },           -- registers on the REGS line, in order (names from cpu.state)
        sp            = { "A7", "SP" },           -- the stack pointer register, first name that exists
        -- inp_guard.lua: the game's own exception-code store, if it keeps one
        exception_store = 0xFF0000,               -- a .w store here begins every handler
        store_to_vector = 2,                      -- vector = stored code + this
        store_code_max  = 9,                      -- larger stored values are not exception codes
        arm_frame       = 300,                    -- ARM_FRAME default: ignore stores before it
        match = { addr = 0xFF8004, width = 4, value = 0x40000 },   -- GUARD_MATCH's in-match flag
        alive = { { "match", 0xFF8004, 4 } },     -- inp_guard's ALIVE line: { name, address, width }, …
        -- OPTIONAL register lists (each has a 68000-shaped default when absent):
        probe_regs = { "D0", "D1", "A0", "A1", "A3", "A6" },   -- replay_guard's PROBE line
        trace_regs = { "D0", "D1", "A0", "A1", "A2", "A3", "A4", "A6" },   -- trace_writes' hit line
        tap_regs   = { "D0", "D1", "D2", "D3", "A0", "A1", "A2", "A3", "A4", "A6" },   -- tap_writes' REGLOG
    },
}
