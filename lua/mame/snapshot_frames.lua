-- snapshot_frames.lua — play a replay and save snapshots at named frames.
--
-- WHY: every RAM gate is structurally blind to rendering. MAME renders its
-- bitmap internally even under `-video none` + SDL_VIDEODRIVER=dummy, so
-- `manager.machine.video:snapshot()` produces a real frame headlessly. This
-- turns "look at it" into a scripted, rerunnable measurement.
--
-- The snapshot goes to the emulator's snapshot directory (drivers/mame.sh
-- points it at <sandbox>/snap/<set>/NNNN.png). Numbering is MAME's own
-- (0000, 0001, ...) in the order taken, so SNAP_FRAMES order IS the file
-- order; the mapping is also written to TRACE_OUT.
--
--   env BBH_PROFILE  the machine profile (required)
--   env REPLAY       optional input script (the .rpl grammar)
--   env SNAP_FRAMES  comma-separated frame numbers to capture
--   env TRACE_OUT    index log path (default snapshot_frames.txt)
--   env FRAMES       hard stop (default max(SNAP_FRAMES))
--   env POKES        "frame:addr:hexbytes;..." scheduled RAM writes
--
-- Ends with a SNAPSUMMARY line for scripted assertion.
-- INPUT STAGING IS CANONICAL: parse `held[fr]`, stage for the NEXT frame
-- (`held[frame + 1]`), exactly as replay.lua — so a frame number in this
-- log IS a replay.lua frame number and can be cross-referenced with a
-- checksum log. (Lineage: VampireSaved tests/lua/snapshot_frames.lua; its
-- lenient private parser is replaced by rpl_parse.lua, so a malformed
-- replay now fails loudly instead of playing a subset.)

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$"))
    or (os.getenv("BBH_HOME") and (os.getenv("BBH_HOME") .. "/lua/mame")) or "."
local profile = dofile(HERE .. "/profile.lua")
local rpl = dofile(HERE .. "/rpl_parse.lua")
local P = profile.load()

local out_path = os.getenv("TRACE_OUT") or "snapshot_frames.txt"
local want = {}
local want_list = {}
for tok in (os.getenv("SNAP_FRAMES") or ""):gmatch("[^,%s]+") do
    local n = tonumber(tok)
    if n then want[n] = true; want_list[#want_list + 1] = n end
end
assert(#want_list > 0, "SNAP_FRAMES must name at least one frame")
table.sort(want_list)
local max_frames = tonumber(os.getenv("FRAMES") or "") or want_list[#want_list]

local machine = manager.machine
local f = assert(io.open(out_path, "wb"))

-- input playback
local held = {}
local replay_path = os.getenv("REPLAY")
if replay_path then
    local F = profile.bind(P, machine.ioport)
    local held_wt = rpl.parse(replay_path, P.sides)
    held = profile.held_fields(F, held_wt)
end

local frame = 0
local taken = 0
local prev = {}

-- POKES: same grammar and application point as replay.lua
local cpu = machine.devices[P.cpu]
assert(cpu, "no CPU device " .. P.cpu)
local program = cpu.spaces[P.space]
local pokes = {}
for spec in (os.getenv("POKES") or ""):gmatch("[^;]+") do
    local fr, addr, hexs = spec:match("^(%d+):(%x+):(%x+)$")
    if fr then pokes[#pokes + 1] = { tonumber(fr), tonumber(addr, 16), hexs } end
end

emu.register_frame_done(function()
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
    for _, fo in ipairs(prev) do fo:set_value(0) end
    prev = held[frame + 1] or {}
    for _, fo in ipairs(prev) do fo:set_value(1) end

    if want[frame] then
        machine.video:snapshot()
        f:write(string.format("SNAP %04d frame %d\n", taken, frame))
        taken = taken + 1
    end

    if frame >= max_frames then
        f:write(string.format("SNAPSUMMARY frames=%d taken=%d wanted=%d\n",
            frame, taken, #want_list))
        f:close()
        machine:exit()
    end
end)
