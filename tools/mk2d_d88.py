#!/usr/bin/env python3
import argparse
import struct
from pathlib import Path

CYLINDERS = 40
HEADS = 2
SECTORS_PER_SIDE = 16
SECTOR_SIZE = 256
RAW_SIZE = CYLINDERS * HEADS * SECTORS_PER_SIDE * SECTOR_SIZE

SYSTEM_CYLINDERS = 2
SYSTEM_SIZE = SYSTEM_CYLINDERS * HEADS * SECTORS_PER_SIDE * SECTOR_SIZE
CYLINDER_SIZE = HEADS * SECTORS_PER_SIDE * SECTOR_SIZE
IPL_SIZE = 0x0200
IOSERVER_OFFSET = IPL_SIZE
IOSERVER_SLOT_SIZE = 0x1000
CPM_SYSTEM_OFFSET = CYLINDER_SIZE
CPM_SYSTEM_SIZE = 0x1A00

BLOCK_SIZE = 2048
TOTAL_BLOCKS = 152          # DPB DSM=151 -> blocks 0..151
DIR_BLOCKS = 2              # DPB AL0=C0h -> blocks 0 and 1
DIR_ENTRIES = 128           # DPB DRM=127
DIR_ENTRY_SIZE = 32
DIR_SIZE = DIR_ENTRIES * DIR_ENTRY_SIZE

EXTENT_BLOCKS = 16          # DSM < 256 -> 16 one-byte allocation entries
RECORD_SIZE = 128

D88_HEADER_SIZE = 0x2B0
D88_TRACK_COUNT = CYLINDERS * HEADS
D88_SECTOR_HEADER_SIZE = 16
D88_TRACK_SIZE = SECTORS_PER_SIDE * (D88_SECTOR_HEADER_SIZE + SECTOR_SIZE)
D88_SIZE = D88_HEADER_SIZE + D88_TRACK_COUNT * D88_TRACK_SIZE

VALID_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#$@!%&'()-^_{}~`")


def cpm_name(path: Path):
    name = path.name.upper()
    if name.count(".") > 1:
        raise ValueError(f"{path.name}: CP/M name must be 8.3")
    if "." in name:
        stem, ext = name.split(".", 1)
    else:
        stem, ext = name, ""
    if not (1 <= len(stem) <= 8) or len(ext) > 3:
        raise ValueError(f"{path.name}: CP/M name must be 8.3")
    if any(ch not in VALID_CHARS for ch in stem + ext):
        raise ValueError(f"{path.name}: unsupported CP/M filename character")
    return stem.ljust(8).encode("ascii"), ext.ljust(3).encode("ascii")


def command_files(directory: Path):
    if not directory.exists():
        return []
    files = [p for p in directory.iterdir()
             if p.is_file() and p.suffix.upper() == ".COM"]
    return sorted(files, key=lambda p: p.name.upper())


def write_cpm_files(raw: bytearray, files):
    next_block = DIR_BLOCKS
    next_dir = 0
    seen = set()

    for path in files:
        n8, e3 = cpm_name(path)
        key = n8 + e3
        if key in seen:
            raise ValueError(f"duplicate CP/M filename: {path.name}")
        seen.add(key)

        data = path.read_bytes()
        blocks_needed = (len(data) + BLOCK_SIZE - 1) // BLOCK_SIZE
        if next_block + blocks_needed > TOTAL_BLOCKS:
            raise ValueError(f"disk full while adding {path.name}")

        blocks = list(range(next_block, next_block + blocks_needed))
        next_block += blocks_needed

        for block in blocks:
            off = SYSTEM_SIZE + block * BLOCK_SIZE
            raw[off:off + BLOCK_SIZE] = b"\x1a" * BLOCK_SIZE
        for i, byte in enumerate(data):
            block_index = i // BLOCK_SIZE
            within = i % BLOCK_SIZE
            off = SYSTEM_SIZE + blocks[block_index] * BLOCK_SIZE + within
            raw[off] = byte

        if not blocks:
            chunks = [([], 0)]
        else:
            chunks = []
            for pos in range(0, len(blocks), EXTENT_BLOCKS):
                chunk_blocks = blocks[pos:pos + EXTENT_BLOCKS]
                chunk_start = pos * BLOCK_SIZE
                chunk_bytes = max(0, min(len(data) - chunk_start,
                                         len(chunk_blocks) * BLOCK_SIZE))
                chunks.append((chunk_blocks, chunk_bytes))

        for physical_extent, (chunk_blocks, chunk_bytes) in enumerate(chunks):
            if next_dir >= DIR_ENTRIES:
                raise ValueError(f"directory full while adding {path.name}")

            chunk_records = (chunk_bytes + RECORD_SIZE - 1) // RECORD_SIZE
            logical_base = physical_extent * 2
            if chunk_records > 128:
                extent_no = logical_base + 1
                rc = chunk_records - 128
            else:
                extent_no = logical_base
                rc = chunk_records

            entry = bytearray(32)
            entry[0] = 0
            entry[1:9] = n8
            entry[9:12] = e3
            entry[12] = extent_no & 0x1F
            entry[13] = 0
            entry[14] = (extent_no >> 5) & 0xFF
            entry[15] = rc & 0xFF
            for i, block in enumerate(chunk_blocks):
                entry[16 + i] = block

            doff = SYSTEM_SIZE + next_dir * DIR_ENTRY_SIZE
            raw[doff:doff + DIR_ENTRY_SIZE] = entry
            next_dir += 1


