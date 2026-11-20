#!/usr/bin/env python3
"""Validate RAW_DISK_API vector and operation-range check in all BIOS builds."""
import sys
from pathlib import Path
for name in sys.argv[1:]:
    data = Path(name).read_bytes()
    assert len(data) <= 0x400
    for off in range(0,0x3c,3):
        assert data[off] == 0xc3, (name,off)
        target = int.from_bytes(data[off+1:off+3],"little") - 0xf200
        assert 0 <= target < len(data), (name,off,target)
    target = int.from_bytes(data[0x3a:0x3c],"little") - 0xf200
    assert data[target:target+3] == bytes([0xfe,7,0xda])
    assert data[target+5:target+8] == bytes([0xfe,12,0xda])
    print(f"PASS: {name}: RAW_DISK_API F239h")
