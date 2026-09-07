-- profiles/cps2w.lua — CPS-2 WIDE: the lineage's extended profile (a 6 MB
-- program window, `vsavjw`). Identical to cps2.lua except the code window
-- a ROM-plausible long may fall in — the lineage's inp_guard.lua carried
-- 0x600000 where its replay_guard.lua still carried the stock 0x400000, so
-- the two guards drew different STACK sketches on the same crash. One
-- machine, one profile: choose by BBH_PROFILE.
local P = dofile((debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or ".") .. "/cps2.lua")
P.name = "cps2w"
P.crash.code = { lo = 0x000100, hi = 0x600000 }
return P
