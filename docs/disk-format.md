# FM-11 CP/M disk formats

Initial compatibility target: Fujitsu FM-11 floppy formats used by the original CP/M-80 system.

## Logical drives

- A:-D: 2D floppy units 0-3, Mini FDC
- E:-H: 2HD floppy units 0-3, Standard FDC
- I: and later: unsupported initially

Bubble memory and HDD support are intentionally outside the first implementation.

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
- 256 bytes per physical sector

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

## Deblocking

CP/M 2.2 uses 128-byte logical sectors while FM-11 floppy sectors are 256 bytes.  The 6809 I/O service performs deblocking.

For 2D, one side contains 32 CP/M records.  For 2HD, one side contains 52 CP/M records.

Conceptually:

```
side = logical_sector / records_per_side
r = logical_sector % records_per_side
physical_sector = (r / 2) + 1
half = r & 1
```

`half=0` selects bytes 0-127 of the physical sector and `half=1` selects bytes 128-255.

The exact FDC sector numbering is kept in the 6809 low-level driver so the CP/M-facing BIOS remains independent of controller details.
