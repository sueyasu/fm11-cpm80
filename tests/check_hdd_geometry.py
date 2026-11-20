#!/usr/bin/env python3
"""Exercise the BDOS 24-bit / 8-bit division model and HDD geometry bounds."""
from mk_hdd_data import MODELS

def div24(record, spt):
    q = record & 0xffff
    r = record >> 16
    for _ in range(16):
        r = (r << 1) | (q >> 15)
        q = (q << 1) & 0xffff
        if r >= spt:
            r -= spt
            q += 1
    return q, r

for model, (cyl, heads) in MODELS.items():
    blocks = (cyl - 1)*heads//2
    assert 256 < blocks <= 4103
    assert (blocks+7)//8 <= 513
    for record in range(blocks*128):
        track, sector = div24(record, 64)
        assert (track, sector) == divmod(record, 64)
        assert heads+track < cyl*heads
    print("PASS:", model, "DSM", blocks-1, "OFF", heads)
for spt, tracks in ((64, 78), (104, 75)):
    for record in range(spt*tracks):
        assert div24(record, spt) == divmod(record, spt)
print("PASS: floppy relative-record division")
