# FORMAT physical disk API

One new JMP vector follows CACHE_SYNC (F233h) and CACHE_RESET (F236h):
RAW_DISK_API at F239h (BIOS base + 39h). Standard 17 vectors and the
existing extensions are unchanged. Use the WBOOT vector at page zero
to discover the BIOS base, not a fixed address, in utilities.
A=operation (07h..0Bh), CALL RAW_DISK_API; returns A=0/Z=1 success or
A=1/Z=0 failure. BC/DE/HL and SP preserved; other flags unspecified.
The utility populates the existing ten-byte mailbox before the call.
The API does not change CBIOS selected drive/track/sector/DMA.
It is synchronous and non-reentrant. Do not use alongside other
disk activity. It is not a standard CP/M 2.2 interface.

| Address | Input |
|---|---|
| FBF8 | drive 0..8 |
| FBFA-FBFB | 16-bit side-track, big-endian (FDD cylinder*2+head) |
| FBFC-FBFD | 16-bit physical sector, big-endian, **1-based** |
| FBFE-FBFF | 16-bit guest buffer address, big-endian |

| A | Operation | Details |
|---|---|---|
| 07h | GET_GEOMETRY | input drive and side-track; output TRACK=total side-tracks, SECTOR_H=physical sectors/side-track, SECTOR_L=N (0=128,1=256 bytes), DATA=heads |
| 08h | PHYS_READ | read one complete physical sector |
| 09h | PHYS_WRITE | write one complete physical sector |
| 0Ah | FORMAT_TRACK | FDD only, caller supplies complete WD17xx WRITE TRACK byte stream; sector ignored |
| 0Bh | GET_CPU_TYPE | DATA=0 (6809+Z80), 1 (8088+Z80), 2 (V20); no disk fields required |

GET_GEOMETRY on FDD returns fixed format geometry, not a media presence
test. HDD geometry is obtained by SENSE. Query track 0 separately for
2HD mixed sector size. All track numbers are absolute (reserved area
included). HDD sector 1 is LBA track*32. The native backend translates
the 1-based API sector to the 0-based MDC LBA.

| Format | Side-tracks | Sectors/side | Sector bytes | WRITE TRACK DMA length |
|---|---:|---:|---:|---:|
| 2D | 80 | 16 | 256 | 6400 |
| 2HD track 0 | 154 | 26 | 128 | 10900 |
| 2HD other | 154 | 26 | 256 | 10900 |
| HDD | model-dependent | 32 | 256 | unsupported |

WRITE TRACK stream generation belongs to FORMAT.COM in commit 5;
use the same FE/CHRN/F7, FB/data/F7 format as CP/M-86 FORMAT.
The caller must provide the full stated byte count, with appropriate
CHRN, gaps and sector sizes (including special 2HD track 0).
Buffers must be entirely within 0100h..DBFFh, without wrap.
No BIOS memory, stack, page-zero or mailbox DMA is permitted.
FDD DMA operates directly on guest RAM (bank 0 on 6809, bank 1
on 8088/V20); HDD uses the native MDC transport.

Before each raw transfer, the server validates parameters, flushes
all dirty cache sectors and invalidates the cache. A failed flush
aborts the raw operation. Raw transfers bypass the cache and propagate
controller or DMA failures. No automatic verification of written data.
After changing the filesystem, the utility must reset BDOS disk state
(function 13 or WBOOT); raw I/O cannot repair BDOS allocation vectors
or open FCBs. Do not format the boot drive while running from it.
The caller is responsible for confirming destructive operations.

## Build and validation

make test-raw-api builds all three BIOS/server variants and verifies
the assembled jump table and operation range check. Actual controller
I/O tests are separate. FORMAT.COM and its boot-system installation
logic are not included in this commit.
