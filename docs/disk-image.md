# 2D disk image build

`make image` builds a bootable Fujitsu-compatible 2D CP/M disk in D88 format:

```text
build/images/fm11-cpm80-2d.d88
```

For inspection and emulator/debug use, the equivalent raw 320 KiB sector image
is also written as:

```text
build/images/fm11-cpm80-2d.raw
```

## Geometry

```text
40 cylinders
2 heads
16 physical sectors/head
256 bytes/physical sector
320 KiB raw capacity
```

The D88 image uses media type `00h` (2D), 80 formatted track entries, 16
sectors per track entry, and 256-byte sectors.

## Boot/system area

DPB `OFF=2` reserves the first two cylinders, giving a 16 KiB system area at
raw offsets `$0000-$3FFF`.

```text
0000-01FF  stage-1 IPL (ROM loads this to 6809 $0400)
0200-1FFF  position-independent stage-2 loader.bin and zero padding
2000-3FFF  reserved/zero-filled second system cylinder
4000-4FFF  CP/M directory (allocation blocks 0 and 1)
5000-      file data (allocation block 2 onward)
```

The FM-11 ROM loads T0/H0/S1-S2 to `$0400` and jumps there. Stage 1 uses
`$2000` as its stack, then reads only the remaining 30 sectors of cylinder 0,
T0/H0/S3-S16 followed by T0/H1/S1-S16, to `$2600-$43FF` and jumps to `$2600`.

The `$2600` stage-2 start address is part of the boot memory map. Testing showed
that starting the 6809 stage-2 at `$4000` caused unstable execution, while the
same position-independent loader starting below `$4000` booted CP/M through the
CCP prompt and `DIR`. The loaded image is allowed to extend above `$4000`; the
observed restriction applies to its execution start address.

The image builder rejects an IPL larger than `$0200` bytes or a stage-2 image
larger than `$1E00` bytes. This guarantees that the ROM-loaded IPL never needs
to seek away from track 0.

## Adding CP/M commands

Place local command binaries in:

```text
external/commands/
```

Only `.COM` files are imported. Names are converted to upper case and must fit
CP/M 8.3 naming rules. They are installed in user area 0.

The builder implements the current 2D DPB:

```text
BSH=4       2 KiB allocation blocks
EXM=1       up to 32 KiB per physical directory entry
DSM=151     allocation blocks 0..151
DRM=127     128 directory entries
AL0=C0h     directory uses blocks 0 and 1
OFF=2       two reserved cylinders
```

Files larger than 32 KiB are split across multiple CP/M directory extents.
Allocation is deterministic and sequential.
