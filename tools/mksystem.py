#!/usr/bin/env python3
import argparse
from pathlib import Path

CCP_BASE = 0xDC00
BIOS_BASE = 0xF200
SYSTEM_END = 0xF600
CORE_SIZE = BIOS_BASE - CCP_BASE
BIOS_MAX = SYSTEM_END - BIOS_BASE

p = argparse.ArgumentParser(description="Build the FM-11 62K CP/M 2.2 system payload")
p.add_argument("--core", required=True, help="62K CCP+BDOS image, DC00-F1FF")
p.add_argument("--bios", required=True, help="BIOS image assembled at F200")
p.add_argument("--output", required=True)
a = p.parse_args()

core = Path(a.core).read_bytes()
bios = Path(a.bios).read_bytes()

if len(core) != CORE_SIZE:
    raise SystemExit(
        f"error: CCP+BDOS must be exactly 0x{CORE_SIZE:X} bytes "
        f"(DC00-F1FF); got 0x{len(core):X}"
    )
if len(bios) > BIOS_MAX:
    raise SystemExit(
        f"error: BIOS exceeds F200-F5FF: 0x{len(bios):X} bytes "
        f"(maximum 0x{BIOS_MAX:X})"
    )

# Keep the on-disk system payload at 0x1A00 bytes so the I/O-server sectors
# remain at the same cylinder-0 locations.
out = core + bios + bytes(BIOS_MAX - len(bios))
Path(a.output).write_bytes(out)
print(f"wrote {a.output}: 0x{len(out):X} bytes (DC00-F5FF)")