def make_raw(ipl: bytes, system: bytes, ioserver: bytes, files):
    if len(ipl) > IPL_SIZE:
        raise ValueError(
            f"ipl_2d.bin is {len(ipl)} bytes; maximum is {IPL_SIZE}")
    if len(system) != CPM_SYSTEM_SIZE:
        raise ValueError(
            f"system62.bin is {len(system)} bytes; expected exactly "
            f"{CPM_SYSTEM_SIZE} bytes")
    if len(ioserver) > IOSERVER_SLOT_SIZE:
        raise ValueError(
            f"ioserver.bin is {len(ioserver)} bytes; maximum is "
            f"{IOSERVER_SLOT_SIZE} bytes")
    if IOSERVER_OFFSET + IOSERVER_SLOT_SIZE > CYLINDER_SIZE:
        raise ValueError("internal I/O-server slot exceeds cylinder 0")
    if CPM_SYSTEM_OFFSET + CPM_SYSTEM_SIZE > SYSTEM_SIZE:
        raise ValueError("internal CP/M system image exceeds cylinder 1")

    raw = bytearray(b"\xe5" * RAW_SIZE)

    # OFF=2 reserves cylinders 0 and 1 as a 16 KiB system area.
    # Cylinder 0 is exclusively the 6809 boot environment:
    #   $0000-$01FF  ROM-loaded IPL
    #   $0200-$11FF  resident I/O-server slot (up to $1000 bytes)
    # Cylinder 1 contains the single CP/M system image:
    #   $2000-$39FF  system62.bin -> Z80 physical $DC00-$F5FF
    # The IPL never seeks away from cylinder 0; the resident I/O server loads
    # cylinder 1 after its private mapping is active.
    raw[:SYSTEM_SIZE] = b"\x00" * SYSTEM_SIZE
    raw[:len(ipl)] = ipl
    raw[IOSERVER_OFFSET:IOSERVER_OFFSET + len(ioserver)] = ioserver
    raw[CPM_SYSTEM_OFFSET:CPM_SYSTEM_OFFSET + len(system)] = system

    raw[SYSTEM_SIZE:SYSTEM_SIZE + DIR_SIZE] = b"\xe5" * DIR_SIZE
    write_cpm_files(raw, files)
    return raw


def make_d88(raw: bytes, label: str):
    if len(raw) != RAW_SIZE:
        raise ValueError("internal raw-image size mismatch")

    image = bytearray(D88_SIZE)
    label_bytes = label.encode("ascii", errors="strict")
    if len(label_bytes) > 16:
        raise ValueError("D88 label must be at most 16 ASCII characters")

    image[0:17] = label_bytes + b"\x00" * (17 - len(label_bytes))
    image[0x1A] = 0x00
    image[0x1B] = 0x00             # 2D
    struct.pack_into("<I", image, 0x1C, D88_SIZE)

    out = D88_HEADER_SIZE
    for track_index in range(D88_TRACK_COUNT):
        struct.pack_into("<I", image, 0x20 + track_index * 4, out)
        cyl = track_index // HEADS
        head = track_index % HEADS
        raw_track = track_index * SECTORS_PER_SIDE * SECTOR_SIZE

        for sector_index in range(SECTORS_PER_SIDE):
            sector_no = sector_index + 1
            header = struct.pack(
                "<BBBBHBBB5sH",
                cyl, head, sector_no, 1,
                SECTORS_PER_SIDE,
                0x00, 0x00, 0x00,
                b"\x00" * 5,
                SECTOR_SIZE,
            )
            image[out:out + D88_SECTOR_HEADER_SIZE] = header
            out += D88_SECTOR_HEADER_SIZE

            src = raw_track + sector_index * SECTOR_SIZE
            image[out:out + SECTOR_SIZE] = raw[src:src + SECTOR_SIZE]
            out += SECTOR_SIZE

    if out != D88_SIZE:
        raise ValueError("internal D88 size mismatch")
    return image


def main():
    ap = argparse.ArgumentParser(description="Build an FM-11 CP/M-80 2D D88 image")
    ap.add_argument("--ipl", required=True, type=Path)
    ap.add_argument("--system", required=True, type=Path)
    ap.add_argument("--ioserver", required=True, type=Path)
    ap.add_argument("--commands", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--raw-output", type=Path)
    ap.add_argument("--label", default="FM11 CPM80")
    args = ap.parse_args()

    ipl = args.ipl.read_bytes()
    system = args.system.read_bytes()
    ioserver = args.ioserver.read_bytes()
    files = command_files(args.commands)
    raw = make_raw(ipl, system, ioserver, files)
    d88 = make_d88(raw, args.label)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(d88)
    if args.raw_output:
        args.raw_output.parent.mkdir(parents=True, exist_ok=True)
        args.raw_output.write_bytes(raw)

    print(f"{args.output}: {len(d88)} bytes, {len(files)} command file(s)")
    print(f"ipl: raw offset 0x0000, {len(ipl)} bytes")
    print(f"I/O server: raw offset 0x{IOSERVER_OFFSET:04x}, {len(ioserver)} bytes")
    print(f"CP/M system: raw offset 0x{CPM_SYSTEM_OFFSET:04x}, {len(system)} bytes")
    for path in files:
        print(f"  {path.name}")


if __name__ == "__main__":
    main()
