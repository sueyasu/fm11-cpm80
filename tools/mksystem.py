#!/usr/bin/env python3
import argparse
from pathlib import Path

CCP_BASE = 0xC400
BIOS_BASE = 0xDA00
IOSERVER_BASE = 0xDE00
CORE_SIZE = BIOS_BASE - CCP_BASE
BIOS_MAX = IOSERVER_BASE - BIOS_BASE

p = argparse.ArgumentParser(description="Build the FM-11 56K CP/M 2.2 system payload")
p.add_argument("--core", required=True, help="56K CCP+BDOS image, C400-D9FF")
p.add_argument("--bios", required=True, help="BIOS image assembled at DA00")
p.add_argument("--output", required=True)
a = p.parse_args()

core = Path(a.core).read_bytes()
bios = Path(a.bios).read_bytes()

if len(core) != CORE_SIZE:
    raise SystemExit(
        f"error: CCP+BDOS must be exactly 0x{CORE_SIZE:X} bytes "
        f"(C400-D9FF); got 0x{len(core):X}"
    )
if len(bios) > BIOS_MAX:
    raise SystemExit(
        f"error: BIOS exceeds DA00-DDFF: 0x{len(bios):X} bytes "
        f"(maximum 0x{BIOS_MAX:X})"
    )

# Pad the BIOS to DE00 so the generated payload has a stable load extent.
out = core + bios + bytes(BIOS_MAX - len(bios))
Path(a.output).write_bytes(out)
print(f"wrote {a.output}: 0x{len(out):X} bytes (C400-DDFF)")
