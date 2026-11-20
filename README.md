# FM-11 CP/M-80

CP/M 2.2 for the Fujitsu FM-11 with the Z80 card.

- 62K system: CCP at DC00h, BDOS entry at E406h, BIOS at F200h.
- Fixed drive letters: A:-D: = 2D units 0-3; E:-H: = 2HD units 0-3, as in FM-11 CP/M-86.
- 2D boots to A:, 2HD boots to E:. Warm boot preserves the current user and drive when available.
- Resident 6809 I/O service, DMA sector reads/writes, write-through cache and physical RESTORE/SEEK.
- Local console and serial console via the native mailbox service; bootable 2D and 2HD D88 and RAW images.

## Build

Requires asm8080 (CCP/BDOS and CBIOS), lwasm (6809), Python 3 and make.
Run `make`. The CCP/BDOS source is adapted from PC-9801 CP/M-80 v1.1;
no external core binary is required. See [docs/build.md](docs/build.md).
Optional COM files in external/commands/ are included in both images.

Experimental 8088+Z80 target: install NASM and run `make image8088`.
See [docs/8088-z80.md](docs/8088-z80.md). The default build is unchanged.

## Boot drive and SUBMIT

BDOS function 13 resets the disk system on the actual boot drive; CCP reads
and deletes the batch file `$$$.SUB` there. Standard SUBMIT.COM creates its
batch file on the current drive: run it from the boot drive, specifying the
input file's drive if necessary (e.g. `E>SUBMIT A:TEST`).

## Source and license

- cpm22/: CCP/BDOS, common 8080 CBIOS, and Z80-specific CPU hooks
- include/8080/: common mailbox ABI definitions
- m6809/: disk IPLs and resident I/O service
- include/: hardware definitions
- tools/: image builders and checks
- docs/: build, hardware and disk documentation

Original FM-11-specific code is covered by LICENSE; CP/M core by LICENSE.CPM.
Original Fujitsu reference disk images are not distributed.
