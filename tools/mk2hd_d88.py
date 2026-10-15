#!/usr/bin/env python3
import argparse
import struct
from pathlib import Path

CYLINDERS = 77
HEADS = 2
SECTORS_PER_SIDE = 26
BOOT_SECTOR_SIZE = 128
SECTOR_SIZE = 256

# FM-11 2HD uses the IBM-style special boot track: only T0/H0 is
# single-density 26 x 128 bytes.  All other tracks are 26 x 256 bytes.
BOOT_TRACK_BYTES = SECTORS_PER_SIDE * BOOT_SECTOR_SIZE
NORMAL_TRACK_BYTES = SECTORS_PER_SIDE * SECTOR_SIZE
RAW_SIZE = BOOT_TRACK_BYTES + (CYLINDERS * HEADS - 1) * NORMAL_TRACK_BYTES

IPL_SECTORS = 4
IPL_SIZE = IPL_SECTORS * BOOT_SECTOR_SIZE
IOSERVER_SECTORS = 16
IOSERVER_SIZE = IOSERVER_SECTORS * BOOT_SECTOR_SIZE
IOSERVER_OFFSET = IPL_SIZE

# T1/H0 begins after T0/H0 (128-byte sectors) and T0/H1 (256-byte sectors).
SYSTEM_OFFSET = BOOT_TRACK_BYTES + NORMAL_TRACK_BYTES
SYSTEM_SIZE = SECTORS_PER_SIDE * SECTOR_SIZE

# CP/M OFF=2: directory/data start at cylinder 2.
DATA_OFFSET = BOOT_TRACK_BYTES + 3 * NORMAL_TRACK_BYTES

BLOCK_SIZE = 4096
TOTAL_BLOCKS = 243          # DPB DSM=242 -> blocks 0..242
DIR_BLOCKS = 1              # DPB AL0=80h -> block 0
DIR_ENTRIES = 128           # DPB DRM=127
DIR_ENTRY_SIZE = 32
DIR_SIZE = DIR_ENTRIES * DIR_ENTRY_SIZE

EXTENT_BLOCKS = 16
EXTENT_MASK = 3
RECORD_SIZE = 128

