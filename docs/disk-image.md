# 2D disk image build

`make image` builds a Fujitsu-compatible 2D CP/M disk in D88 format:

```text
build/images/fm11-cpm80-2d.d88
```

For inspection and emulator/debug use, the equivalent raw 320 KiB sector image
is also written as:

```text
build/images/fm11-cpm80-2d.raw
```

## Geometry

The image uses the format described by the 2D DPB in the BIOS:

```text
40 cylinders
2 heads
16 physical sectors/head
256 bytes/physical sector
320 KiB raw capacity
```

The D88 image uses media type `00h` (2D), 80 formatted track entries, 16
sectors per track entry, and 256-byte sectors.

## Reserved system area

The first two cylinders are reserved by DPB `OFF=2`, giving a 16 KiB system
area at raw offsets `0000h-3FFFh`.

```text
0000-01FF  reserved for the stage-1 IPL (not implemented yet)
0200-3FFF  position-independent stage-2 loader.bin
4000-4FFF  CP/M directory (allocation blocks 0 and 1)
5000-      file data (allocation block 2 onward)
```

The D88 builder rejects a stage-2 image larger than `3E00h` bytes.

Because stage 1 has not yet been implemented, the D88 produced by this commit
contains a valid CP/M filesystem and the stage-2 payload but is **not yet
bootable**.  The next boot-track step will fill the reserved first `0200h`
bytes and load stage 2 from the remaining reserved system sectors.

## Adding CP/M commands

Place local command binaries in:

```text
external/commands/
```

Only `.COM` files are imported.  Names are converted to upper case and must fit
CP/M 8.3 naming rules.  They are installed in user area 0.

The builder implements the current 2D DPB exactly:

```text
BSH=4       2 KiB allocation blocks
EXM=1       up to 32 KiB per physical directory entry
DSM=151     allocation blocks 0..151
DRM=127     128 directory entries
AL0=C0h     directory uses blocks 0 and 1
OFF=2       two reserved cylinders
```

Files larger than 32 KiB are split across multiple CP/M directory extents.
Allocation is currently deterministic and sequential, which is sufficient for
building fresh system disks.
