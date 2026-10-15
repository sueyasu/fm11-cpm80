# FM-11 CP/M-80

Open-source BIOS, boot and I/O support for running CP/M-80 on the Fujitsu FM-11 with the Z80 card.

## Initial target

- CP/M 2.2, Fujitsu-style 56K system layout
- CCP at `$C400`, BDOS at `$CC00`, BIOS at `$DA00`
- A: through D: = 2D floppy drives 0 through 3
- E: through H: = 2HD floppy drives 0 through 3
- No HDD or bubble-memory support initially
- Z80 BIOS with a resident 6809 I/O service for floppy access
- synchronous Z80/6809 mailbox protocol using `$FD05` CPU hand-off

The implementation follows the FM-11 hardware architecture and Fujitsu disk formats where useful, without requiring binary compatibility with Fujitsu's original CP/M implementation.

## Build tools

- `z80asm` for Z80 sources
- `lwasm` (LWTOOLS) for MC6809 sources
- Python 3 and make

See [docs/build.md](docs/build.md) for setup and the required external CCP+BDOS image.

The CP/M CCP+BDOS binary is intentionally not kept in Git. The current build expects a locally supplied **56K** core at `external/cpm22/ccpbdos56.bin`; a normal 62K image overlaps the resident 6809 I/O-service area and is therefore not suitable for this initial port.

Optional CP/M `.COM` files can be placed in `external/commands/`; `make image` installs them into the generated 2D filesystem.

## Current status

The repository contains:

- `z80asm`-compatible CP/M 2.2 BIOS and disk structures
- direct standard-8251 console routines
- Fujitsu-compatible DPH/DPB definitions for 2D and 2HD
- A:-H: logical drive mapping
- Z80/6809 mailbox definitions at `$EC00`
- resident 6809 I/O-service dispatcher at `$DE00`
- functional Mini FDC PIO READ path for A:-D: 2D drives
- logical 128-byte to physical 256-byte sector deblocking
- FM-11 ROM-loaded 2D stage-1 IPL at `$0400`
- position-independent 6809 stage-2 cold loader at `$4000`
- bootable-layout 2D CP/M filesystem builder with D88 and raw-image output
- Makefile with binary-size/layout checks

The stage-1 IPL follows the working FM-11 NitrOS-9 2D boot convention: the ROM loads T0/H0/S1-S2 to `$0400`, then stage 1 loads T0/H0/S3 through T1/H1/S16 to `$4000` and starts stage 2.

WRITE, 2HD Standard-FDC transfer, and warm-boot reload remain to be implemented.

## Source layout

```text
cpm22/bios/        Z80 CP/M 2.2 BIOS
include/z80/       Z80-side FM-11 definitions
include/6809/      6809-side FM-11 definitions
m6809/             stage-1 IPL, stage-2 loader and resident I/O service
tools/             build/layout and disk-image helpers
external/cpm22/    local, untracked CCP+BDOS input
external/commands/ local, untracked CP/M command binaries
docs/              hardware, protocol, disk and build notes
```

## Reference media

Original Fujitsu CP/M disk images are used only as reverse-engineering references and are not part of this repository. CP/M system binaries whose redistribution terms are unclear should likewise be supplied externally by the user/build environment.
