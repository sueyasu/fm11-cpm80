# Disk image build

`make image` builds two D88 images:

```text
build/images/fm11-cpm80-2d.d88
build/images/fm11-cpm80-2hd.d88
```

Equivalent raw sector images are also written as:

```text
build/images/fm11-cpm80-2d.raw
build/images/fm11-cpm80-2hd.raw
```

The 2D image is the current bootable system disk. The 2HD image is a formatted
non-bootable data disk prepared for the existing 2HD DPB; 2HD boot and runtime
Standard-FDC read/write support are intentionally not part of this stage.

## 2D geometry

```text
40 cylinders
2 heads
16 physical sectors/head
256 bytes/physical sector
320 KiB raw capacity
```

The D88 image uses media type `00h` (2D), 80 formatted track entries, 16
sectors per track entry, and 256-byte sectors.

### 2D boot/system area

DPB `OFF=2` reserves the first two cylinders, giving a 16 KiB system area at
raw offsets `$0000-$3FFF`.

The active system layout is:

```text
0000-01FF  IPL (ROM loads this to 6809 $0400)
0200-09FF  6809 I/O-server slot -> physical $10000-$107FF
0A00-1FFF  reserved/zero padding
2000-39FF  system62.bin -> Z80 physical $DC00-$F5FF
3A00-3FFF  reserved/zero padding
4000-4FFF  CP/M directory (allocation blocks 0 and 1)
5000-      file data (allocation block 2 onward)
```

Cylinder 0 is therefore exclusively the 6809 boot environment. The ROM-loaded
IPL stays on cylinder 0 and loads only T0/H0/S3-S10, the eight-sector I/O-server
slot. The IPL never performs a SEEK or STEP.

After the resident I/O server is running from private RAM, it initializes the
Mini FDC, moves to cylinder 1, and loads `system62.bin` from T1/H0/S1 onward.
`system62.bin` is exactly `$1A00` bytes: `$1600` bytes of CCP+BDOS followed by
a BIOS slot padded to `$0400` bytes.

Cold boot reads all 26 physical sectors from the cylinder-1 image to Z80
physical `$DC00-$F5FF`. WBOOT uses the same image and reads only the first 22
physical sectors to restore CCP+BDOS at `$DC00-$F1FF`; BIOS remains resident.
There is no duplicate warm-boot system copy.

The 2D image builder rejects an IPL larger than `$0200`, a system payload whose
size is not exactly `$1A00`, or an I/O server larger than `$0800`.

The 2D DPB is:

```text
BSH=4       2 KiB allocation blocks
EXM=1       up to 32 KiB per physical directory entry
DSM=151     allocation blocks 0..151
DRM=127     128 directory entries
AL0=C0h     directory uses blocks 0 and 1
OFF=2       two reserved cylinders
```

## 2HD data image

The generated 2HD image uses the geometry already described by the BIOS DPB:

```text
77 cylinders
2 heads
26 physical sectors/head
256 bytes/physical sector
raw size = $FA400 bytes
```

The D88 image uses media type `20h` (2HD), 154 formatted track entries, 26
sectors per track entry, and 256-byte sectors.

DPB `OFF=2` reserves cylinders 0 and 1, giving a `$6800`-byte system area. The
current 2HD image is deliberately non-bootable, so that area is zero-filled:

```text
00000-067FF  reserved system area
06800-077FF  CP/M directory (allocation block 0)
07800-       file data (allocation block 1 onward)
```

The 2HD DPB is:

```text
BSH=5       4 KiB allocation blocks
EXM=3       up to 64 KiB per physical directory entry
DSM=242     allocation blocks 0..242
DRM=127     128 directory entries
AL0=80h     directory uses block 0
OFF=2       two reserved cylinders
```

## Adding CP/M commands

Place local command binaries in:

```text
external/commands/
```

Only `.COM` files are imported. Names are converted to upper case and must fit
CP/M 8.3 naming rules. They are installed in user area 0 of both generated
images. Allocation is deterministic and sequential.
