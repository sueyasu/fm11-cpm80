#!/usr/bin/env python3
import argparse
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("file")
p.add_argument("--max-size", required=True, type=lambda s: int(s, 0))
p.add_argument("--name", default="binary")
a = p.parse_args()

path = Path(a.file)
size = path.stat().st_size
if size > a.max_size:
    raise SystemExit(f"error: {a.name} is 0x{size:X} bytes; limit is 0x{a.max_size:X}")
print(f"{a.name}: 0x{size:X} bytes (limit 0x{a.max_size:X})")
