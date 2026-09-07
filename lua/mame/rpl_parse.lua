-- rpl_parse.lua — the `.rpl` replay grammar, parsed in ONE place on the Lua
-- side (the python twin is lib/py/bbh/rpl.py; selftest/test_rpl_lua.sh and
-- fidelity F8 prove the two agree on every replay).
--
--   <frame>[-<endframe>] <who>=<tokens> [<who>=<tokens> ...]
--   <frame> wait
--
-- `#` starts a comment; blank lines are ignored. `who` is a SIDE of the
-- machine profile (the lineage's p1 / p2 / sys); its tokens are concatenated
-- and split by the side's TOKEN WIDTH (one character for a player, two for
-- `sys`). Lines OR together: a token is held for every frame its ranges
-- cover. Frame 1 is the first emulated frame. `wait` holds nothing and only
-- extends the replay.
--
-- The lineage (VampireSaved tests/lua/*.lua) carried this parser in SEVEN
-- files — one strict copy in replay.lua / replay_guard.lua and five lenient
-- copies in the tap instruments that silently DROPPED an unknown side or
-- token. This module is the strict one for all of them: a replay the
-- grammar rejects fails loudly with its line's reason, never plays a subset.
-- Error texts are the lineage's assertions, so a replay rejected here is
-- rejected by rpl.py for the same reason.
--
-- Runs under MAME's Lua and under a standalone lua (5.3+): no MAME API here.
--
--   local rpl = dofile(".../rpl_parse.lua")
--   local held, last_frame, nlines = rpl.parse(path, sides)
--       held[frame] = { {who, token}, ... } in file order (duplicates kept)
--       sides[who]  = { width = n, tokens = "UDLR…" | { tok = true, … } }
--   rpl.dump(held, last_frame)  -> the canonical text (the equality check)

local M = {}

-- The lineage's vocabulary, as the default for a standalone lint.
M.DEFAULT_SIDES = {
    p1  = { width = 1, tokens = "UDLR123456" },
    p2  = { width = 1, tokens = "UDLR123456" },
    sys = { width = 2, tokens = "S1S2C1C2SVTS" },
}

local function split_tokens(width, s)
    local toks = {}
    for i = 1, #s, width do toks[#toks + 1] = s:sub(i, i + width - 1) end
    return toks
end
M.split_tokens = split_tokens

-- side.tokens: a string split by width, or a table whose KEYS are the tokens
-- (a machine profile's token -> {port, field} map serves directly).
local function vocab_of(side)
    if type(side.tokens) == "string" then
        local set = {}
        for _, t in ipairs(split_tokens(side.width, side.tokens)) do set[t] = true end
        return set
    end
    return side.tokens
end
M.vocab_of = vocab_of

function M.parse(path, sides)
    sides = sides or M.DEFAULT_SIDES
    local vocab = {}
    for who, side in pairs(sides) do vocab[who] = vocab_of(side) end
    local held, last_frame, nlines = {}, 0, 0
    local lineno = 0
    for line in io.lines(path) do
        lineno = lineno + 1
        local body = line:gsub("#.*", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if #body > 0 then
            nlines = nlines + 1
            local range, rest = body:match("^(%S+)%s+(.*)$")
            if not range then
                error(path .. ":" .. lineno .. ": expected '<frame>[-<end>] who=tokens'", 0)
            end
            local a, b = range:match("^(%d+)%-(%d+)$")
            if not a then a = range:match("^(%d+)$"); b = a end
            if not a then
                error(path .. ":" .. lineno .. ": bad frame range '" .. range .. "'", 0)
            end
            a, b = tonumber(a), tonumber(b)
            if not (a >= 1 and b >= a) then
                error(path .. ":" .. lineno .. ": bad range", 0)
            end
            for spec in rest:gmatch("%S+") do
                if spec ~= "wait" then
                    local who, toks = spec:match("^(%a+%d?)=(%S+)$")
                    local v = who and vocab[who]
                    if not v then
                        error(path .. ":" .. lineno .. ": unknown side '" .. tostring(who) .. "'", 0)
                    end
                    for _, t in ipairs(split_tokens(sides[who].width, toks)) do
                        if not v[t] then
                            error(path .. ":" .. lineno .. ": unknown token '" .. t .. "' for " .. who, 0)
                        end
                        for fr = a, b do
                            held[fr] = held[fr] or {}
                            held[fr][#held[fr] + 1] = { who, t }
                        end
                    end
                end
            end
            if b > last_frame then last_frame = b end
        end
    end
    return held, last_frame, nlines
end

-- The canonical text of a parse: one line per held frame, ascending,
-- `<frame> who=tok who=tok …` in file order, then `last <n>`. rpl.py's
-- `dump` prints the same text; the two must be byte-identical.
function M.dump(held, last_frame)
    local frames = {}
    for fr in pairs(held) do frames[#frames + 1] = fr end
    table.sort(frames)
    local out = {}
    for _, fr in ipairs(frames) do
        local parts = { tostring(fr) }
        for _, wt in ipairs(held[fr]) do parts[#parts + 1] = wt[1] .. "=" .. wt[2] end
        out[#out + 1] = table.concat(parts, " ")
    end
    out[#out + 1] = "last " .. last_frame
    return table.concat(out, "\n") .. "\n"
end

return M
