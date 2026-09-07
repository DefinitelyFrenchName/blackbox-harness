-- read_tap.lua — PC-attributed READ (+WRITE) tap on RAM addresses,
-- NON-DEBUG so frame counting stays replay-exact. Modeled on tap_writes.lua:
-- same replay/POKES playback, install_read_tap/install_write_tap with the
-- re-install notifier + recursion guard.
--
-- WHY IT EXISTS: a value read mid-frame by a dispatcher can be one that no
-- frame_done sample and no cross-run write log explains, because the value
-- is state-dependent and every run allocates it differently — never
-- correlate a state-dependent value across runs; serialize read+write in
-- ONE run, which is exactly what this script does.
--
-- SCOPE LIMIT: RAM data reads only. A read tap on ROM/opcode fetches is
-- SILENTLY BLIND (cached direct pointers); do not point this at ROM and read
-- the silence as deadness.
--
--   env BBH_PROFILE  the machine profile (required)
--   env RTAP     "hexaddr,declen"  (word-aligned start, decimal length)
--   env WINDOW   "lo,hi" frame gate for READ logging (writes always log —
--                the boot-time writes are the liveness control)
--   env REPLAY / POKES / FRAMES / TRACE_OUT as tap_writes.lua
-- Logs: R <frame> PC <pc> off <addr> data <val> mask <m>
--       W <frame> PC <pc> off <addr> data <val> mask <m>
-- END line + PCHIST for liveness assertion (a log without boot-time W lines
-- at any RAM address is a dead instrument, full stop).

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$"))
    or (os.getenv("BBH_HOME") and (os.getenv("BBH_HOME") .. "/lua/mame")) or "."
local profile = dofile(HERE .. "/profile.lua")
local rpl = dofile(HERE .. "/rpl_parse.lua")
local P = profile.load()

local out_path   = os.getenv("TRACE_OUT") or "read_tap.txt"
local max_frames = tonumber(os.getenv("FRAMES") or "") or 3600   -- as the other taps (the lineage's 5450 was one replay's length)
local wa, wb = (os.getenv("WINDOW") or "0,99999999"):match("^(%d+),(%d+)$")
wa, wb = tonumber(wa), tonumber(wb)
local spec = assert(os.getenv("RTAP"), "set RTAP=hexaddr,declen")
local a_s, l_s = spec:match("^(%x+),(%d+)$")
local base, len = tonumber(a_s, 16), tonumber(l_s)
local PC_MASK = (P.crash and P.crash.pc_mask) or 0xFFFFFF
local PCFMT = "%0" .. #string.format("%x", PC_MASK) .. "x"

local machine = manager.machine
local cpu     = machine.devices[P.cpu]
assert(cpu, "no CPU device " .. P.cpu)
local space   = cpu.spaces[P.space]
local f = assert(io.open(out_path, "wb"))

local frame = 0
local hits, pchist = 0, {}
local tap, wtap
local installing = false
local function install()
    if installing then return end
    installing = true
    tap = space:install_read_tap(base, base + len - 1, "rt", function(offset, data, mask)
        if frame >= wa and frame <= wb then
            hits = hits + 1
            local pc = cpu.state["CURPC"].value & PC_MASK
            pchist[pc] = (pchist[pc] or 0) + 1
            f:write(string.format("R %d PC " .. PCFMT .. " off " .. PCFMT .. " data %08x mask %08x\n",
                    frame, pc, offset, data, mask))
        end
    end)
    -- write tap over the same range, always-on (liveness: boot must hit)
    wtap = space:install_write_tap(base, base + len - 1, "wt", function(offset, data, mask)
        hits = hits + 1
        local pc = cpu.state["CURPC"].value & PC_MASK
        f:write(string.format("W %d PC " .. PCFMT .. " off " .. PCFMT .. " data %08x mask %08x\n",
                frame, pc, offset, data, mask))
    end)
    installing = false
end
install()
space:add_change_notifier(function()
    if tap then tap:remove() end
    if wtap then wtap:remove() end
    install()
end)

-- replay + pokes playback. INPUT STAGING IS CANONICAL: parse `held[fr]`,
-- stage for the NEXT frame (`held[frame + 1]`), exactly as replay.lua.
local held = {}
local FIELDS = nil
local replay_path = os.getenv("REPLAY")
if replay_path then
    FIELDS = profile.bind(P, machine.ioport)
    local held_wt = rpl.parse(replay_path, P.sides)
    held = profile.held_fields(FIELDS, held_wt)
end

local pokes = {}
for spec2 in (os.getenv("POKES") or ""):gmatch("[^;]+") do
    local fr, addr, hexs = spec2:match("^(%d+):(%x+):(%x+)$")
    if fr then pokes[#pokes + 1] = { tonumber(fr), tonumber(addr, 16), hexs } end
end

local pressed = {}
emu.register_frame_done(function()
    frame = frame + 1
    for _, pk in ipairs(pokes) do
        if pk[1] == frame then
            local a = pk[2]
            for b in pk[3]:gmatch("%x%x") do
                space:write_u8(a, tonumber(b, 16)); a = a + 1
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
        local rows = {}
        for pc, n in pairs(pchist) do rows[#rows + 1] = { pc, n } end
        table.sort(rows, function(x, y) return x[2] > y[2] end)
        for _, r in ipairs(rows) do
            f:write(string.format("PCHIST " .. PCFMT .. " %d\n", r[1], r[2]))
        end
        f:close()
        manager.machine:exit()
    end
end)
