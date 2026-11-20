#!/usr/bin/env python3
"""Pad an assembled CCP/BDOS to DC00h-F1FFh without truncating code."""
import sys
from pathlib import Path

source, dest = map(Path, sys.argv[1:])
limit = 0x1600
data = source.read_bytes()
size = len(data)
if not 0x806 < size <= limit:
    raise SystemExit(f"{source}: got {size} bytes, invalid CCP/BDOS size (maximum {limit})")
if data[0] != 0xc3 or data[0x806] != 0xc3:
    raise SystemExit(f"{source}: missing CCP or BDOS entry JMP at DC00h/E406h")
dest.write_bytes(data.ljust(limit, b"\x00"))
print(f"{source}: {size} bytes; padded {limit-size} bytes -> {dest}: {limit} bytes")
