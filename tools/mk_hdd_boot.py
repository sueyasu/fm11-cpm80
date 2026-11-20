#!/usr/bin/env python3
"""Build a whole-HDD FM-11 CP/M-80 boot disk. Adapted from fm11-cpm86 (MIT)."""
import argparse
import math
from pathlib import Path
from mk2d_d88 import cpm_name, command_files
from mk_hdd_data import MODELS

SECTOR = 256
SPT = 32
BLOCK = 16384
DIRECTORY_ENTRIES = 512
DIRECTORY_BYTES = DIRECTORY_ENTRIES * 32
RECORD = 128
SERVER_SIZE = 0x1800
SYSTEM_SIZE = 0x1A00
RESIDENT_SIZE = SERVER_SIZE + SYSTEM_SIZE
ALLOCATIONS_PER_ENTRY = 8    # DSM > 255: eight 16-bit pointers
RECORDS_PER_ENTRY = ALLOCATIONS_PER_ENTRY * BLOCK // RECORD
ERASED = 0xE5


def build_image(model: str, ipl: bytes, server: bytes, system: bytes, files=()) -> bytes:
    cylinders, heads = MODELS[model]
    size = cylinders * heads * SPT * SECTOR
    reserved = heads * SPT * SECTOR
    if len(ipl) != 512 or len(server) != SERVER_SIZE or len(system) != SYSTEM_SIZE:
        raise ValueError("IPL must be 512, server 0x1800, system 0x1a00 bytes")
    if ipl[0] != 0xFA or server[0] != 0xFA or system[0] != 0xc3 or system[0x1600] != 0xc3:
        raise ValueError("invalid HDD IPL, native server or CP/M signature")
    if reserved < 512 + RESIDENT_SIZE:
        raise ValueError("HDD reserved cylinder too small")
    total_blocks = (size-reserved)//BLOCK
    if not 256 < total_blocks < 65536:
        raise ValueError("DSM must use two-byte allocation pointers")
    # Disk initialized in E5, which is a valid empty CP/M directory.
    image = bytearray([ERASED]) * size
    image[:512] = ipl
    image[512:512+RESIDENT_SIZE] = server + system
    seen = set()
    block_index = 1
    entry_index = 0
    for path in files:
        path = Path(path)
        stem, ext = cpm_name(path)
        name = stem+ext
        if name in seen:
            raise ValueError(f"{path}: duplicate CP/M filename")
        seen.add(name)
        data = path.read_bytes()
        records_total = math.ceil(len(data)/RECORD)
        if records_total > 65536:
            raise ValueError(f'{path}: exceeds CP/M 2.2 file limit')
        records_left = records_total
        cursor = 0
        extent_base = 0
        while records_left or extent_base == 0:
            if entry_index >= DIRECTORY_ENTRIES:
                raise ValueError(f"{path}: HDD directory full")
            records = min(records_left, RECORDS_PER_ENTRY)
            used_bytes = min(len(data)-cursor, records*RECORD)
            used_blocks = math.ceil(used_bytes/BLOCK)
            if block_index + used_blocks > total_blocks:
                raise ValueError(f"{path}: HDD full")
            entry = bytearray(32)
            entry[0] = 0
            entry[1:9] = stem
            entry[9:12] = ext
            subextent = (records-1)//128 if records else 0
            logical_extent = extent_base+subextent
            entry[12] = logical_extent & 31
            entry[13] = 0
            entry[14] = (logical_extent>>5)&63
            entry[15] = records - 128*subextent
            for j in range(used_blocks):
                dest = reserved + (block_index+j)*BLOCK
                chunk = data[cursor:cursor+BLOCK]
                image[dest:dest+BLOCK] = chunk.ljust(BLOCK, bytes([0x1a]))
                entry[16+j*2:18+j*2] = (block_index+j).to_bytes(2, "little")
                cursor += len(chunk)
            d = reserved + entry_index*32
            image[d:d+32] = entry
            block_index += used_blocks
            records_left -= records
            extent_base += 8
            entry_index += 1
    return bytes(image)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", choices=MODELS, default="m2233b")
    parser.add_argument("--ipl", type=Path, required=True)
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--system", type=Path, required=True)
    parser.add_argument("--commands", type=Path, required=True)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    files = command_files(args.commands)
    data = build_image(args.model, args.ipl.read_bytes(), args.server.read_bytes(),
                       args.system.read_bytes(), files)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('xb') as f:
        f.write(data)
    print(f"{args.output}: {len(data)} bytes; model={args.model}, "
          f"{len(files)} CP/M file(s), boot drive I:")


if __name__ == "__main__":
    main()
