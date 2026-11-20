#!/usr/bin/env python3
"""Emit ordered padded IPL assets and FORMAT transient workspace."""
import argparse
from pathlib import Path

LABELS = ("IPL092D", "IPL092H", "IPL09HD", "IPL862D", "IPL862H", "IPL86HD")

def generate(paths):
    out = []
    for label, path in zip(LABELS, paths):
        raw = path.read_bytes()
        if not 0 < len(raw) <= 512:
            raise ValueError(f"{path}: IPL size {len(raw)}")
        raw = raw.ljust(512, b"\x00")
        for i in range(0,512,16):
            prefix = label if i == 0 else "        "
            out.append(prefix + " DB " + ",".join(f"0{x:02X}H" for x in raw[i:i+16]))
    out.extend(("SAVED DS 256", "BUFFER DS 10900", "IMAGE DS 12800",
                "        DS 256", "STACKTOP EQU $", ""))
    return "\n".join(out)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("output", type=Path)
    p.add_argument("ipls", type=Path, nargs=6)
    a = p.parse_args()
    a.output.write_text(generate(a.ipls), encoding="ascii")

if __name__ == "__main__":
    main()
