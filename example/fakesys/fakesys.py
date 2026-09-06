#!/usr/bin/env python3
"""fakesys.py — a deterministic FAKE MACHINE, so the harness can be exercised
end to end without a ROM, an emulator, or a board.

It is driven exactly like an emulator under the replay engine: a set name,
a search path holding `<set>.zip`, a replay script, and the environment of
drivers/README.md. It writes the checksum-log grammar (`<frame> <hash>` per
frame, `END <n>` last) and honours the same variables, so every
expectation class has a producer:

    the ROM's `features=` line (member <set>.01), or FAKE_BUILD=<list>:
      (none)   the BASE machine                          -> exact / .sha1
      hook     one byte written a frame LATE on every player-button
               press, and "cycle cost" noise in the stack region
               $FF80-$FFFF every frame (the region a consumer MASKS)
                                                         -> flicker
      select   after 1P start, a contiguous range of frames touching one
               byte, then restored                       -> window
      attract  the attract demo (frame 900 on, no coin) diverges
               permanently                               -> diverge
      both     = hook,select                             -> composite
    FAKE_NONDET=1     mixes the clock in: the NONDETERMINISTIC path
    FAKE_CRASH_AT=n   the guarded grammar: CRASH / REGS / STACK lines at
                      frame n, END-CRASH, exit 2

Environment (the driver contract): REPLAY (required), CHECKSUM_OUT,
TAIL_FRAMES (120), MASK_RANGES (`lo-hi,...` hex offsets from the window
base, end exclusive; masked bytes are SKIPPED from the hash), DUMPS
(`frame:lo-hi;...` -> dump_<frame>_<lo>.bin beside the log), POKES
(`frame:addr:hexbytes;...`, applied at the start of the frame),
SNAP_FRAMES (`f,f,...` -> snap_<f>.ppm in FAKE_SANDBOX or beside the log),
VIDEO_OUT (a second hash log over the 64x64 screen), INPUT_OUT (`<frame>
<p1> <p2> <sys>` per frame), INPUT_INJECT_TEST=<frame> (the must-fire
control of the input-integrity assertion: writes an INPUT-VIOLATION line
before END), NO_INPUT_CHECK (disables that assertion).

The machine: 64 KiB of RAM (the whole of it is the checksum window), three
ports with the lineage's token vocabulary (p1/p2: U D L R 1-6; sys: S1 S2
C1 C2 SV TS), a frame counter, an input mirror, a PRNG seeded from the
ROM, an attract -> select -> match state machine, a 64x64 screen. The
per-frame hash is 16 hex characters (blake2b-64 over the unmasked window;
the log grammar names no algorithm, and this one is fast in pure python).

    python3 fakesys.py <set> [--rompath "dir;dir"]     (or FAKE_ROMPATH)
"""
import hashlib
import os
import sys
import time
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "lib" / "py"))
from bbh import rpl  # noqa: E402

RAM_SIZE = 0x10000
BITS = {"p1": {t: i for i, t in enumerate("UDLR123456")},
        "p2": {t: i for i, t in enumerate("UDLR123456")},
        "sys": {t: i for i, t in enumerate(["S1", "S2", "C1", "C2", "SV", "TS"])}}
BUTTONS = 0x3F0          # bits 4-9 of a player port
FEATURE_ALIASES = {"base": "", "both": "hook,select"}


def die(msg, rc=1):
    print(f"fakesys: {msg}", file=sys.stderr)
    sys.exit(rc)


def find_rom(setname, rompath):
    for d in rompath.split(";"):
        cand = Path(d) / f"{setname}.zip"
        if cand.is_file():
            return cand
    die(f"{setname}.zip not found in rompath {rompath}")


def read_rom(zpath, setname):
    with zipfile.ZipFile(zpath) as zf:
        try:
            cfg = zf.read(f"{setname}.01").decode()
            seedtxt = zf.read(f"{setname}.02").decode()
        except KeyError as e:
            die(f"{zpath}: missing program member {e}")
    feats = ""
    for line in cfg.splitlines():
        if line.startswith("features="):
            feats = line.split("=", 1)[1].strip()
    seed = 1
    for line in seedtxt.splitlines():
        if line.startswith("seed="):
            seed = int(line.split("=", 1)[1])
    return feats, seed


