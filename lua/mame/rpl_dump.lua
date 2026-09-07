-- rpl_dump.lua — print the canonical parse of one or more replays through
-- rpl_parse.lua, for the equality check against `python3 -m bbh.rpl dump`.
--
-- Standalone:  lua rpl_dump.lua [--profile x.lua] <replay.rpl>...
-- Under MAME:  mame <set> -autoboot_script rpl_dump.lua  with
--              env RPL_DUMP_FILES (one path per line) and RPL_DUMP_OUT (the
--              output file); BBH_PROFILE selects the vocabulary. The machine
--              exits at its first frame — a boot's worth of time, and the
--              parse runs under the PRODUCTION interpreter.
--
-- Output per replay: `== <path>`, then rpl_parse.dump's text, or
-- `ERROR <message>` for a replay the grammar rejects.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$"))
    or (os.getenv("BBH_HOME") and (os.getenv("BBH_HOME") .. "/lua/mame")) or "."
local rpl = dofile(HERE .. "/rpl_parse.lua")

-- BBH_PROFILE as the drivers resolve it: a bare name is lua/mame/profiles/<name>.lua
local function sides_of(profile_path)
    if not profile_path or profile_path == "" then return rpl.DEFAULT_SIDES end
    if not profile_path:find("/") then
        if not profile_path:match("%.lua$") then profile_path = profile_path .. ".lua" end
        profile_path = HERE .. "/profiles/" .. profile_path
    end
    local P = dofile(profile_path)
    return P.sides
end

local function dump_all(paths, sides, out)
    for _, path in ipairs(paths) do
        out:write("== " .. path .. "\n")
        local ok, held, last = pcall(rpl.parse, path, sides)
        if ok then out:write(rpl.dump(held, last))
        else out:write("ERROR " .. tostring(held) .. "\n") end
    end
end

if manager then
    -- under MAME
    local paths = {}
    for line in (os.getenv("RPL_DUMP_FILES") or ""):gmatch("[^\n]+") do paths[#paths + 1] = line end
    local out = assert(io.open(assert(os.getenv("RPL_DUMP_OUT"), "set RPL_DUMP_OUT"), "wb"))
    dump_all(paths, sides_of(os.getenv("BBH_PROFILE")), out)
    out:close()
    emu.register_frame_done(function() manager.machine:exit() end)
else
    local paths, prof = {}, os.getenv("BBH_PROFILE")
    local i = 1
    while i <= #arg do
        if arg[i] == "--profile" then prof = arg[i + 1]; i = i + 2
        else paths[#paths + 1] = arg[i]; i = i + 1 end
    end
    dump_all(paths, sides_of(prof), io.stdout)
end
