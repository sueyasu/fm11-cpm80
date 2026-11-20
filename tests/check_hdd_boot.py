#!/usr/bin/env python3
"""Structural test of both native boot variants, no emulator required."""
import sys
import tempfile
from pathlib import Path
from mk_hdd_boot import build_image, MODELS

native, v20 = map(Path, sys.argv[1:])
ipl = (native / "ipl_hdd.bin").read_bytes()
rom = (native / "hdd_bootrom.bin").read_bytes()
assert len(ipl) == 512 and ipl[0] == 0xfa
assert len(rom) == 4096 and rom[0xff0:0xff5] == bytes.fromhex("ea 00 00 00 ff")
assert bytes.fromhex("b0 08 ea 00 00 00 04") in ipl
with tempfile.TemporaryDirectory() as tmp:
    f = Path(tmp) / "TEST.COM"
    data = bytes(range(256))*513  # crosses one 128 KiB physical extent
    f.write_bytes(data)
    for target in (native, v20):
        server = (target / "ioserver.bin").read_bytes()
        system = (target / "system62.bin").read_bytes()
        for model, (c,h) in MODELS.items():
            raw = build_image(model, ipl, server, system, [f])
            base = h*8192
            assert len(raw) == c*h*8192
            assert raw[:512] == ipl
            assert raw[512:6656] == server
            assert raw[6656:13312] == system
            assert raw[13312:base] == bytes([0xe5])*(base-13312)
            assert raw[base+1:base+12] == b"TEST    COM"
            assert raw[base+12] == 7 and raw[base+15] == 128
            assert raw[base+16:base+32] == b"".join(i.to_bytes(2,"little") for i in range(1,9))
            assert raw[base+44] == 8 and raw[base+47] == 2
            assert raw[base+48:base+50] == b"\x09\x00"
            assert raw[base+16384:base+16384+len(data)] == data
        print("PASS:", target, "all nine HDD boot image layouts")
