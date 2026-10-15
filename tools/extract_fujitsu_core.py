#!/usr/bin/env python3
import argparse
from pathlib import Path

CORE_OFFSET = 0x0200
CORE_SIZE = 0x1600
MIN_IMAGE_SIZE = CORE_OFFSET + CORE_SIZE

p = argparse.ArgumentParser(
    description="Extract the 56K CCP+BDOS core from a Fujitsu FM-11 CP/M disk image"
)
p.add_argument("image")
p.add_argument("output")
a = p.parse_args()

src = Path(a.image).read_bytes()
if len(src) < MIN_IMAGE_SIZE:
    raise SystemExit(
        f"error: image is too small (0x{len(src):X}); need at least 0x{MIN_IMAGE_SIZE:X} bytes"
    )

core = src[CORE_OFFSET:CORE_OFFSET + CORE_SIZE]
Path(a.output).parent.mkdir(parents=True, exist_ok=True)
Path(a.output).write_bytes(core)
print(
    f"wrote {a.output}: 0x{len(core):X} bytes from image offsets "
    f"0x{CORE_OFFSET:04X}-0x{CORE_OFFSET + CORE_SIZE - 1:04X}"
)
