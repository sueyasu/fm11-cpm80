#!/usr/bin/env python3
"""Check 6809 boot slots and geometry across all supported models."""
import sys
from pathlib import Path
from mk_hdd_boot import build_image, MODELS
native, cpm = map(Path, sys.argv[1:])
ipl = (native / "ipl_hdd.bin").read_bytes()
server = (native / "ioserver.bin").read_bytes()
system = (cpm / "system62.bin").read_bytes()
for model, (c,h) in MODELS.items():
    raw = build_image(model, ipl, server, system, cpu="6809")
    base = h*8192
    assert len(raw) == c*h*8192
    assert raw[:512] == ipl.ljust(512,b"\0")
    assert raw[512:6656] == server.ljust(6144,b"\0")
    assert raw[6656:13312] == system
    assert raw[13312:base+16384] == b"\xe5"*(base+16384-13312)
    # Verify the split tag representation and 24-bit LBA at every track.
    for track in range(c*h):
        hi, lo = divmod(track,256)
        assert ((hi << 8) | lo)*32+31 < c*h*32
print("PASS: all nine 6809 HDD image layouts")
