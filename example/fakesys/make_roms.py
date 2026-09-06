#!/usr/bin/env python3
"""make_roms.py — generate the example's FAKE ROM images, deterministically.

    python3 example/fakesys/make_roms.py [--out example/roms] [--check]

Five images of the fake machine, each `<dir>/fake.zip` with the members
`fake.01` (the features line — the PROGRAM), `fake.02` (the seed — program),
`fake.gfx` (NOT a program member) and `fake.key`:

    base          no features                       registered by PROGRAM key
    attract       attract                           registered by PROGRAM key
    build-a       hook,select,attract + gfx v1      registered by WHOLE-SET key
    build-b       hook,select,attract + gfx v2      registered by WHOLE-SET key
    hook          hook                              NOT registered (the loud exit 2)

build-a and build-b are THE DUAL-KEY CASE: the same program members, so the
same program key, and one non-program member apart, so different whole-set
keys — the shape of a gfx-only freeze, where a registry keyed on the program
alone would hand two builds one expectation set.

Every zip is byte-reproducible (fixed timestamps, stored, sorted members),
so `--check` can assert the committed images and `expected/registry.tsv`
still describe what this script generates; the selftest runs it.
"""
import argparse
import hashlib
import io
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "lib" / "py"))

IMAGES = {
    "base":     ("", 12345, b"GFX v1 " * 64),
    "attract":  ("attract", 12345, b"GFX v1 " * 64),
    "build-a":  ("hook,select,attract", 12345, b"GFX v1 " * 64),
    "build-b":  ("hook,select,attract", 12345, b"GFX v2 " * 64),
    "hook":     ("hook", 12345, b"GFX v1 " * 64),
}
STAMP = (2026, 1, 1, 0, 0, 0)


def image_bytes(features, seed, gfx):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_STORED) as zf:
        members = {
            "fake.01": f"features={features}\n".encode(),
            "fake.02": f"seed={seed}\n".encode(),
            "fake.gfx": gfx,
            "fake.key": b"fake-key-0001",
        }
        for name in sorted(members):
            zi = zipfile.ZipInfo(name, date_time=STAMP)
            zi.compress_type = zipfile.ZIP_STORED
            zf.writestr(zi, members[name])
    return buf.getvalue()


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(HERE.parent / "roms"))
    ap.add_argument("--check", action="store_true", help="assert the images on disk are what this generates")
    a = ap.parse_args(argv)
    out = Path(a.out)
    bad = 0
    for name, (features, seed, gfx) in IMAGES.items():
        data = image_bytes(features, seed, gfx)
        path = out / name / "fake.zip"
        if a.check:
            have = path.read_bytes() if path.is_file() else b""
            same = have == data
            print(f"  {'ok   ' if same else 'FAIL '} {path.relative_to(out.parent)} "
                  f"{'matches' if same else 'DIFFERS from'} the generator")
            bad |= not same
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            print(f"wrote {path} sha1 {hashlib.sha1(data).hexdigest()[:8]}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
