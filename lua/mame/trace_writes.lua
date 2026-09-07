-- trace_writes.lua — log every access hitting a watched RAM range: PC,
-- value and register state, through a DEBUGGER watchpoint. The standard
-- tool for "who initializes this field?" (requires -debug on the command
-- line — drivers/mame.sh does not add it; run the emulator directly or
-- through a guarded invocation).
--
--   env BBH_PROFILE  the machine profile (required)
--   env REPLAY       optional input script (the .rpl grammar)
--   env WATCH        "ff8480,4" (start,len) or "ff8480,4,r" / "...,rw"
--                    (watch mode; default w = writes); mode "b" sets an
--                    EXECUTION BREAKPOINT at the address instead (len
--                    ignored) — log registers at a PC.
--                    An optional 4th field selects the ADDRESS SPACE:
--                    "8f216,4,r,o" watches the OPCODES space (wposet),
--                    "…,d" the data space, default/"p" the program space.
--                    THIS MATTERS on CPUs whose pc-relative reads go through
--                    the opcode space (the lineage's 68000: every jump or
--                    handler table indexed pc-relative): a plain wpset on
--                    such a table is SILENTLY BLIND and reports zero hits,
--                    which reads as "this table is never used".
--   env TRACE_OUT    log path (default trace_writes.txt)
--   env FRAMES       stop after this many frames (default 3600)
--   env DUMPS        "frame:lo-hi;..." — RAM dumps written next to
--                    TRACE_OUT as dump_<frame>_<lo>.bin. Every -debug watch
--                    configuration is its own TIMELINE (the lineage measured
--                    three same-poke trace runs taking three different
--                    trajectories), so state anchors must come from the
--                    SAME run as the trace or the hits cannot be
--                    interpreted. A trace run should be self-documenting.
--   env POKES        "frame:addr:hexbytes;..." scheduled RAM writes
--
-- Each hit logs: frame, PC, and the profile's crash.regs (or a default
-- register list) — enough to identify a source table pointer for a
-- table-copy loop without a full instruction trace.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$"))
    or (os.getenv("BBH_HOME") and (os.getenv("BBH_HOME") .. "/lua/mame")) or "."
local profile = dofile(HERE .. "/profile.lua")
local rpl = dofile(HERE .. "/rpl_parse.lua")
local P = profile.load()

local watch = assert(os.getenv("WATCH"), "set WATCH=start,len")
local out_path = os.getenv("TRACE_OUT") or "trace_writes.txt"
local max_frames = tonumber(os.getenv("FRAMES") or "") or 3600

local machine = manager.machine
local debugger = machine.debugger
assert(debugger, "run mame with -debug")
local cpu = machine.devices[P.cpu]
assert(cpu, "no CPU device " .. P.cpu)

local f = assert(io.open(out_path, "wb"))
local frame = 0
local hits = 0

-- input playback
local held = {}
local FIELDS = nil
local replay_path = os.getenv("REPLAY")
if replay_path then
    FIELDS = profile.bind(P, machine.ioport)
    local held_wt = rpl.parse(replay_path, P.sides)
    held = profile.held_fields(FIELDS, held_wt)
end

-- LENGTH IS HEX, and it must be matched as hex. MAME's debugger parses
-- `wpset addr,len,...` numbers as HEX, so a length of "a" means ten bytes
-- and "10" means sixteen. The lineage's pattern once demanded %d+ for the
-- length, so a hex-lettered length failed the match, the assert killed the
-- run BEFORE the replay started, and the trace file came out EMPTY — which
-- reads downstream as "zero accesses, this address is never touched".
local start_addr, len, mode, space = watch:match("^(%x+),(%x+),?(%a*),?(%a*)$")
assert(start_addr, "WATCH format: hexaddr,hexlen[,r|w|rw][,p|d|o]")
if mode == "" then mode = "w" end
if space == "" then space = "p" end
local WPCMD = { p = "wpset", d = "wpdset", o = "wposet" }
assert(WPCMD[space], "WATCH space must be p (program), d (data) or o (opcodes)")

-- register the watchpoint (or breakpoint, mode "b") on the profile's CPU
debugger:command("focus 0")
if mode == "b" then
    debugger:command(string.format("bpset %s", start_addr))
else
    debugger:command(string.format("%s %s,%s,%s", WPCMD[space], start_addr, len, mode))
end

local poke_space = cpu.spaces[P.space]
-- DUMPS: same grammar/application point as replay.lua's; files land next to TRACE_OUT.
local dumps = {}
for spec in (os.getenv("DUMPS") or ""):gmatch("[^;]+") do
    local fr, lo, hi = spec:match("^(%d+):(%x+)-(%x+)$")
    assert(fr, "DUMPS spec must be frame:hexlo-hexhi — got " .. spec)
    dumps[#dumps + 1] = { tonumber(fr), tonumber(lo, 16), tonumber(hi, 16) }
end
local dump_dir = out_path:match("^(.*)/") or "."
local pokes = {}
for spec in (os.getenv("POKES") or ""):gmatch("[^;]+") do
    local fr, addr, hexs = spec:match("^(%d+):(%x+):(%x+)$")
    if fr then pokes[#pokes + 1] = { tonumber(fr), tonumber(addr, 16), hexs } end
end

local TRACE_REGS = (P.crash and P.crash.trace_regs)
    or { "D0", "D1", "A0", "A1", "A2", "A3", "A4", "A6" }

local pressed = {}
emu.register_frame_done(function()
    frame = frame + 1
    for _, pk in ipairs(pokes) do
        if pk[1] == frame then
            local a = pk[2]
            for b in pk[3]:gmatch("%x%x") do
                poke_space:write_u8(a, tonumber(b, 16))
                a = a + 1
            end
        end
    end
    for _, dm in ipairs(dumps) do
        if dm[1] == frame then
            local df = assert(io.open(string.format("%s/dump_%d_%x.bin",
                                                    dump_dir, frame, dm[2]), "wb"))
            local bytes = {}
            for a = dm[2], dm[3] - 1 do
                bytes[#bytes + 1] = string.char(poke_space:read_u8(a))
            end
            df:write(table.concat(bytes)); df:close()
        end
    end
    if FIELDS then
        local want = {}
        for _, fldo in ipairs(held[frame + 1] or {}) do want[fldo] = true end
        for _, fldo in ipairs(FIELDS.all) do
            if want[fldo] and not pressed[fldo] then fldo:set_value(1); pressed[fldo] = true
            elseif not want[fldo] and pressed[fldo] then fldo:clear_value(); pressed[fldo] = nil end
        end
    end
    if frame >= max_frames then
        f:write(string.format("END %d hits %d\n", frame, hits))
        f:close()
        manager.machine:exit()
    end
end)

emu.register_periodic(function()
    if debugger.execution_state == "stop" then
        local st = cpu.state
        local parts = { string.format("frame %d PC %06x", frame, st["CURPC"].value) }
        for _, rn in ipairs(TRACE_REGS) do
            parts[#parts + 1] = string.format("%s %08x", rn, st[rn].value)
        end
        f:write(table.concat(parts, " ") .. "\n")
        hits = hits + 1
        debugger.execution_state = "run"
    end
end)
