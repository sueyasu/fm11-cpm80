#!/usr/bin/env python3
"""Create an empty NON-BOOTABLE FM-11 CP/M whole-HDD data image."""
import argparse
from pathlib import Path

MODELS = {
    "m2230b": [
        315,
        2
    ],
    "m2231b": [
        157,
        4
    ],
    "m2232b": [
        157,
        6
    ],
    "m2233b": [
        315,
        4
    ],
    "m2234b": [
        315,
        6
    ],
    "m2235b": [
        315,
        8
    ],
    "m2241b": [
        747,
        4
    ],
    "m2242b": [
        747,
        7
    ],
    "m2243b": [
        747,
        11
    ]
}
def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--model", choices=MODELS, default="m2233b")
    p.add_argument("output", type=Path)
    a = p.parse_args()
    c, h = MODELS[a.model]
    a.output.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation: never erase an existing disk.
    with a.output.open("xb") as f:
        for _ in range(c*h):
            f.write(bytes([0xe5])*8192)
    print(f"{a.output}: {c*h*8192} bytes ({a.model}, data only)")
if __name__ == "__main__":
    main()
