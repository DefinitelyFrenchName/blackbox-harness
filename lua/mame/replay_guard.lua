-- replay_guard.lua — replay.lua plus crash detection: identical checksum-log
-- output, plus CRASH/PCWEEDS/SOFTRESET lines when the machine leaves the
-- rails. Lineage: VampireSaved tests/lua/replay_guard.lua, the CPU facts
-- (vectors, the exception-frame layout, the code window, register names)
-- moved into the MACHINE PROFILE's `crash` table.
--
-- SUBSTITUTABILITY, STATED HONESTLY (the lineage's GitHub #31): this script
-- does not implement MASK_RANGES and REFUSES to run when MASK_RANGES or
-- NO_INPUT_CHECK is set rather than ignoring them (drivers/mame_guarded.sh
-- refuses them before the emulator starts). Substitutable for UNMASKED
-- comparisons; for a masked one, use replay.lua.
--
-- Two modes, auto-selected:
--   * authoritative (run with -debug -debugger none): breakpoints on the
--     exception handlers (the vector table read from ROM at boot). A trip
--     logs "CRASH <frame> vec<n> PC <fault_pc> SP <sp> [ADDR <fault_addr>]",
--     a stack sketch (ROM-plausible longs walking up from SP), dumps the RAM
--     window to crash_<frame>_<lo>.bin, writes "END-CRASH <frame>", exits.
--   * cheap (no -debug; soak-grade, sampling can miss transient excursions):
--     per-frame CURPC classified against CODE_RANGES; the in-match flag
--     watched over GUARD_MATCH. Logs PCWEEDS/SOFTRESET, keeps running.
--
-- CAVEAT: -debug runs are deterministic but their checksum logs are NOT
-- comparable to non-debug expectations — the debugger changes the
-- scheduler's timeslicing. Cheap mode produces canonical checksums.
--
-- Usage: mame <set> [-debug -debugger none] -autoboot_script replay_guard.lua
--   env BBH_PROFILE / REPLAY / CHECKSUM_OUT / TAIL_FRAMES / SNAP_FRAMES /
--       DUMPS / POKES / INPUT_INJECT_TEST   as replay.lua
--   env CRASH_VECTORS authoritative mode: vectors to trap (default: the
--                     profile's crash.vectors)
--   env CODE_RANGES   cheap mode: "start-end,start-end" hex PC whitelist;
--                     unset = no PC check
--   env GUARD_MATCH   cheap+auth: "a-b" frames during which the profile's
--                     match flag must hold its value; unset = no check
--   env GUARD_PC_LOG="a-b"      log CURPC at the end of every frame in [a,b]
--   env GUARD_TRACE="a-b"       instruction trace over [a,b] to <CHECKSUM_OUT>.trace (-debug)
--   env GUARD_BREAK=<hexaddr>   break there and report like a crash (vec99)
--   env GUARD_PROBE=<hexaddr> [GUARD_PROBE_COND=<expr>] [GUARD_PROBE_MEM=<reg>+<hexoff>]
--       [GUARD_PROBE_MAX=n] [GUARD_PROBE_HIST=n] [GUARD_PROBE_TRACE=<path>]
--                     conditional LOGGING breakpoint — PROBE lines, run continues
--   env GUARD_FORCE="<hexaddr>:<minframe>:REG=hex,..."  one-shot register forcing
--
-- Log grammar (grep-able): normal "<frame> <fnv1a64>" lines, then any of
--   CRASH <frame> vec<n> PC <pc6> SP <sp8> ADDR <addr8>|-
--   REGS <reg>=<val> ...
--   STACK <sp8> <val8>            (up to 16 ROM-plausible return addresses)
--   PCWEEDS <frame> <pc6>         (max 10, then suppressed)
--   SOFTRESET <frame> <val8>
--   PROBE <frame> D0=.. ... RET <sp0.l> [MEM[reg+off]=bb]
--   INPUT-VIOLATION <frame> <port> live <v> expected <v>
-- and finally "END <n>" (clean) or "END-CRASH <frame>" (crashed).

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$"))
    or (os.getenv("BBH_HOME") and (os.getenv("BBH_HOME") .. "/lua/mame")) or "."
local profile = dofile(HERE .. "/profile.lua")
local rpl = dofile(HERE .. "/rpl_parse.lua")
local P = profile.load()
local C = profile.require_crash(P)

local replay_path = assert(os.getenv("REPLAY"), "set REPLAY to the input script path")
local out_path = os.getenv("CHECKSUM_OUT") or "replay_checksums.txt"
local tail_frames = tonumber(os.getenv("TAIL_FRAMES") or "") or 120

-- ── WHAT THIS SCRIPT DOES NOT IMPLEMENT, STATED LOUDLY ──────────────────
-- A masked comparison run through the guard would produce a WHOLE-window log
-- with the ratified windows still in it — compared against a masked basis,
-- a phantom regression with no reachable green state. Silently ignoring an
-- env var that changes what a log MEANS is worse than not supporting it.
if os.getenv("MASK_RANGES") then
    error("replay_guard.lua does not implement MASK_RANGES. Its log would be "
       .. "unmasked and would not be comparable to a masked basis. Use "
       .. "replay.lua for masked comparisons.", 0)
end
if os.getenv("NO_INPUT_CHECK") then
    error("NO_INPUT_CHECK is replay.lua's opt-out; setting it here implies an "
       .. "integrity check you did not get. Remove it, or use replay.lua.", 0)
end

-- ── field lookup + parse (identical to replay.lua) ───────────────────────────

local ioport = manager.machine.ioport
local F = profile.bind(P, ioport)
local FIELDS, FIELD_INFO = F.fields, F.info
local held_wt, last_frame = rpl.parse(replay_path, P.sides)
local held = profile.held_fields(F, held_wt)

local total_frames = last_frame + tail_frames

local snap_at = {}
for n in (os.getenv("SNAP_FRAMES") or ""):gmatch("%d+") do
    local fr = tonumber(n)
    snap_at[fr] = true
    if fr + 1 > total_frames then total_frames = fr + 1 end
end

local dump_at = {}
local out_dir = out_path:match("^(.*)/[^/]+$") or "."
for spec in (os.getenv("DUMPS") or ""):gmatch("[^;]+") do
    local fr, first, last = spec:match("^(%d+):(%x+)%-(%x+)$")
    assert(fr, "bad DUMPS spec: " .. spec)
    fr = tonumber(fr)
    dump_at[fr] = dump_at[fr] or {}
    table.insert(dump_at[fr], { tonumber(first, 16), tonumber(last, 16) })
    if fr + 1 > total_frames then total_frames = fr + 1 end
end

-- ── guard config ─────────────────────────────────────────────────────────────

local machine = manager.machine
local cpu = machine.devices[P.cpu]
assert(cpu, "no CPU device " .. P.cpu .. " (profile " .. P.path .. ")")
local program = cpu.spaces[P.space]
assert(program, "no address space " .. P.space .. " on " .. P.cpu)
local debugger = machine.debugger  -- nil unless -debug
local RAM_LO, RAM_HI = P.ram.lo, P.ram.hi
local PC_MASK = C.pc_mask

local function sp_of(st)
    for _, n in ipairs(C.sp) do
        local ok, v = pcall(function() return st[n].value end)
        if ok and v then return v end
    end
    error("no stack-pointer register among " .. table.concat(C.sp, "/"), 0)
end

local code_ranges = {}
for a, b in (os.getenv("CODE_RANGES") or ""):gmatch("(%x+)%-(%x+)") do
    code_ranges[#code_ranges + 1] = { tonumber(a, 16), tonumber(b, 16) }
end

local match_a, match_b
do
    local a, b = (os.getenv("GUARD_MATCH") or ""):match("^(%d+)%-(%d+)$")
    if a then match_a, match_b = tonumber(a), tonumber(b) end
end
local function read_width(addr, width)
    if width == 4 then return program:read_u32(addr)
    elseif width == 2 then return program:read_u16(addr)
    else return program:read_u8(addr) end
end

-- GUARD_PC_LOG="a-b": log CURPC at end of every frame in [a,b] (loop hunts)
local pclog_a, pclog_b
do
    local a, b = (os.getenv("GUARD_PC_LOG") or ""):match("^(%d+)%-(%d+)$")
    if a then pclog_a, pclog_b = tonumber(a), tonumber(b) end
end

-- GUARD_TRACE="a-b": debugger instruction trace over frames [a,b] to
-- <CHECKSUM_OUT>.trace (needs -debug)
local trace_a, trace_b
do
    local a, b = (os.getenv("GUARD_TRACE") or ""):match("^(%d+)%-(%d+)$")
    if a then trace_a, trace_b = tonumber(a), tonumber(b) end
end

local f = assert(io.open(out_path, "wb"))
local frame = 0
local crashed = false
local weeds_logged = 0

-- authoritative mode: map exception-handler address -> vector number.
-- Vector reads are data-space accesses, so program-space reads here see
-- the same values the CPU uses.
local handler_vec = {}
if debugger then
    local vecs = {}
    for n in (os.getenv("CRASH_VECTORS") or C.vectors):gmatch("%d+") do
        vecs[#vecs + 1] = tonumber(n)
    end
    debugger:command("focus 0")
    for _, n in ipairs(vecs) do
        local h = program:read_u32(C.vector_base + n * C.vector_stride)
        if h < C.code.hi and h % 2 == 0 then
            if not handler_vec[h] then
                handler_vec[h] = n
                -- 0x prefix is load-bearing: bare hex like "d0" parses as
                -- the REGISTER D0 in debugger expressions
                debugger:command(string.format("bpset 0x%x", h))
            end
        end
    end
end

local function rom_plausible(v)
    return v >= C.code.lo and v < C.code.hi and v % 2 == 0
end

local function on_crash(vec)
    crashed = true
    local st = cpu.state
    local sp = sp_of(st)
    local fault_pc, fault_addr
    if C.group0[vec] then
        fault_addr = program:read_u32(sp + C.addr_at_sp)
        fault_pc = program:read_u32(sp + C.pc_at_sp.group0)
    else
        fault_pc = program:read_u32(sp + C.pc_at_sp.other)
    end
    f:write(string.format("CRASH %d vec%d PC %06x SP %08x ADDR %s\n",
        frame, vec, fault_pc & PC_MASK, sp,
        fault_addr and string.format("%08x", fault_addr) or "-"))
    local regs = {}
    for _, rn in ipairs(C.regs) do
        local ok, v = pcall(function() return st[rn].value end)
        regs[#regs + 1] = string.format("%s=%08x", rn, ok and v or 0)
    end
    f:write("REGS " .. table.concat(regs, " ") .. "\n")
    -- stack sketch: ROM-plausible longs walking up from SP
    local shown = 0
    for off = 0, 63 * 4, 4 do
        local a = sp + off
        if a >= C.stack_top then break end
        local v = program:read_u32(a)
        if rom_plausible(v) then
            f:write(string.format("STACK %08x %08x\n", a, v))
            shown = shown + 1
            if shown >= 16 then break end
        end
    end
    -- crash-time instruction history (opt-in via GUARD_PROBE_HIST, the same
    -- env as the probe-hit history). A group-0 exception pushes a
    -- MID-INSTRUCTION PC, so the CRASH line alone cannot name the
    -- instruction STREAM into the fault; the debugger's `history` at the
    -- handler breakpoint can.
    local nh = tonumber(os.getenv("GUARD_PROBE_HIST") or "") or 0
    if nh > 0 and debugger then
        pcall(function()
            debugger:command(string.format("history %s,%d", P.cpu:gsub("^:", ""), nh))
            local cl = debugger.consolelog
            local n = #cl
            for i = math.max(1, n - nh), n do
                f:write("HIST " .. tostring(cl[i]) .. "\n")
            end
        end)
    end
    local df = assert(io.open(string.format("%s/crash_%d_%06x.bin", out_dir, frame, RAM_LO), "wb"))
    df:write(program:read_range(RAM_LO, RAM_HI, 8))
    df:close()
    f:write(string.format("END-CRASH %d\n", frame))
    f:close()
    machine:exit()
end

-- GUARD_BREAK="hexaddr": break there and report like a crash (with stack
-- sketch) — e.g. the soft-reset entry, to catch who restarted the game
local break_addr = tonumber(os.getenv("GUARD_BREAK") or "", 16)
if debugger and break_addr then
    debugger:command(string.format("bpset 0x%x", break_addr))
end

-- GUARD_PROBE="hexaddr": conditional LOGGING breakpoint — on each hit write
--   PROBE <frame> <regs…> RET <(SP)>
-- and CONTINUE (unlike GUARD_BREAK, which reports and exits). Optional
-- GUARD_PROBE_COND holds a raw debugger condition. Capped at 400 hits by
-- default (then the bp is cleared and a PROBE-CAP line written);
-- GUARD_PROBE_MAX raises the cap — the default silently truncates a census
-- of a HOT site (the lineage's 14z-69p audit "proved" one id from the first
-- 400 calls). Raise it whenever the question is "what values does this
-- site EVER see".
local probe_addr = tonumber(os.getenv("GUARD_PROBE") or "", 16)
local PROBE_REGS = C.probe_regs or { "D0", "D1", "A0", "A1", "A3", "A6" }
-- GUARD_PROBE_MEM="<reg>+<hexoff>" appends MEM=<byte> to each PROBE line:
-- the byte at that register plus offset AT THE MOMENT OF THE HIT.
local probe_mem_reg, probe_mem_off
do
    local pm = os.getenv("GUARD_PROBE_MEM")
    if pm and #pm > 0 then
        probe_mem_reg, probe_mem_off = pm:match("^(%a%d?)%+(%x+)$")
        probe_mem_off = tonumber(probe_mem_off or "", 16)
    end
end
local probe_cond = os.getenv("GUARD_PROBE_COND")
-- GUARD_FORCE="<hexaddr>:<minframe>:REG=hexval[,REG=hexval...]": ONE-SHOT
-- register forcing at a breakpoint — the deterministic rig for data-path
-- fixes. On the first stop at <hexaddr> with frame >= <minframe>: set the
-- named registers, write "FORCE <frame> <reglist>", resume; later stops at
-- the address resume without acting. Composes with POKES and with the crash
-- detection — a forced dispatch that faults still reports CRASH normally.
local force_addr, force_minframe, force_regs, force_done = nil, 0, {}, false
do
    local fspec = os.getenv("GUARD_FORCE")
    if fspec and #fspec > 0 then
        local a2, mf, rl = fspec:match("^(%x+):(%d+):(.+)$")
        assert(a2, "GUARD_FORCE must be hexaddr:minframe:REG=hex,...")
        force_addr = tonumber(a2, 16)
        force_minframe = tonumber(mf)
        for r, v in rl:gmatch("(%a%d)=(%x+)") do
            force_regs[#force_regs + 1] = { r:upper(), tonumber(v, 16) }
        end
        assert(#force_regs > 0, "GUARD_FORCE: no REG=hex pairs parsed")
    end
end
local probe_hits = 0
local PROBE_MAX = tonumber(os.getenv("GUARD_PROBE_MAX") or "") or 400
-- GUARD_PROBE_HIST=N: on each probe hit, append the debugger's
-- last-N-instruction `history` as HIST lines. A probe's RET <(SP)> names the
-- caller ONLY for a call-reached entry — a tail-jump leaves (SP) holding
-- unrelated data; history names the real instruction stream into the site.
local PROBE_HIST = tonumber(os.getenv("GUARD_PROBE_HIST") or "") or 0
-- GUARD_PROBE_TRACE=<path>: start a full instruction trace at the FIRST
-- probe hit and stop it at the SECOND — a handler's complete tick is
-- everything between two consecutive dispatches. Large; a diagnosis rig.
local PROBE_TRACE = os.getenv("GUARD_PROBE_TRACE") or ""
local CPU_NAME = P.cpu:gsub("^:", "")
if debugger and probe_addr then
    if probe_cond and #probe_cond > 0 then
        debugger:command(string.format("bpset 0x%x,%s", probe_addr, probe_cond))
    else
        debugger:command(string.format("bpset 0x%x", probe_addr))
    end
end
-- GUARD_FORCE arms LAZILY at minframe and clears after firing: a debugger
-- stop delays the frame_done input application by a beat, so a breakpoint
-- that idles armed outside the needed window turns a clean replay into
-- INPUT-VIOLATIONs. Armed once, cleared once; the bp number is parsed from
-- the debugger console.
local force_armed, force_bpnum = false, nil

if debugger then
    emu.register_periodic(function()
        if crashed then return end
        if debugger.execution_state == "stop" then
            local pc = cpu.state["CURPC"].value & PC_MASK
            local vec = handler_vec[pc]
            if vec then
                on_crash(vec)
            elseif force_addr and pc == force_addr then
                if not force_done and frame >= force_minframe then
                    local parts = {}
                    for _, rv in ipairs(force_regs) do
                        cpu.state[rv[1]].value = rv[2]
                        parts[#parts + 1] = string.format("%s=%x", rv[1], rv[2])
                    end
                    force_done = true
                    if force_bpnum then
                        debugger:command("bpclear " .. force_bpnum)
                    end
                    f:write(string.format("FORCE %d %s\n", frame,
                                          table.concat(parts, ",")))
                end
                debugger.execution_state = "run"
            elseif probe_addr and pc == probe_addr then
                local st = cpu.state
                local sp = sp_of(st)
                local memtxt = ""
                if probe_mem_reg and st[probe_mem_reg] then
                    local at = (st[probe_mem_reg].value + probe_mem_off) & PC_MASK
                    memtxt = string.format(" MEM[%s+%x=%06x]=%02x",
                                           probe_mem_reg, probe_mem_off, at,
                                           program:read_u8(at))
                end
                local rv = {}
                for _, rn in ipairs(PROBE_REGS) do
                    rv[#rv + 1] = string.format("%s=%08x", rn, st[rn].value)
                end
                f:write(string.format("PROBE %d %s RET %08x%s\n",
                    frame, table.concat(rv, " "), program:read_u32(sp), memtxt))
                if PROBE_HIST > 0 then
                    debugger:command(string.format("history %s,%d", CPU_NAME, PROBE_HIST))
                    local cl = debugger.consolelog
                    local n = #cl
                    for i = math.max(1, n - PROBE_HIST), n do
                        f:write("HIST " .. tostring(cl[i]) .. "\n")
                    end
                end
                if PROBE_TRACE ~= "" then
                    if probe_hits == 0 then
                        debugger:command(string.format("trace %s,%s", PROBE_TRACE, CPU_NAME))
                        f:write("TRACE-START\n")
                    elseif probe_hits == 1 then
                        debugger:command("trace off," .. CPU_NAME)
                        f:write("TRACE-STOP\n")
                    end
                end
                probe_hits = probe_hits + 1
                if probe_hits >= PROBE_MAX then
                    debugger:command("bpclear")
                    -- re-arm the crash + break breakpoints the clear removed
                    for h in pairs(handler_vec) do
                        debugger:command(string.format("bpset 0x%x", h))
                    end
                    if break_addr then
                        debugger:command(string.format("bpset 0x%x", break_addr))
                    end
                    f:write("PROBE-CAP\n")
                end
                debugger.execution_state = "run"
            elseif break_addr and pc == break_addr then
                if frame > 100 then  -- ignore the boot-time pass
                    on_crash(99)
                else
                    debugger.execution_state = "run"
                end
            else
                -- initial debugger halt or unrelated stop: resume silently
                debugger.execution_state = "run"
            end
        end
    end)
end

-- ── per-frame drive (replay.lua core + cheap-mode checks) ────────────────────

local FNV_PRIME = 0x100000001b3
local function fnv1a64(s)
    local h = 0xcbf29ce484222325
    local n = #s - (#s % 8)
    for i = 1, n, 8 do
        h = (h ~ string.unpack("<i8", s, i)) * FNV_PRIME
    end
    for i = n + 1, #s do
        h = (h ~ s:byte(i)) * FNV_PRIME
    end
    return h
end

local all_fields = F.all
local pressed = {}

-- POKES="frame:addr:hexbytes;..." — scheduled RAM writes
local pokes = {}
for spec in (os.getenv("POKES") or ""):gmatch("[^;]+") do
    local fr, addr, hexs = spec:match("^(%d+):(%x+):(%x+)$")
    if fr then pokes[#pokes + 1] = { tonumber(fr), tonumber(addr, 16), hexs } end
end

-- ── INPUT INTEGRITY ASSERTION ────────────────────────────────────────────
-- Ported from replay.lua, where it is "deliberately not opt-in": a stray
-- host press otherwise produces a clean PASS on a run that is no longer a
-- replay of anything. (This script keeps the lineage guard's own variant:
-- the baseline is captured from frame 1's live read, and the violation line
-- is written the moment it is seen.)
local PORT_TAGS = P.ports
local integ_ports, baseline, controlled = {}, {}, {}
local violations, first_violation = 0, nil
for _, tag in ipairs(PORT_TAGS) do
    integ_ports[tag] = assert(ioport.ports[tag], "no port " .. tag)
    controlled[tag] = 0
end
-- Compare ONLY the bits this harness can drive.
for _, group in pairs(FIELDS) do
    for _, field in pairs(group) do
        local info = FIELD_INFO[field]
        controlled[info[1]] = controlled[info[1]] | info[2]
    end
end
local inject_frame = tonumber(os.getenv("INPUT_INJECT_TEST") or "")
local INJECT_BIT = P.inject_bit or 0x01

-- Expected port values for a frame's held set: the idle baseline with each
-- pressed field's mask applied.
local function expected_ports(frame_held)
    if not baseline[PORT_TAGS[1]] then return nil end
    local exp = {}
    for _, tag in ipairs(PORT_TAGS) do exp[tag] = baseline[tag] end
    for _, field in ipairs(frame_held or {}) do
        local info = FIELD_INFO[field]
        if info then
            if P.active_low then exp[info[1]] = exp[info[1]] & ~info[2]
            else exp[info[1]] = exp[info[1]] | info[2] end
        end
    end
    return exp
end

emu.register_frame_done(function()
    if crashed then return end
    frame = frame + 1
    for _, pk in ipairs(pokes) do
        if pk[1] == frame then
            local a = pk[2]
            for b in pk[3]:gmatch("%x%x") do
                program:write_u8(a, tonumber(b, 16))
                a = a + 1
            end
        end
    end

    if force_addr and not force_armed and not force_done
       and frame >= force_minframe - 1 and debugger then
        debugger:command(string.format("bpset 0x%x", force_addr))
        local cl = debugger.consolelog
        local last = tostring(cl[#cl] or "")
        force_bpnum = last:match("Breakpoint (%d+) set")
        force_armed = true
    end
    f:write(string.format("%d %016x\n", frame, fnv1a64(program:read_range(RAM_LO, RAM_HI, 8))))
    if snap_at[frame] then machine.video:snapshot() end
    for _, range in ipairs(dump_at[frame] or {}) do
        local df = assert(io.open(string.format("%s/dump_%d_%06x.bin", out_dir, frame, range[1]), "wb"))
        df:write(program:read_range(range[1], range[2], 8))
        df:close()
    end

    if trace_a and frame == trace_a then
        debugger:command(string.format("trace %s.trace,0", out_path))
    end
    if trace_a and frame == trace_b then
        debugger:command("trace off,0")
    end
    if pclog_a and frame >= pclog_a and frame <= pclog_b then
        f:write(string.format("PC %d %06x\n", frame,
                              cpu.state["CURPC"].value & PC_MASK))
    end

    -- cheap-mode PC classification (also harmless under -debug)
    if #code_ranges > 0 then
        local pc = cpu.state["CURPC"].value & PC_MASK
        local ok = false
        for _, r in ipairs(code_ranges) do
            if pc >= r[1] and pc < r[2] then ok = true; break end
        end
        if not ok and weeds_logged < 10 then
            f:write(string.format("PCWEEDS %d %06x\n", frame, pc))
            weeds_logged = weeds_logged + 1
            if weeds_logged == 10 then f:write("PCWEEDS suppressed\n") end
        end
    end
    if match_a and frame >= match_a and frame <= match_b then
        assert(C.match, "GUARD_MATCH needs profile crash.match")
        local v = read_width(C.match.addr, C.match.width)
        if v ~= C.match.value then
            f:write(string.format("SOFTRESET %d %08x\n", frame, v))
        end
    end

    local want = {}
    for _, field in ipairs(held[frame + 1] or {}) do want[field] = true end
    for _, field in ipairs(all_fields) do
        if want[field] and not pressed[field] then
            field:set_value(1); pressed[field] = true
        elseif not want[field] and pressed[field] then
            field:clear_value(); pressed[field] = nil
        end
    end

    -- integrity: frame 1 captures the idle baseline (nothing staged yet);
    -- afterwards the live ports must equal what THIS script staged.
    if not baseline[PORT_TAGS[1]] then
        for _, tag in ipairs(PORT_TAGS) do
            baseline[tag] = integ_ports[tag]:read() & controlled[tag]
        end
    else
        local exp = expected_ports(held[frame])
        for _, tag in ipairs(PORT_TAGS) do
            local live = integ_ports[tag]:read() & controlled[tag]
            if inject_frame and frame == inject_frame and tag == PORT_TAGS[1] then
                -- ground truth: a phantom press
                if P.active_low then live = live & ~INJECT_BIT else live = live | INJECT_BIT end
            end
            if exp and live ~= (exp[tag] & controlled[tag]) then
                violations = violations + 1
                if not first_violation then
                    first_violation = string.format(
                        "INPUT-VIOLATION %d %s live %04x expected %04x",
                        frame, tag, live, exp[tag] & controlled[tag])
                    f:write(first_violation .. "\n")
                end
            end
        end
    end

    if frame >= total_frames then
        if violations > 0 then
            f:write(string.format("INPUT-VIOLATIONS %d\n", violations))
        end
        f:write(string.format("END %d\n", frame))
        f:close()
        machine:exit()
    end
end)