D88_HEADER_SIZE = 0x2B0
D88_TRACK_COUNT = CYLINDERS * HEADS
D88_SECTOR_HEADER_SIZE = 16

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
            off = DATA_OFFSET + block * BLOCK_SIZE
            raw[off:off + BLOCK_SIZE] = b"\x1a" * BLOCK_SIZE
        for i, byte in enumerate(data):
            block_index = i // BLOCK_SIZE
            within = i % BLOCK_SIZE
            off = DATA_OFFSET + blocks[block_index] * BLOCK_SIZE + within
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
            logical_base = physical_extent * (EXTENT_MASK + 1)
            if chunk_records == 0:
                logical_in_entry = 0
                rc = 0
            else:
                logical_in_entry = min((chunk_records - 1) // 128, EXTENT_MASK)
                rc = chunk_records - logical_in_entry * 128
            extent_no = logical_base + logical_in_entry

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

            doff = DATA_OFFSET + next_dir * DIR_ENTRY_SIZE
            raw[doff:doff + DIR_ENTRY_SIZE] = entry
            next_dir += 1


def fit(data: bytes, limit: int, name: str):
    if len(data) > limit:
        raise ValueError(f"{name}: {len(data)} bytes exceeds {limit}-byte slot")
    return data + b"\x00" * (limit - len(data))


def make_raw(ipl: bytes, system: bytes, ioserver: bytes, files):
    raw = bytearray(b"\xe5" * RAW_SIZE)

    # Reserved cylinders 0-1.  The exact mixed-density byte stream is kept in
    # the raw image so D88 conversion can preserve 128-byte T0/H0 sectors.
    raw[:DATA_OFFSET] = b"\x00" * DATA_OFFSET
    raw[0:IPL_SIZE] = fit(ipl, IPL_SIZE, "2HD IPL")
    raw[IOSERVER_OFFSET:IOSERVER_OFFSET + IOSERVER_SIZE] = fit(
        ioserver, IOSERVER_SIZE, "I/O server")
    raw[SYSTEM_OFFSET:SYSTEM_OFFSET + SYSTEM_SIZE] = fit(
        system, SYSTEM_SIZE, "CP/M system")

    raw[DATA_OFFSET:DATA_OFFSET + DIR_SIZE] = b"\xe5" * DIR_SIZE
    write_cpm_files(raw, files)
    return raw


def sector_size(cyl, head):
    return BOOT_SECTOR_SIZE if cyl == 0 and head == 0 else SECTOR_SIZE


def make_d88(raw: bytes, label: str):
    if len(raw) != RAW_SIZE:
        raise ValueError("internal raw-image size mismatch")

    label_bytes = label.encode("ascii", errors="strict")
    if len(label_bytes) > 16:
        raise ValueError("D88 label must be at most 16 ASCII characters")

    track_sizes = []
    for track_index in range(D88_TRACK_COUNT):
        cyl = track_index // HEADS
        head = track_index % HEADS
        size = sector_size(cyl, head)
        track_sizes.append(SECTORS_PER_SIDE * (D88_SECTOR_HEADER_SIZE + size))
    d88_size = D88_HEADER_SIZE + sum(track_sizes)

    image = bytearray(d88_size)
    image[0:17] = label_bytes + b"\x00" * (17 - len(label_bytes))
    image[0x1A] = 0x00
    image[0x1B] = 0x20             # 2HD
    struct.pack_into("<I", image, 0x1C, d88_size)

    out = D88_HEADER_SIZE
    src = 0
    for track_index in range(D88_TRACK_COUNT):
        struct.pack_into("<I", image, 0x20 + track_index * 4, out)
        cyl = track_index // HEADS
        head = track_index % HEADS
        size = sector_size(cyl, head)
        n = 0 if size == 128 else 1
        density = 0x40 if size == 128 else 0x00

        for sector_no in range(1, SECTORS_PER_SIDE + 1):
            header = struct.pack(
                "<BBBBHBBB5sH",
                cyl, head, sector_no, n,
                SECTORS_PER_SIDE,
                density, 0x00, 0x00,
                b"\x00" * 5,
                size,
            )
            image[out:out + D88_SECTOR_HEADER_SIZE] = header
            out += D88_SECTOR_HEADER_SIZE
            image[out:out + size] = raw[src:src + size]
            out += size
            src += size

    if src != RAW_SIZE or out != d88_size:
        raise ValueError("internal D88 size mismatch")
    return image


def main():
    ap = argparse.ArgumentParser(
        description="Build a bootable FM-11 CP/M-80 2HD D88 image")
    ap.add_argument("--ipl", required=True, type=Path)
    ap.add_argument("--system", required=True, type=Path)
    ap.add_argument("--ioserver", required=True, type=Path)
    ap.add_argument("--commands", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--raw-output", type=Path)
    ap.add_argument("--label", default="FM11 CPM80 2HD")
    args = ap.parse_args()

    files = command_files(args.commands)
    raw = make_raw(args.ipl.read_bytes(), args.system.read_bytes(),
                   args.ioserver.read_bytes(), files)
    d88 = make_d88(raw, args.label)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(d88)
    if args.raw_output:
        args.raw_output.parent.mkdir(parents=True, exist_ok=True)
        args.raw_output.write_bytes(raw)

    print(f"{args.output}: {len(d88)} bytes, {len(files)} command file(s)")
    print("boot track: T0/H0 = 26 x 128-byte single-density sectors")
    print("  S1-S4  : 2HD IPL")
    print("  S5-S20 : resident 6809 I/O server")
    print("system: T1/H0/S1-S26 = system62.bin")
    print(f"directory: raw 0x{DATA_OFFSET:04x}-0x{DATA_OFFSET + DIR_SIZE - 1:04x}")
    for path in files:
        print(f"  {path.name}")


if __name__ == "__main__":
    main()
