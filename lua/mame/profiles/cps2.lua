-- profiles/cps2.lua — THE FIRST MACHINE PROFILE: a stock CPS-2 board under
-- MAME (the lineage's `vsavj`; a 4 MB 68000 program window). Every value
-- here is the literal the lineage's tests/lua/replay.lua, replay_guard.lua
-- and inp_guard.lua carried in source. Proved by fidelity F8 (the lineage's
-- driver and drivers/mame.sh produce byte-identical logs on the same
-- replay), not by inspection.
--
-- profiles/cps2w.lua is the CPS-2 WIDE variant (a 6 MB program window);
-- profiles/TEMPLATE.lua explains every key.
return {
    name   = "cps2",
    cpu    = ":maincpu",
    space  = "program",
    screen = ":screen",

    -- the checksum window; MASK_RANGES offsets count from lo
    ram = { lo = 0xFF0000, hi = 0xFFFFFF },

    -- inputs are ACTIVE LOW: idle reads all-ones on the controlled bits
    active_low = true,

    -- replay sides: token -> { port tag, field name }; width = characters per token
    sides = {
        p1 = { width = 1, tokens = {
            U = { ":IN0", "P1 Up" },       D = { ":IN0", "P1 Down" },
            L = { ":IN0", "P1 Left" },     R = { ":IN0", "P1 Right" },
            ["1"] = { ":IN0", "P1 Button 1" }, ["2"] = { ":IN0", "P1 Button 2" },
            ["3"] = { ":IN0", "P1 Button 3" }, ["4"] = { ":IN1", "P1 Button 4" },
            ["5"] = { ":IN1", "P1 Button 5" }, ["6"] = { ":IN1", "P1 Button 6" },
        } },
        p2 = { width = 1, tokens = {
            U = { ":IN0", "P2 Up" },       D = { ":IN0", "P2 Down" },
            L = { ":IN0", "P2 Left" },     R = { ":IN0", "P2 Right" },
            ["1"] = { ":IN0", "P2 Button 1" }, ["2"] = { ":IN0", "P2 Button 2" },
            ["3"] = { ":IN0", "P2 Button 3" }, ["4"] = { ":IN1", "P2 Button 4" },
            ["5"] = { ":IN1", "P2 Button 5" }, ["6"] = { ":IN2", "P2 Button 6" },
        } },
        sys = { width = 2, tokens = {
            S1 = { ":IN2", "1 Player Start" }, S2 = { ":IN2", "2 Players Start" },
            C1 = { ":IN2", "Coin 1" },         C2 = { ":IN2", "Coin 2" },
            SV = { ":IN2", "Service 1" },      TS = { ":IN2", "Service Mode" },
        } },
    },

    -- the input ports, in the order INPUT_OUT and the integrity assertion log them
    ports = { ":IN0", ":IN1", ":IN2" },
    port_hex_digits = 4,        -- a port value's printed width (16-bit ports)

    -- tap_writes.lua's COLLECT mode: the machine's sprite-list record — an
    -- entry every `stride` bytes, the tile code `width` bytes wide at `offset`
    collect = { stride = 8, offset = 4, width = 2 },

    -- INPUT_INJECT_TEST: replay.lua presses this side/token for one frame;
    -- replay_guard.lua clears `inject_bit` of ports[1] on its read
    inject     = { "p1", "1" },
    inject_bit = 0x01,

    -- the crash guard (replay_guard.lua) and the recording guard (inp_guard.lua)
    crash = {
        -- exception vectors to trap under -debug: bus/address/illegal/div0/CHK/TRAPV/spurious
        vectors       = "2,3,4,5,6,7,24",
        vector_base   = 0,          -- the vector table's address
        vector_stride = 4,          -- bytes per vector
        group0        = { [2] = true, [3] = true },   -- vectors whose frame carries a fault address
        -- the exception frame: PC at SP+10 for a group-0 frame (FC.w, addr.l, IR.w, SR.w, PC.l), SP+2 otherwise (SR.w, PC.l)
        pc_at_sp      = { group0 = 10, other = 2 },
        addr_at_sp    = 2,
        -- a ROM-plausible long (return addresses in the stack sketch; handler addresses)
        code          = { lo = 0x000100, hi = 0x400000 },
        stack_top     = 0xFFFFFC,   -- the stack sketch stops here
        pc_mask       = 0xFFFFFF,
        regs          = { "D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7",
                          "A0", "A1", "A2", "A3", "A4", "A5", "A6" },
        sp            = { "A7", "SP" },   -- the stack pointer's name, first that exists
        -- the game's OWN exception-code store (inp_guard.lua): every handler
        -- begins with a .w store of its code here; vector = code + store_to_vector
        exception_store  = 0xFF0000,
        store_width      = 2,       -- the handlers store a .w
        store_to_vector  = 2,
        store_code_max   = 9,       -- codes above this are not exception codes (boot RAM tests)
        arm_frame        = 300,     -- ignore stores before this frame (boot-time RAM tests)
        -- the in-match flag (GUARD_MATCH; the recording guard's ALIVE line)
        match = { addr = 0xFF8004, width = 4, value = 0x40000 },
        -- the recording guard's ALIVE line: name, address, width
        alive = { { "match", 0xFF8004, 4 }, { "p1", 0xFF8402, 1 }, { "p2", 0xFF8802, 1 } },
    },
}
