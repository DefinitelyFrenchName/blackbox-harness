"""thresholds.py — THE comparison-class thresholds, declared ONCE.

Three numbers govern every non-exact comparison class:

    FLICKER_MAX = 2    a divergent run this short or shorter is a FLICKER
                       frame ("isolated <=2-frame divergences")
    RECONVERGE  = 60   identical frames required after the last divergence
                       (the non-propagation proof; it governs the
                       re-convergence TAIL and does not bind across the gap
                       between two separately attributed mechanisms)
    MAX_TOTAL   = 8    the cap on a flicker INVENTORY (never on a window run)

A consumer may set them in its bbh.toml `[thresholds]` section
(`flicker_max`, `reconverge`, `flicker_max_total`); the comparators read
them from here and NOWHERE ELSE. Lineage: VampireSaved's
tools/s4_thresholds.py (14z-93, GitHub #44 there), where the pair had been
declared FOUR times with a comment saying they "must stay in step" and
nothing asserting it — and the tool whose purpose was "propose a line that
drops in verbatim" could propose one the checker rejected. The values are a
consumer's RATIFIED comparison policy, not a tuning knob: changing one is an
amendment of that policy and a reviewed edit of its config.

Resolution: the environment's BBH_CONFIG (exported by every runner and by
lib/sh/config.sh) names the consumer config; absent, the defaults apply.
"""
import os

_DEFAULTS = {"flicker_max": 2, "reconverge": 60, "flicker_max_total": 8}


def _resolve():
    vals = dict(_DEFAULTS)
    path = os.environ.get("BBH_CONFIG")
    if path and os.path.isfile(path):
        from . import config as C
        cfg = C.load(path)
        for k in vals:
            vals[k] = int(C.get(cfg, "thresholds." + k, vals[k]))
    return vals


_V = _resolve()
FLICKER_MAX = _V["flicker_max"]
RECONVERGE = _V["reconverge"]
MAX_TOTAL = _V["flicker_max_total"]
