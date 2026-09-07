-- tap_writes.lua — log writes hitting a RAM range via a memory tap (no
-- debugger: frame counting stays replay-exact, unlike trace_writes.lua —
-- debugger stops desync a replay). The tool for "who writes this field
-- DURING these frames?" on hot fields written every frame, where
-- watchpoint stops would melt the replay.
--
--   env BBH_PROFILE  the machine profile (required)
--   env REPLAY     optional input script (the .rpl grammar)
--   env TAP        "ff8810,8" (hexstart,declen) — write tap over the range
--   env WINDOW     "3040,3110" — only log hits inside this frame window
--                  (tap installed the whole run; logging gated)
--   env TRACE_OUT  log path (default tap_writes.txt)
--   env FRAMES     stop after this many frames (default 3600)
--   env POKES      "frame:addr:hexbytes;..." scheduled RAM writes
--   env REGLOG     =1: append the register set to every hit (names the
--                  source table pointers for computed cursors)
--   env STACKLOG   =1: append the five longs at the top of the stack
--                  (caller attribution for engine-internal writer PCs)
--   env COLLECT    "lo,hi" hex: COLLECT mode — instead of per-write lines,
--                  accumulate the SET of values written in-window at entry
--                  offsets where (offset % stride) == offset — the profile's
--                  `collect` record layout, env COLLECT_STRIDE / COLLECT_OFFSET /
--                  COLLECT_WIDTH overriding — whose value falls in [lo,hi];
--                  dumped as CODE lines at END,
--                  bucketed "vanilla" / "ported" by COLLECT_PORTED
--                  ("lo-hi,lo-hi" hex PC ranges; the lineage's patch holes).
--
-- Each hit logs: frame, PC (CURPC at tap time = the writing instruction),
-- tap offset, data word, mask. PCs aggregate at END as a histogram.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$"))
    or (os.getenv("BBH_HOME") and (os.getenv("BBH_HOME") .. "/lua/mame")) or "."
local profile = dofile(HERE .. "/profile.lua")
local rpl = dofile(HERE .. "/rpl_parse.lua")
local P = profile.load()

local tap_spec = assert(os.getenv("TAP"), "set TAP=start,len")
local out_path = os.getenv("TRACE_OUT") or "tap_writes.txt"
local max_frames = tonumber(os.getenv("FRAMES") or "") or 3600
local wa, wb = (os.getenv("WINDOW") or "0,99999999"):match("^(%d+),(%d+)$")
wa, wb = tonumber(wa), tonumber(wb)

local machine = manager.machine
local cpu = machine.devices[P.cpu]
assert(cpu, "no CPU device " .. P.cpu)
local space = cpu.spaces[P.space]

local f = assert(io.open(out_path, "wb"))
local frame = 0
local hits = 0
local by_pc = {}
local collect_lo, collect_hi
do
    local c = os.getenv("COLLECT")
    if c then
        local a, b = c:match("^(%x+),(%x+)$")
        collect_lo, collect_hi = tonumber(a, 16), tonumber(b, 16)
    end
end
local CL = P.collect or {}
local COLLECT_STRIDE = tonumber(os.getenv("COLLECT_STRIDE") or "") or CL.stride or 8
local COLLECT_OFFSET = tonumber(os.getenv("COLLECT_OFFSET") or "") or CL.offset or 4
local COLLECT_WIDTH = tonumber(os.getenv("COLLECT_WIDTH") or "") or CL.width or 2
local COLLECT_MASK = (1 << (8 * COLLECT_WIDTH)) - 1
local PCFMT = "%0" .. #string.format("%x", (P.crash and P.crash.pc_mask) or 0xFFFFFF) .. "x"
local ported_ranges = {}
for a, b in (os.getenv("COLLECT_PORTED") or ""):gmatch("(%x+)%-(%x+)") do
    ported_ranges[#ported_ranges + 1] = { tonumber(a, 16), tonumber(b, 16) }
end
local function is_ported(pc)
    for _, r in ipairs(ported_ranges) do
        if pc >= r[1] and pc < r[2] then return true end
    end
    return false
end
local collected = {}

-- input playback
local held = {}
local FIELDS = nil
local replay_path = os.getenv("REPLAY")
if replay_path then
    FIELDS = profile.bind(P, machine.ioport)
    local held_wt = rpl.parse(replay_path, P.sides)
    held = profile.held_fields(FIELDS, held_wt)
end

local start_addr, len = tap_spec:match("^(%x+),(%d+)$")
assert(start_addr, "TAP format: hexaddr,len")
start_addr = tonumber(start_addr, 16)

local REG_NAMES = (P.crash and P.crash.tap_regs)
    or { "D0", "D1", "D2", "D3", "A0", "A1", "A2", "A3", "A4", "A6" }
local SP_NAMES = (P.crash and P.crash.sp) or { "SP", "A7" }

-- GOTCHA (paid for in the lineage): a passthrough tap is silently dropped
-- whenever anything re-installs handlers in the space (CPS-2 does this right
-- after boot) — without the change notifier the tap logs boot writes only
-- and reads as "nobody writes this field". Re-install on every space change.
local tap
local installing = false
local function install_tap()
    installing = true
    tap = space:install_write_tap(start_addr, start_addr + tonumber(len) - 1,
        "tapw", function(offset, data, mask)
            if collect_lo then
                if frame >= wa and frame <= wb and offset % COLLECT_STRIDE == COLLECT_OFFSET then
                    local v = data & COLLECT_MASK
                    if mask & COLLECT_MASK == 0 then v = (data >> (8 * COLLECT_WIDTH)) & COLLECT_MASK end
                    if v >= collect_lo and v <= collect_hi then
                        local pc = cpu.state["CURPC"].value
                        local key = v + (is_ported(pc) and (COLLECT_MASK + 1) or 0)
                        collected[key] = (collected[key] or 0) + 1
                    end
                end
                hits = hits + 1
                return
            end
            if frame >= wa and frame <= wb then
                local pc = cpu.state["CURPC"].value
                hits = hits + 1
                by_pc[pc] = (by_pc[pc] or 0) + 1
                local extra = ""
                if os.getenv("REGLOG") then
                    local ok, res = pcall(function()
                        local st = cpu.state
                        local r = {}
                        for _, n in ipairs(REG_NAMES) do
                            r[#r + 1] = n .. "=" .. string.format("%08x", st[n].value)
                        end
                        return " " .. table.concat(r, " ")
                    end)
                    extra = ok and res or (" regerr")
                end
                if os.getenv("STACKLOG") then
                    local ok, res = pcall(function()
                        local st = cpu.state
                        local spr
                        for _, n in ipairs(SP_NAMES) do spr = spr or st[n] end
                        local sp = spr.value
                        local r = {}
                        for k = 0, 4 do
                            r[#r + 1] = string.format("%08x", space:read_u32(sp + k * 4))
                        end
                        return " stack " .. table.concat(r, " ")
                    end)
                    extra = ok and res or (" stackerr " .. tostring(res))
                end
                f:write(string.format("frame %d PC " .. PCFMT .. " off " .. PCFMT .. " data %08x mask %08x%s\n",
                                      frame, pc, offset, data, mask, extra))
            end
        end)
    installing = false
end
install_tap()
local notifier = space:add_change_notifier(function(mode)
    if not installing and mode:find("w") then install_tap() end
end)

-- POKES="frame:addr:hexbytes;..." — write bytes at the given frame
local pokes = {}
for spec in (os.getenv("POKES") or ""):gmatch("[^;]+") do
    local fr, addr, hexs = spec:match("^(%d+):(%x+):(%x+)$")
    if fr then pokes[#pokes + 1] = { tonumber(fr), tonumber(addr, 16), hexs } end
end

local pressed = {}
emu.register_frame_done(function()
    frame = frame + 1
    for _, pk in ipairs(pokes) do
        if pk[1] == frame then
            local a = pk[2]
            for b in pk[3]:gmatch("%x%x") do
                space:write_u8(a, tonumber(b, 16))
                a = a + 1
            end
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
        if collect_lo then
            local ks = {}
            for v in pairs(collected) do ks[#ks + 1] = v end
            table.sort(ks)
            for _, v in ipairs(ks) do
                f:write(string.format("CODE %0" .. (COLLECT_WIDTH * 2) .. "x %s %d\n", v & COLLECT_MASK,
                        (v > COLLECT_MASK) and "ported" or "vanilla", collected[v]))
            end
        end
        local pcs = {}
        for pc, n in pairs(by_pc) do pcs[#pcs + 1] = { pc, n } end
        table.sort(pcs, function(x, y) return x[2] > y[2] end)
        for _, e in ipairs(pcs) do
            f:write(string.format("PCHIST " .. PCFMT .. " %d\n", e[1], e[2]))
        end
        f:close()
        manager.machine:exit()
    end
end)
