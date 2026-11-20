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

Both images are bootable. A:–D: always map to 2D FDDs and E:–H:
always map to 2HD FDDs, regardless of the boot medium. I: is the HDD.

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
0200-19FF  6809 I/O-server slot -> physical $10000-$117FF
1A00-1FFF  reserved/zero padding
2000-39FF  system62.bin -> Z80 physical $DC00-$F5FF
3A00-3FFF  reserved/zero padding
4000-4FFF  CP/M directory (allocation blocks 0 and 1)
5000-      file data (allocation block 2 onward)
```

For the default `make image` target, cylinder 0 contains the 6809
boot environment; 8088/V20 images contain their corresponding native
server instead. The ROM-loaded
IPL stays on cylinder 0 and loads T0/H0/S3-S16 and T0/H1/S1-S10,
the 24-sector I/O-server slot. The IPL never performs a SEEK or STEP.

After the resident I/O server is running from private RAM, it initializes the
Mini FDC, moves to cylinder 1, and loads `system62.bin` from T1/H0/S1 onward.
`system62.bin` is exactly `$1A00` bytes: `$1600` bytes of CCP+BDOS followed by
a BIOS slot padded to `$0400` bytes.

Cold boot reads all 26 physical sectors from the cylinder-1 image to Z80
physical `$DC00-$F5FF`. WBOOT uses the same image and reads only the first 22
physical sectors to restore CCP+BDOS at `$DC00-$F1FF`; BIOS remains resident.
There is no duplicate warm-boot system copy.

The 2D image builder rejects an IPL larger than `$0200`, a system payload whose
size is not exactly `$1A00`, or an I/O server larger than `$1800`.

The 2D DPB is:

```text
BSH=4       2 KiB allocation blocks
EXM=1       up to 32 KiB per physical directory entry
DSM=151     allocation blocks 0..151
DRM=127     128 directory entries
AL0=C0h     directory uses blocks 0 and 1
OFF=2       two reserved cylinders
```

## 2HD boot image

77 cylinders, two heads, 26 sectors per head. T0/H0 uses 128-byte
single-density sectors; all other tracks use 256-byte sectors.
The D88 media type is 20h. DPB OFF=2 reserves cylinders 0 and 1.

```text
00000-001FF  IPL (T0/H0/S1-S4)
00200-00CFF  I/O server first 0B00h bytes (T0/H0/S5-S26)
00D00-019FF  I/O server remaining 0D00h bytes (T0/H1/S1-S13)
01A00-026FF  reserved/zero padding
02700-040FF  system62.bin (T1/H0/S1-S26)
04100-05AFF  reserved/zero padding
05B00-06AFF  CP/M directory (allocation block 0)
06B00-       file data (allocation block 1 onward)
```

Normal disk I/O begins at cylinder 2 and does not touch the mixed-density
boot track. Standard FDC uses DMA channel 1 with 256-byte physical sectors.

The 2HD DPB is:

```text
BSH=5       4 KiB allocation blocks
EXM=3       up to 64 KiB per physical directory entry
DSM=242     allocation blocks 0..242
DRM=127     128 directory entries
AL0=80h     directory uses block 0
OFF=2       two reserved cylinders
```

## Other CPU variants and HDD images

Use `make image8088` for 8088+Z80 or `make imagev20` for NEC V20.
Both create corresponding 2D/2HD D88 and RAW images with the same disk
layout. Use `make imagehdd`, `make image8088-hdd` or `make imagev20-hdd`
for whole-HDD images; see [boot-hdd.md](boot-hdd.md). All boot variants
use the original FM-11 ROM.

## Adding CP/M commands

Place local command binaries in:

```text
external/commands/
```

Only `.COM` files are imported. Names are converted to upper case and must fit
CP/M 8.3 naming rules. They are installed in user area 0 of both generated
images. Allocation is deterministic and sequential.
