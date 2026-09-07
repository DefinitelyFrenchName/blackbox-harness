-- replay.lua — scripted-input replay runner with per-frame RAM checksums:
-- the oracle-harness core. Identical inputs must yield identical checksum
-- logs across runs, builds and implementations.
--
-- Lineage: VampireSaved tests/lua/replay.lua, every literal about the board
-- moved into the MACHINE PROFILE (profile.lua, BBH_PROFILE) and the replay
-- grammar into rpl_parse.lua. The log is byte-identical to the lineage's on
-- the cps2 profile — fidelity F8 (`cmp`) is the proof.
--
-- Usage: mame <set> -autoboot_script lua/mame/replay.lua ...  (drivers/mame.sh)
--   env BBH_PROFILE   the machine profile (required)
--   env REPLAY        input script path (required)
--   env CHECKSUM_OUT  checksum log path (default replay_checksums.txt)
--   env TAIL_FRAMES   frames to keep running after last scripted input (default 120)
--   env SNAP_FRAMES   optional "300,600,900": save a snapshot at those frames
--                     (to the emulator's snapshot dir) — for replay authoring
--   env DUMPS         optional "2900:ff8000-ff8700;3000:ff9400-ff9500":
--                     at end of frame N, dump the RAM range to
--                     <dir of CHECKSUM_OUT>/dump_<frame>_<start>.bin
--   env POKES         optional "frame:addr:hexbytes;...": scheduled RAM writes,
--                     applied at the start of the frame
--   env INPUT_OUT     optional path: per-frame raw input-port values
--                     ("<frame> <port> <port> ..." over profile.ports). Proves
--                     whether a divergence was caused by HOST input leaking
--                     into the emulated controls; the driver disables every
--                     host input provider — this is the detector for when
--                     something slips past that.
--   env VIDEO_OUT     optional path: per-frame FRAMEBUFFER checksum log,
--                     same grammar, written to a SEPARATE file so no frozen
--                     RAM expectation moves. A RAM-only gate is structurally
--                     blind to the entire video path (the lineage's 19-bit
--                     tile-address change produced byte-identical RAM logs
--                     whether it worked or drew garbage).
--   env MASK_RANGES   optional "7f00-7ff0" (offsets from profile.ram.lo, end
--                     exclusive): exclude window(s) from the checksum.
--                     Unset = canonical whole-window checksum. A mask is a
--                     BASIS: a log under one mask is never comparable to a
--                     log under another.
--   env NO_INPUT_CHECK      disables the input-integrity assertion (analysis only)
--   env INPUT_INJECT_TEST   <frame>: the assertion's must-fire control
--
-- Log format: "<frame> <fnv1a64>" per frame, "INPUT-VIOLATION <n> <detail>"
-- if the assertion fired, then "END <n>".

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$"))
    or (os.getenv("BBH_HOME") and (os.getenv("BBH_HOME") .. "/lua/mame")) or "."
local profile = dofile(HERE .. "/profile.lua")
local rpl = dofile(HERE .. "/rpl_parse.lua")
local P = profile.load()

local replay_path = assert(os.getenv("REPLAY"), "set REPLAY to the input script path")
local out_path = os.getenv("CHECKSUM_OUT") or "replay_checksums.txt"
local tail_frames = tonumber(os.getenv("TAIL_FRAMES") or "") or 120

-- ── field lookup ─────────────────────────────────────────────────────────────

local ioport = manager.machine.ioport
local F = profile.bind(P, ioport)
local FIELDS, FIELD_INFO = F.fields, F.info

-- ── parse replay ─────────────────────────────────────────────────────────────

-- held[frame] = { field, field, ... } (list may contain duplicates; harmless)
local held_wt, last_frame = rpl.parse(replay_path, P.sides)
local held = profile.held_fields(F, held_wt)

local total_frames = last_frame + tail_frames

local snap_at = {}
for n in (os.getenv("SNAP_FRAMES") or ""):gmatch("%d+") do
    local fr = tonumber(n)
    snap_at[fr] = true
    if fr + 1 > total_frames then total_frames = fr + 1 end
end

local dump_at = {}  -- frame -> { {first, last}, ... }
local out_dir = out_path:match("^(.*)/[^/]+$") or "."
for spec in (os.getenv("DUMPS") or ""):gmatch("[^;]+") do
    local fr, first, last = spec:match("^(%d+):(%x+)%-(%x+)$")
    assert(fr, "bad DUMPS spec: " .. spec)
    fr = tonumber(fr)
    dump_at[fr] = dump_at[fr] or {}
    table.insert(dump_at[fr], { tonumber(first, 16), tonumber(last, 16) })
    if fr + 1 > total_frames then total_frames = fr + 1 end
end

-- ── per-frame drive ──────────────────────────────────────────────────────────

local cpu = manager.machine.devices[P.cpu]
assert(cpu, "no CPU device " .. P.cpu .. " (profile " .. P.path .. ")")
local program = cpu.spaces[P.space]
assert(program, "no address space " .. P.space .. " on " .. P.cpu)
local RAM_LO, RAM_HI, RAM_SIZE = P.ram.lo, P.ram.hi, profile.ram_size(P)

-- POKES="frame:addr:hexbytes;..." — scheduled RAM writes
local pokes = {}
for spec in (os.getenv("POKES") or ""):gmatch("[^;]+") do
    local fr, addr, hexs = spec:match("^(%d+):(%x+):(%x+)$")
    if fr then pokes[#pokes + 1] = { tonumber(fr), tonumber(addr, 16), hexs } end
end
local f = assert(io.open(out_path, "wb"))
local frame = 0

-- MASK_RANGES (opt-in): exclude windows (offsets from ram.lo, end exclusive)
-- from the checksum. Default (unset) is the canonical whole-window checksum.
local mask_ranges = {}
local mask_spec = os.getenv("MASK_RANGES") or ""
for a, b in mask_spec:gmatch("(%x+)%-(%x+)") do
    local lo, hi = tonumber(a, 16), tonumber(b, 16)
    -- VALIDATE, do not just parse (the lineage's GitHub #61). The mask string
    -- IS the definition of a ratified comparison basis, so a malformed one
    -- makes every expectation citing it meaningless.
    if lo > hi then
        error(string.format("MASK_RANGES: %04x-%04x is inverted", lo, hi), 0)
    end
    if hi > RAM_SIZE then
        error(string.format("MASK_RANGES: %04x-%04x runs past work RAM "
                            .. "(offsets from $%06X, end EXCLUSIVE)", lo, hi, RAM_LO), 0)
    end
    mask_ranges[#mask_ranges + 1] = { lo, hi }
end
-- A non-empty spec that parsed to nothing is a typo, not "no mask": it would
-- silently produce a whole-window checksum under a name that promises a
-- masked one.
if mask_spec:match("%S") and #mask_ranges == 0 then
    error("MASK_RANGES is set but parsed to no ranges: " .. mask_spec, 0)
end
table.sort(mask_ranges, function(x, y) return x[1] < y[1] end)

local function read_workram_masked()
    if #mask_ranges == 0 then
        return program:read_range(RAM_LO, RAM_HI, 8)
    end
    local parts, pos = {}, 0x0000
    for _, r in ipairs(mask_ranges) do
        if r[1] > pos then
            parts[#parts + 1] = program:read_range(RAM_LO + pos, RAM_LO + r[1] - 1, 8)
        end
        -- NEVER MOVE POS BACKWARDS (the lineage's #61). Ranges are sorted by
        -- START, so a NESTED or overlapping window can have a smaller end
        -- than the one before it — e.g. 1000-2000 then 1500-1800. A bare
        -- `pos = r[2]` rewinds to 0x1800 and the tail read then re-includes
        -- 0x1800-0x2000, silently UNMASKING bytes the spec asked to exclude.
        if r[2] > pos then pos = r[2] end
    end
    if pos <= RAM_SIZE - 1 then
        parts[#parts + 1] = program:read_range(RAM_LO + pos, RAM_HI, 8)
    end
    return table.concat(parts)
end

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

-- INPUT_OUT: per-frame raw input-port values, written alongside (never into)
-- the RAM log. Defence in depth against the ONE failure mode that can
-- corrupt a replay without corrupting the emulator: host input reaching the
-- emulated controls. On any divergence, diff the input logs first: if they
-- differ, the cause is external input and the investigation is over.
local PORT_TAGS = P.ports
local PORTFMT = "%0" .. (P.port_hex_digits or 4) .. "x"
local input_out = os.getenv("INPUT_OUT")
local inf, in_ports
if input_out then
    inf = assert(io.open(input_out, "wb"))
    in_ports = {}
    for _, tag in ipairs(PORT_TAGS) do
        in_ports[#in_ports + 1] = assert(ioport.ports[tag], "no port " .. tag)
    end
end

-- ── INPUT INTEGRITY ASSERTION (always on, no env flag) ──────────────────
-- The log above is evidence after the fact; this is the guard. The harness
-- knows exactly which fields it staged for each frame, so it can verify
-- that the live ports contain THAT AND NOTHING ELSE. Any extra bit means an
-- input arrived from outside the script and the run is no longer a replay
-- of anything. Deliberately not opt-in: the failure it catches is silent
-- and produces a plausible-looking log.
local inject_frame = tonumber(os.getenv("INPUT_INJECT_TEST") or "")
local INTEGRITY = os.getenv("NO_INPUT_CHECK") == nil
local integ_ports, baseline, controlled = {}, {}, {}
local violations, first_violation = 0, nil
if INTEGRITY then
    for _, tag in ipairs(PORT_TAGS) do
        integ_ports[tag] = assert(ioport.ports[tag], "no port " .. tag)
        controlled[tag] = 0
    end
    -- Compare ONLY the bits this harness can drive: a port may carry lines
    -- that legitimately toggle (the lineage's EEPROM data line flagged every
    -- replay at frame 77 before this mask). Host keystrokes land on
    -- controller bits, so masking to them loses no detection power.
    for _, group in pairs(FIELDS) do
        for _, field in pairs(group) do
            local info = FIELD_INFO[field]
            controlled[info[1]] = controlled[info[1]] | info[2]
        end
    end
end

-- The idle value of the controlled bits is a KNOWN CONSTANT of the board
-- (active-low: all ones), asserted on frame 1 rather than adopted from the
-- live ports — a host key held from before frame 1 through the whole run
-- would otherwise read as baseline and match on every later frame (the
-- lineage's #57: the one input pattern with no divergence signature).
local function idle_of(tag)
    return P.active_low and controlled[tag] or 0
end

-- Expected port values for a given frame's held set: start from the idle
-- baseline and press each held field's mask. Returns nil until the baseline
-- has been captured on frame 1.
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

-- VIDEO_OUT: per-frame framebuffer checksum, written alongside (never into)
-- the RAM log. Same FNV-1a64 and same "<frame> <hash>" line format.
local video_out = os.getenv("VIDEO_OUT")
local vf, video_screen
if video_out then
    vf = assert(io.open(video_out, "wb"))
    assert(P.screen, "VIDEO_OUT needs profile.screen")
    video_screen = assert(manager.machine.screens[P.screen], "no " .. P.screen .. " device")
end

-- every field we might touch, for release bookkeeping
local all_fields = F.all
local pressed = {}  -- field -> true while held
local inject_field = P.inject and FIELDS[P.inject[1]] and FIELDS[P.inject[1]][P.inject[2]]
if inject_frame then
    assert(inject_field, "INPUT_INJECT_TEST needs profile.inject = { side, token }")
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

    -- checksum first: state at END of frame N
    f:write(string.format("%d %016x\n", frame, fnv1a64(read_workram_masked())))
    if vf then
        vf:write(string.format("%d %016x\n", frame, fnv1a64(video_screen:pixels())))
    end
    if inf then
        local vals = { tostring(frame) }
        for _, p in ipairs(in_ports) do vals[#vals + 1] = string.format(PORTFMT, p:read()) end
        inf:write(table.concat(vals, " ") .. "\n")
    end
    if INTEGRITY then
        -- The set in effect DURING this frame is the one staged at the end
        -- of the previous frame, i.e. held[frame]. (held[1] is never staged
        -- — nothing runs before frame 1 — so frame 1 is always idle and is
        -- where the baseline is asserted.)
        if frame == 1 then
            for _, tag in ipairs(PORT_TAGS) do
                local got = integ_ports[tag]:read() & controlled[tag]
                local idle = idle_of(tag)
                if got ~= idle then
                    violations = violations + 1
                    first_violation = first_violation or string.format(
                        "frame 1 port %s: controlled bits " .. PORTFMT .. " are already %s "..
                        "(= HELD before the replay started; stuck host key or "..
                        "modifier?) read " .. PORTFMT .. ", idle " .. PORTFMT,
                        tag, (got ~ idle) & controlled[tag],
                        P.active_low and "LOW" or "HIGH", got, idle)
                end
                baseline[tag] = idle
            end
        else
            local exp = expected_ports(held[frame])
            for _, tag in ipairs(PORT_TAGS) do
                local got = integ_ports[tag]:read() & controlled[tag]
                if exp[tag] ~= got then
                    violations = violations + 1
                    first_violation = first_violation or
                        string.format("frame %d port %s expected " .. PORTFMT .. " got " .. PORTFMT .. " (mask " .. PORTFMT .. ")",
                                      frame, tag, exp[tag], got, controlled[tag])
                end
            end
        end
    end
    if snap_at[frame] then manager.machine.video:snapshot() end
    for _, range in ipairs(dump_at[frame] or {}) do
        local df = assert(io.open(string.format("%s/dump_%d_%06x.bin", out_dir, frame, range[1]), "wb"))
        df:write(program:read_range(range[1], range[2], 8))
        df:close()
    end

    -- then stage inputs that should be held DURING frame N+1
    local want = {}
    for _, field in ipairs(held[frame + 1] or {}) do want[field] = true end
    for _, field in ipairs(all_fields) do
        if want[field] and not pressed[field] then
            field:set_value(1); pressed[field] = true
        elseif not want[field] and pressed[field] then
            field:clear_value(); pressed[field] = nil
        end
    end

    -- TEST-ONLY positive control (INPUT_INJECT_TEST=<frame>): simulate a
    -- stray HOST keypress by pressing a field that held[] does not record,
    -- for exactly one frame. The integrity check above must then fire at
    -- that frame. A check that has only ever been silent is not evidence of
    -- anything.
    if inject_frame and (frame + 1) == inject_frame then
        inject_field:set_value(1)
        pressed[inject_field] = true   -- so the next frame's staging releases it
    end

    if frame >= total_frames then
        -- A violation means inputs reached the machine from outside the
        -- script, so this log is not a replay of anything. Say so IN the
        -- log, before END, where every consumer will trip over it rather
        -- than silently comparing a corrupt run.
        if violations > 0 then
            f:write(string.format("INPUT-VIOLATION %d %s\n", violations, first_violation))
        end
        f:write(string.format("END %d\n", frame))
        f:close()
        if vf then vf:write(string.format("END %d\n", frame)); vf:close() end
        if inf then inf:write(string.format("END %d\n", frame)); inf:close() end
        manager.machine:exit()
    end
end)
