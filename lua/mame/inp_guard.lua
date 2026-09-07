-- inp_guard.lua — crash capture for a MAME .inp PLAYBACK, cheap mode (no
-- -debug, so the playback stays faithful to the recording — -debug changes
-- scheduler timeslicing). Lineage: VampireSaved tests/lua/inp_guard.lua,
-- written for the first natural-path capture of a field crash every
-- scripted rig had missed.
--
-- MECHANISM: the machine's own exception handlers begin with a store of
-- their code to a known address (the profile's crash.exception_store) and
-- then soft-restart. A WRITE TAP on that address fires synchronously on the
-- store, while the faulting frame is still on the stack and the registers
-- are untouched. So without a debugger we get:
--   CRASH <frame> vec<n> PC <pc6> SP <sp8> ADDR <addr8>|- HANDLER <pc6>
--   REGS <reg>=.. ..
--   STACK <addr> <val>            ROM-plausible longs above SP (max 16)
--   dump crash_<frame>_<lo>.bin (the RAM window, taken at the store)
-- Boot-time RAM tests also write the store: filtered by ARM_FRAME and by
-- the value (codes above crash.store_code_max); filtered writes are
-- counted, not hidden.
--
-- env BBH_PROFILE    the machine profile (required; needs crash.exception_store)
-- env CHECKSUM_OUT   log path (default inp_guard.log)
-- env ARM_FRAME      ignore writes before this frame (default: the profile's crash.arm_frame)
-- env MAX_FRAMES     stop after this many frames (default 200000)
-- env STOP_AFTER     frames to keep running after the first crash (default 600)
-- env SELFTEST_FRAME verdict control: at this frame the script itself writes
--                    1 to the store through the address space; the tap MUST
--                    report it as a (synthetic) CRASH or the detector is dead.
-- env TRACE_FROM     (needs -debug -debugger none): start an instruction
--                    trace at this frame, stop at the first crash. -debug
--                    perturbs timeslicing — confirm the crash frame matches
--                    the cheap-mode capture before trusting the trace.
-- env WATCH          "lo-hi[,lo-hi]" hex RAM ranges: every WRITE is logged
--                    with the writing PC into a ring (last WATCH_KEEP,
--                    default 60), flushed at each crash as "W <frame> PC <pc> <addr> <data>".

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$"))
    or (os.getenv("BBH_HOME") and (os.getenv("BBH_HOME") .. "/lua/mame")) or "."
local profile = dofile(HERE .. "/profile.lua")
local P = profile.load()
local C = profile.require_crash(P)
assert(C.exception_store, "profile " .. P.path .. ": crash.exception_store is required by inp_guard.lua")
local STORE_TO_VEC = C.store_to_vector or 0
local CODE_MAX = C.store_code_max or 0xFFFF

local out_path = os.getenv("CHECKSUM_OUT") or "inp_guard.log"
local arm = tonumber(os.getenv("ARM_FRAME") or "") or C.arm_frame or 0
local max_frames = tonumber(os.getenv("MAX_FRAMES") or "") or 200000
local stop_after = tonumber(os.getenv("STOP_AFTER") or "") or 600
local selftest = tonumber(os.getenv("SELFTEST_FRAME") or "")
local trace_from = tonumber(os.getenv("TRACE_FROM") or "")
local watch_keep = tonumber(os.getenv("WATCH_KEEP") or "") or 60
local ring, ring_n = {}, 0
local trace_path = os.getenv("TRACE_OUT") or "inp_guard.trace"
local debugger = manager.machine.debugger
local tracing = false

local cpu = manager.machine.devices[P.cpu]
assert(cpu, "no CPU device " .. P.cpu)
local program = cpu.spaces[P.space]
local RAM_LO, RAM_HI = P.ram.lo, P.ram.hi
local PC_MASK = C.pc_mask
local f = assert(io.open(out_path, "wb"))
local frame, crashes, filtered, stop_at = 0, 0, 0, nil

local function sp_of(st)
    for _, n in ipairs(C.sp) do
        local ok, v = pcall(function() return st[n].value end)
        if ok and v then return v end
    end
    error("no stack-pointer register among " .. table.concat(C.sp, "/"), 0)
end

local function rom_plausible(v)
    return v >= C.code.lo and v < C.code.hi and v % 2 == 0
end

local function read_width(addr, width)
    if width == 4 then return program:read_u32(addr)
    elseif width == 2 then return program:read_u16(addr)
    else return program:read_u8(addr) end
end

local function on_store(code)
    local st = cpu.state
    local sp = sp_of(st)
    local vec = code + STORE_TO_VEC
    local fault_pc, fault_addr
    if C.group0[vec] then
        fault_addr = program:read_u32(sp + C.addr_at_sp)
        fault_pc = program:read_u32(sp + C.pc_at_sp.group0)
    else
        fault_pc = program:read_u32(sp + C.pc_at_sp.other)
    end
    local okpc, curpc = pcall(function() return st["CURPC"].value & PC_MASK end)
    f:write(string.format("CRASH %d vec%d PC %06x SP %08x ADDR %s HANDLER %s\n",
        frame, vec, fault_pc & PC_MASK, sp,
        fault_addr and string.format("%08x", fault_addr) or "-",
        okpc and string.format("%06x", curpc) or "?"))
    local regs = {}
    for _, rn in ipairs(C.regs) do
        local ok, v = pcall(function() return st[rn].value end)
        regs[#regs + 1] = string.format("%s=%08x", rn, ok and v or 0)
    end
    f:write("REGS " .. table.concat(regs, " ") .. "\n")
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
    if ring_n > 0 then
        local first = math.max(1, ring_n - watch_keep + 1)
        for i = first, ring_n do f:write(ring[i]) end
    end
    local dn = string.format("crash_%d_%06x.bin", frame, RAM_LO)
    local d = assert(io.open(dn, "wb"))
    d:write(program:read_range(RAM_LO, RAM_HI, 8)); d:close()
    f:write(string.format("DUMP %d %s\n", frame, dn))
    if tracing then
        debugger:command("trace off"); tracing = false
        f:write(string.format("TRACE %d off -> %s\n", frame, trace_path))
    end
    f:flush()
    crashes = crashes + 1
    if not stop_at then stop_at = frame + stop_after end
end

-- tap + re-install notifier (the read_tap.lua pattern: a memory-map change
-- drops taps silently; without the notifier a capture goes blind).
local tap
local function on_write(offset, data, mask)
    -- a .w store arrives as one 16-bit access; the code is small
    local code = data & 0xFFFF
    -- a soft-reset path's abbreviated RAM test also writes small values here
    -- with SP outside the RAM window (the lineage measured SP=0); a real
    -- handler store has the exception frame on the RAM stack.
    local sp = sp_of(cpu.state)
    if frame < arm or code > CODE_MAX or sp < RAM_LO or sp > RAM_HI then
        filtered = filtered + 1
        return
    end
    on_store(code)
end
local wtaps = {}
local function install()
    tap = program:install_write_tap(C.exception_store, C.exception_store + 1, "inp_guard", on_write)
    for lo, hi in (os.getenv("WATCH") or ""):gmatch("(%x+)%-(%x+)") do
        lo, hi = tonumber(lo, 16), tonumber(hi, 16)
        wtaps[#wtaps + 1] = program:install_write_tap(lo, hi, "inp_watch_" .. lo, function(offset, data, mask)
            local ok, pc = pcall(function() return cpu.state["CURPC"].value & PC_MASK end)
            ring_n = ring_n + 1
            ring[ring_n] = string.format("W %d PC %06x %06x %08x mask %08x\n", frame, ok and pc or 0, offset, data, mask)
            if ring_n > watch_keep * 2 then
                local keep = {}
                for i = ring_n - watch_keep + 1, ring_n do keep[#keep + 1] = ring[i] end
                ring, ring_n = keep, #keep
            end
        end)
    end
end
install()
program:add_change_notifier(function()
    if tap then tap:remove() end
    for _, t in ipairs(wtaps) do t:remove() end
    wtaps = {}
    install()
end)

local ALIVE = C.alive or {}
emu.register_frame_done(function()
    frame = frame + 1
    if selftest and frame == selftest then
        f:write(string.format("SELFTEST %d writing 1 to $%06X.w\n", frame, C.exception_store))
        program:write_u16(C.exception_store, 1)
    end
    if trace_from and debugger and frame == trace_from then
        debugger:command("trace " .. trace_path .. ",0")
        tracing = true
        f:write(string.format("TRACE %d on -> %s\n", frame, trace_path))
    end
    if frame % 600 == 0 then
        local parts = { string.format("ALIVE %d", frame) }
        for _, a in ipairs(ALIVE) do
            parts[#parts + 1] = string.format("%s=%0" .. (a[3] * 2) .. "x", a[1], read_width(a[2], a[3]))
        end
        f:write(table.concat(parts, " ") .. "\n")
        f:flush()
    end
    if (stop_at and frame >= stop_at) or frame >= max_frames then
        f:write(string.format("END %d crashes=%d filtered_writes=%d\n", frame, crashes, filtered))
        f:close()
        manager.machine:exit()
    end
end)
