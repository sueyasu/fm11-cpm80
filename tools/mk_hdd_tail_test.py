#!/usr/bin/env python3
"""Build/verify a disposable M2243B image for HDDTEST.COM."""
import argparse
from pathlib import Path

CYL, HEADS = 747, 11
TRACK = 8192
BLOCK = 16384
BASE = HEADS * TRACK
SIZE = CYL * HEADS * TRACK
DSM = (CYL-1)*HEADS//2-1
TAIL = BASE + DSM*BLOCK
GUARD = BASE + (DSM % 512)*BLOCK
assert DSM == 4102 and TAIL+BLOCK == SIZE

def entry(name, ext, block, records):
    e = bytearray(32)
    e[1:9] = name.encode().ljust(8)
    e[9:12] = ext.encode().ljust(3)
    e[15] = records
    e[16:18] = block.to_bytes(2, "little")
    return e

def fixture(program):
    assert 0 < len(program) <= BLOCK
    raw = bytearray(b"\xe5") * SIZE
    raw[BASE:BASE+32] = entry("HDDTEST", "COM", 1, (len(program)+127)//128)
    raw[BASE+32:BASE+64] = entry("TAIL", "DAT", DSM, 128)
    raw[BASE+64:BASE+96] = entry("GUARD", "DAT", DSM%512, 128)
    raw[BASE+BLOCK:BASE+BLOCK+len(program)] = program
    raw[GUARD:GUARD+BLOCK] = bytes([0x69])*BLOCK
    raw[TAIL:TAIL+BLOCK] = bytes((r+j)&255 for r in range(128) for j in range(128))
    return raw

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("action", choices=("create","verify"))
    p.add_argument("image", type=Path)
    p.add_argument("program", type=Path)
    a = p.parse_args()
    raw = fixture(a.program.read_bytes())
    if a.action == "create":
        a.image.parent.mkdir(parents=True, exist_ok=True)
        with a.image.open("xb") as f:
            f.write(raw)
        print(f"{a.image}: DSM={DSM}, tail offset={TAIL:#x}, last LBA={SIZE//256-1}")
    else:
        raw[-128:] = bytes([0xa5])*128
        actual = a.image.read_bytes()
        if actual != raw:
            if len(actual) != len(raw):
                raise SystemExit("FAIL: image size changed")
            pos = next(i for i,(x,y) in enumerate(zip(actual,raw)) if x != y)
            raise SystemExit(f"FAIL: unexpected byte at {pos:#x}: {actual[pos]:02x}, expected {raw[pos]:02x}")
        print("PASS: final record persisted; every other image byte unchanged")

if __name__ == "__main__":
    main()
