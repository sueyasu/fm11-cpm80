#!/usr/bin/env python3
"""Structural asset and reserved-area layout regression."""
import sys
from pathlib import Path

com = Path(sys.argv[1]).read_bytes()
assets = [Path(p).read_bytes().ljust(512, b"\0") for p in sys.argv[2:]]
assert len(assets) == 6
blob = b"".join(assets)
assert blob in com, "missing/reordered IPL assets"
start = com.index(blob)
# Workspace starts after assets: saved sector, track stream, system, stack.
assert 0x100 + start + len(blob) + 256 + 10900 + 12800 + 256 <= 0xdc00
# Model the same sector advance sequence used by FORMAT.
for kind in ("2d", "2hd", "hdd"):
    spt = {"2d":16, "2hd":26, "hdd":32}[kind]
    def offset(t,s):
        if kind == "2hd":
            return (s-1)*128 if t == 0 else 26*128+(t-1)*26*256+(s-1)*256
        return (t*spt+s-1)*256
    def span(t,s,n):
        first = offset(t,s)
        pos = first
        while n:
            size = 128 if kind == "2hd" and t == 0 else 256
            assert n >= size and offset(t,s) == pos
            n -= size
            pos += size
            s += 1
            if s > spt:
                t,s=t+1,1
        return first,pos
    assert span(0,1,512)==(0,512)
    assert span(0,5 if kind=="2hd" else 3,6144)==(512,6656)
    t,s=(0,27) if kind=="hdd" else (2,1)
    off={"2d":8192,"2hd":9984,"hdd":6656}[kind]
    assert span(t,s,6656)==(off,off+6656)
print("PASS: FORMAT.COM IPL assets, TPA workspace and three boot layouts")
