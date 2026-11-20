#!/usr/bin/env python3
"""Check both assembled CBIOS extension vectors and mailbox command ABI."""
from pathlib import Path

BASE = 0xF200
for path in (Path("build/z80/bios.bin"), Path("build/i8086/bios.bin")):
    bios = path.read_bytes()
    assert len(bios) <= 0x400, path
    for off in range(0, 19 * 3, 3):
        assert bios[off] == 0xC3, (path, off)
        dest = int.from_bytes(bios[off+1:off+3], "little") - BASE
        assert 0 <= dest < len(bios), (path, off, dest)
    targets = []
    for off, cmd in ((0x33, 4), (0x36, 5)):
        dest = int.from_bytes(bios[off+1:off+3], "little") - BASE
        assert bios[dest:dest+3] == bytes([0x3e, cmd, 0xc3]), (path, off)
        targets.append(int.from_bytes(bios[dest+3:dest+5], "little"))
    assert targets[0] == targets[1], path
    assert BASE <= targets[0] < BASE + len(bios), path
    print(f"PASS: {path}: CACHE_SYNC F233h, CACHE_RESET F236h")
