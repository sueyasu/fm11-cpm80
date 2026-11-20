#!/usr/bin/env python3
"""Structural checks for the V20 backend and both disk images."""
from pathlib import Path
import struct
import sys

v20, native, images = map(Path, sys.argv[1:])
bios = (v20 / "bios.bin").read_bytes()
server = (v20 / "ioserver.bin").read_bytes()
system = (v20 / "system62.bin").read_bytes()
assert len(bios) <= 0x400
assert len(server) == 0x1800
assert len(system) == 0x1a00
assert system[0x1600:0x1600+len(bios)] == bios
assert bytes.fromhex("ed ed 41 c9") in bios, "missing CALLN/RET"
assert bytes.fromhex("0f ff 40") in server, "missing BRKEM"
for kind, size, system_off, server_off in (
    ("2d", 327680, 0x2000, 0x200),
    ("2hd", 1021696, 0x2700, 0x200),
):
    stem = images / ("fm11-cpm80-v20-" + kind)
    raw = stem.with_suffix(".raw").read_bytes()
    d88 = stem.with_suffix(".d88").read_bytes()
    ipl = (native / ("ipl_" + kind + ".bin")).read_bytes()
    assert len(raw) == size
    assert raw[:len(ipl)] == ipl
    assert raw[server_off:server_off+len(server)] == server
    assert raw[system_off:system_off+len(system)] == system
    assert struct.unpack_from("<I", d88, 0x1c)[0] == len(d88)
    recovered = bytearray()
    pos = 0x2b0
    tracks, sectors = (80, 16) if kind == "2d" else (154, 26)
    for track in range(tracks):
        assert struct.unpack_from("<I", d88, 0x20+4*track)[0] == pos
        length = 128 if kind == "2hd" and track == 0 else 256
        for sector in range(1, sectors+1):
            c,h,r,n,count,density,_,_,_,stored = struct.unpack_from("<BBBBHBBB5sH", d88, pos)
            assert (c,h,r,n,count,density,stored) == (
                track//2, track%2, sector, 0 if length == 128 else 1,
                sectors, 0x40 if length == 128 else 0, length)
            pos += 16
            recovered.extend(d88[pos:pos+length])
            pos += length
    assert pos == len(d88) and recovered == raw
    print("PASS:", kind, "V20 IPL/server/system layout and RAW/D88 equality")