def parse_mask(spec):
    ranges = []
    for part in [p for p in spec.split(",") if p.strip()]:
        lo, hi = part.split("-")
        lo, hi = int(lo, 16), int(hi, 16)
        if hi < lo:
            die(f"MASK_RANGES: {lo:04x}-{hi:04x} is inverted")
        if hi > RAM_SIZE:
            die(f"MASK_RANGES: {lo:04x}-{hi:04x} runs past work RAM ({RAM_SIZE:x})")
        ranges.append((lo, hi))
    if spec.strip() and not ranges:
        die(f"MASK_RANGES is set but parsed to no ranges: {spec}")
    return sorted(ranges)


def kept_slices(mask):
    out, pos = [], 0
    for lo, hi in mask:
        if lo > pos:
            out.append((pos, lo))
        pos = max(pos, hi)
    if pos < RAM_SIZE:
        out.append((pos, RAM_SIZE))
    return out


def parse_dumps(spec):
    out = {}
    for part in [p for p in spec.split(";") if p.strip()]:
        try:
            fr, rng = part.split(":")
            lo, hi = rng.split("-")
            out.setdefault(int(fr), []).append((int(lo, 16), int(hi, 16)))
        except ValueError:
            die(f"bad DUMPS spec: {part}")
    return out


def parse_pokes(spec):
    out = {}
    for part in [p for p in spec.split(";") if p.strip()]:
        try:
            fr, addr, hexb = part.split(":")
            out.setdefault(int(fr), []).append((int(addr, 16), bytes.fromhex(hexb)))
        except ValueError:
            die(f"bad POKES spec: {part}")
    return out


def h16(data):
    return hashlib.blake2b(data, digest_size=8).hexdigest()


