# FM-11 CP/M disk formats

FM-11 CP/M-80 disk layouts for 6809+Z80, 8088+Z80 and NEC V20.
All three configurations share the same 2D, 2HD and HDD filesystem formats.

## Logical drives

- A:-D: 2D floppy units 0-3, Mini FDC
- E:-H: 2HD floppy units 0-3, Standard FDC
- I: one whole MDC HDD (no partitions)

These assignments do not depend on the boot medium: 2D starts at A: and 2HD starts at E:.

Bubble memory is not supported. The standard ROM can boot 2D, 2HD or HDD;
the initial drive is A:, E: or I:.

## 2D

Physical geometry:

- 40 cylinders
- 2 sides
- 16 physical sectors per side
- 256 bytes per physical sector

CP/M DPB:

- SPT = 64 (128-byte records per cylinder)
- BSH = 4
- BLM = 15
- EXM = 1
- DSM = 151
- DRM = 127
- AL0 = C0h
- AL1 = 00h
- CKS = 32
- OFF = 2

Allocation block size is 2 KiB.

## 2HD

Physical geometry:

- 77 cylinders
- 2 sides
- 26 physical sectors per side
- 128-byte sectors on cylinder 0/head 0, and 256-byte sectors elsewhere

CP/M DPB:

- SPT = 104
- BSH = 5
- BLM = 31
- EXM = 3
- DSM = 242
- DRM = 127
- AL0 = 80h
- AL1 = 00h
- CKS = 32
- OFF = 2

Allocation block size is 4 KiB.

## HDD (I:)

The whole MDC HDD is used as one CP/M volume. Supported models are M2230B,
M2231B, M2232B, M2233B, M2234B, M2235B, M2241B, M2242B and M2243B.
SENSE determines geometry. The first cylinder is reserved for the boot system.

- 32 physical 256-byte sectors per side-track; 64 CP/M records per track
- 16 KiB allocation blocks: BSH=7, BLM=127, EXM=7
- DRM=511, AL0=80h, AL1=00h, CKS=0
- OFF=heads, DSM=floor((cylinders-1)*heads/2)-1

The BDOS uses 24-bit relative record arithmetic for disks larger than 8 MiB.
Some legacy utilities may still report capacity incorrectly; see
[hdd-data.md](hdd-data.md).

## Deblocking

CP/M 2.2 uses 128-byte logical sectors while FM-11 floppy sectors are 256 bytes.  The native 6809/8088/V20 I/O services perform deblocking.

For 2D, one side contains 32 CP/M records.  For 2HD, one side contains 52 CP/M records.

Conceptually:

```
side = logical_sector / records_per_side
r = logical_sector % records_per_side
physical_sector = (r / 2) + 1
half = r & 1
```

`half=0` selects bytes 0-127 of the physical sector and `half=1` selects bytes 128-255.

FDC/MDC hardware addressing remains in native drivers, not in the common
CBIOS. The 2HD 128-byte boot track is outside the filesystem data area.
See [disk-image.md](disk-image.md) and [format-api.md](format-api.md).
