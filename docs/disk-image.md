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

The system image is stored only once and follows the current RAM layout directly:

```text
0000-01FF  IPL (ROM loads this to 6809 $0400)
0200-1BFF  system56.bin -> Z80 $C400-$DDFF
1C00-29FF  6809 I/O-server slot -> $DE00-$EBFF
2A00-3FFF  reserved/zero padding
4000-4FFF  CP/M directory (allocation blocks 0 and 1)
5000-      file data (allocation block 2 onward)
```

`system56.bin` is exactly `$1A00` bytes. The I/O-server slot is fixed at
`$0E00` bytes; the actual `ioserver.bin` is followed by zero padding. Therefore
the IPL can load one fixed 40-sector stream from raw `$0200-$29FF` directly to
RAM `$C400-$EBFF`.

The FM-11 ROM loads T0/H0/S1-S2 to `$0400` and jumps there. The IPL begins its
direct load at T0/H0/S3. The first 30 sectors finish cylinder 0 and the final
10 sectors are T1/H0/S1-S10. A real WD17xx SEEK is issued when the load crosses
the cylinder boundary.

There is no stage-2 loader and no separate warm-boot copy of the CP/M system.
WBOOT reuses the same system image and reloads only CCP+BDOS (`$1600` bytes,
22 physical sectors) from raw `$0200-$17FF` to Z80 `$C400-$D9FF`. BIOS and the
resident 6809 I/O server remain resident.

The image builder rejects an IPL larger than `$0200`, a `system56.bin` whose
size is not exactly `$1A00`, or an I/O server larger than its current `$0E00`
RAM slot.

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