def main(argv):
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("set")
    ap.add_argument("--rompath", default=os.environ.get("FAKE_ROMPATH", ""))
    a = ap.parse_args(argv)
    if not a.rompath:
        die("no search path: pass --rompath or set FAKE_ROMPATH")
    env = os.environ.get
    replay = env("REPLAY") or die("set REPLAY to the input script path")
    out_path = env("CHECKSUM_OUT") or "replay_checksums.txt"
    tail = int(env("TAIL_FRAMES") or 120)
    mask = parse_mask(env("MASK_RANGES") or "")
    kept = kept_slices(mask)
    dumps = parse_dumps(env("DUMPS") or "")
    pokes = parse_pokes(env("POKES") or "")
    snaps = {int(x) for x in (env("SNAP_FRAMES") or "").replace(",", " ").split()}
    video_out = env("VIDEO_OUT")
    input_out = env("INPUT_OUT")
    inject = int(env("INPUT_INJECT_TEST") or 0)
    integrity = env("NO_INPUT_CHECK") is None
    nondet = env("FAKE_NONDET") == "1"
    crash_at = int(env("FAKE_CRASH_AT") or 0)
    out_dir = Path(out_path).resolve().parent
    snap_dir = Path(env("FAKE_SANDBOX") or out_dir)

    zpath = find_rom(a.set, a.rompath)
    feats, seed = read_rom(zpath, a.set)
    if env("FAKE_BUILD") is not None:
        feats = FEATURE_ALIASES.get(env("FAKE_BUILD"), env("FAKE_BUILD"))
    features = {f.strip() for f in feats.split(",") if f.strip()}
    for f in features:
        if f not in {"hook", "select", "attract"}:
            die(f"unknown feature '{f}' (hook, select, attract)")

    try:
        held, last = rpl.parse(replay)
    except rpl.RplError as e:
        die(str(e))
    total = last + tail

    ram = bytearray(RAM_SIZE)
    screen = bytearray(64 * 64)
    x = seed & ((1 << 64) - 1)
    prev = {"p1": 0, "p2": 0, "sys": 0}
    mode, credits, coined = 0, 0, False
    select_start = match_start = 0
    hp = [100, 100]
    pending_late = None
    violations, first_violation = 0, None

    f = open(out_path, "w")
    vf = open(video_out, "w") if video_out else None
    inf = open(input_out, "w") if input_out else None
    try:
        for frame in range(1, total + 1):
            for addr, data in pokes.get(frame, []):
                ram[addr:addr + len(data)] = data
            ports = {"p1": 0, "p2": 0, "sys": 0}
            for who, tok in held.get(frame, []):
                ports[who] |= 1 << BITS[who][tok]
            edge = {k: ports[k] & ~prev[k] for k in ports}

            # the machine
            ram[0:4] = frame.to_bytes(4, "big")
            for i, k in enumerate(("p1", "p2", "sys")):
                ram[0x58 + 2 * i:0x5A + 2 * i] = ports[k].to_bytes(2, "big")
            x = (x * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
            if nondet:
                x ^= time.time_ns() & 0xFFFF
            ram[0x1000 + (frame * 7) % 0x800] = x >> 56
            ram[0x200:0x208] = x.to_bytes(8, "big")
            if edge["sys"] & (1 << BITS["sys"]["C1"] | 1 << BITS["sys"]["C2"]):
                credits += 1
                coined = True
            ram[0x104] = credits & 0xFF
            ram[0x100] = mode
            if mode == 0:
                if edge["sys"] & (1 << BITS["sys"]["S1"]) and credits > 0:
                    credits -= 1
                    mode, select_start = 1, frame
                elif frame >= 900 and not coined:
                    # base: d; attract: 3d+1 — never equal (2d+1 is odd), so
                    # the divergence starts at exactly 900 and never re-converges
                    d = frame - 900
                    ram[0x300] = ((3 * d + 1) if "attract" in features else d) & 0xFF
            elif mode == 1:
                if edge["p1"] & BUTTONS:
                    ram[0x110] = (ram[0x110] + 1) & 0xFF
                if "select" in features and select_start + 60 <= frame <= select_start + 159:
                    ram[0x710] = 1
                else:
                    ram[0x710] = 0
                if frame >= select_start + 200:
                    mode, match_start = 2, frame
            elif mode == 2:
                t = max(0, 5940 - (frame - match_start))
                ram[0x102:0x104] = t.to_bytes(2, "big")
                if edge["p1"] & BUTTONS:
                    hp[1] = max(0, hp[1] - 1)
                if edge["p2"] & BUTTONS:
                    hp[0] = max(0, hp[0] - 1)
                ram[0x400], ram[0x402] = hp
                if t == 0 or 0 in hp:
                    mode = 3
            # the hook's late byte: base writes it on the press frame; the
            # hooked build writes it one frame later (a 1-frame flicker)
            if pending_late is not None:
                ram[0x700] = pending_late
                pending_late = None
            if (edge["p1"] | edge["p2"]) & BUTTONS:
                v = frame % 251 + 1
                if "hook" in features:
                    pending_late = v
                else:
                    ram[0x700] = v
            ram[0xFF00 + frame % 0x80] = frame & 0xFF
            if "hook" in features:
                ram[0xFF80 + frame % 0x80] = (frame * 31) & 0xFF
            screen[(frame * 13) % 4096] = ram[0x1000 + (frame * 7) % 0x800]
            screen[4095] = mode

            # instruments
            if frame == crash_at:
                pc = 0x1000 + frame
                f.write(f"CRASH {frame} vec4 PC {pc:06x}\n")
                f.write(f"REGS D0={x & 0xffffffff:08x} A7=00ff7ff0\n")
                f.write(f"STACK 0000 {frame:04x} {pc:04x}\n")
                f.write(f"END-CRASH {frame}\n")
                f.close()
                sys.exit(2)
            f.write(f"{frame} {h16(b''.join(bytes(ram[a:b]) for a, b in kept))}\n")
            if vf:
                vf.write(f"{frame} {h16(bytes(screen))}\n")
            if inf:
                inf.write(f"{frame} {ports['p1']:04x} {ports['p2']:04x} {ports['sys']:04x}\n")
            for lo, hi in dumps.get(frame, []):
                (out_dir / f"dump_{frame}_{lo:06x}.bin").write_bytes(bytes(ram[lo:hi]))
            if frame in snaps:
                snap_dir.mkdir(parents=True, exist_ok=True)
                with open(snap_dir / f"snap_{frame}.ppm", "wb") as pf:
                    pf.write(b"P6\n64 64\n255\n" + bytes(b for v in screen for b in (v, v, v)))
            if integrity and inject and frame + 1 == inject:
                violations += 1
                want = ports["sys"]
                first_violation = first_violation or (
                    f"frame {frame + 1} port :IN2 expected {want:04x} got {want ^ 1:04x} (mask 0001)")
            prev = ports
        if violations:
            f.write(f"INPUT-VIOLATION {violations} {first_violation}\n")
        f.write(f"END {total}\n")
        if vf:
            vf.write(f"END {total}\n")
        if inf:
            inf.write(f"END {total}\n")
    finally:
        f.close()
        if vf:
            vf.close()
        if inf:
            inf.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
