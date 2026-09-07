-- profile.lua — the MACHINE PROFILE loader: one Lua table per board, named
-- by BBH_PROFILE, validated here so a script never runs on a profile missing
-- a key it reads (it would fail later, on a nil index, with a message that
-- names nothing).
--
-- Every literal the lineage's replay.lua / replay_guard.lua / inp_guard.lua
-- carried about CPS-2 — the CPU tag, the address space, the screen, the RAM
-- window, the three port tags and 22 field names, the `sys` token width,
-- the exception vectors, the group-0 stack layout, the exception store, the
-- match flag — is a key of the profile. profiles/TEMPLATE.lua carries every
-- key with a comment; profiles/cps2.lua is the first real one, proved by
-- fidelity F8 (the lineage's driver and the harness's produce the same log),
-- not by inspection.
--
--   local profile = dofile(HERE .. "/profile.lua")
--   local P = profile.load()                -- from BBH_PROFILE
--   local P = profile.load("/path/to/x.lua")
--   profile.require_crash(P)                -- the guard scripts' keys
--   local F = profile.bind(P, ioport)       -- F.fields[who][tok], F.info[field] = {port, mask}, F.all
--   profile.ram_size(P)

local M = {}

M.REQUIRED = { "name", "cpu", "space", "ram", "sides", "ports" }
M.REQUIRED_CRASH = { "vectors", "vector_stride", "group0", "pc_at_sp", "addr_at_sp",
                     "code", "stack_top", "pc_mask", "regs", "sp" }

local function fail(path, msg)
    error("profile " .. tostring(path) .. ": " .. msg, 0)
end

function M.load(path)
    path = path or os.getenv("BBH_PROFILE")
    if not path or path == "" then
        error("set BBH_PROFILE to a machine profile (lua/mame/profiles/<board>.lua)", 0)
    end
    local P = dofile(path)
    if type(P) ~= "table" then fail(path, "did not return a table") end
    for _, k in ipairs(M.REQUIRED) do
        if P[k] == nil then fail(path, "missing required key '" .. k .. "'") end
    end
    if type(P.ram) ~= "table" or not P.ram.lo or not P.ram.hi or P.ram.hi < P.ram.lo then
        fail(path, "ram must be { lo = <addr>, hi = <addr> } with hi >= lo")
    end
    for who, side in pairs(P.sides) do
        if type(side) ~= "table" or not side.width or type(side.tokens) ~= "table" then
            fail(path, "sides." .. tostring(who) .. " must be { width = n, tokens = { tok = {port, field}, … } }")
        end
    end
    if type(P.ports) ~= "table" or #P.ports == 0 then
        fail(path, "ports must list the input-port tags in log order")
    end
    if P.active_low == nil then P.active_low = true end
    P.path = path
    return P
end

function M.require_crash(P)
    if type(P.crash) ~= "table" then fail(P.path, "the guard needs a 'crash' table") end
    for _, k in ipairs(M.REQUIRED_CRASH) do
        if P.crash[k] == nil then fail(P.path, "crash." .. k .. " is required by the guard") end
    end
    return P.crash
end

function M.ram_size(P)
    return P.ram.hi - P.ram.lo + 1
end

-- Bind the profile's sides to MAME's ioport fields. Keyed by the exact
-- field object (MAME may hand out a fresh wrapper per lookup, so identity
-- matching against port.fields later would be unreliable — the lineage's
-- FIELD_INFO construction).
function M.bind(P, ioport)
    local info, fields, all = {}, {}, {}
    for who, side in pairs(P.sides) do
        fields[who] = {}
        for tok, pf in pairs(side.tokens) do
            local p = ioport.ports[pf[1]]
            assert(p, "no port " .. pf[1])
            local f = p.fields[pf[2]]
            assert(f, "no field '" .. pf[2] .. "' in " .. pf[1])
            info[f] = { pf[1], f.mask }
            fields[who][tok] = f
            all[#all + 1] = f
        end
    end
    return { fields = fields, info = info, all = all }
end

-- Map a parsed replay (rpl_parse's {who, tok} pairs) onto field objects.
function M.held_fields(F, held)
    local out = {}
    for fr, list in pairs(held) do
        local h = {}
        for i, wt in ipairs(list) do h[i] = F.fields[wt[1]][wt[2]] end
        out[fr] = h
    end
    return out
end

return M
