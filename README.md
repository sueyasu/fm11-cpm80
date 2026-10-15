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

- `lwasm` (LWTOOLS) for MC6809 sources
- `asm8080` for the CP/M/8080 BIOS
- Python 3 and make

See [docs/build.md](docs/build.md) for setup and the required external CCP+BDOS image.

The CP/M CCP+BDOS binary is intentionally not kept in Git. The current build expects a locally supplied **56K** core at `external/cpm22/ccpbdos56.bin`; a normal 62K image overlaps the resident 6809 I/O-service area and is therefore not suitable for this initial port.

## Current status

The repository contains:

- `asm8080`-compatible CP/M 2.2 BIOS jump table and disk structures
- direct standard-8251 console routines
- Fujitsu-compatible DPH/DPB definitions for 2D and 2HD
- A:-H: logical drive mapping
- Z80/6809 mailbox definitions at `$EC00`
- resident 6809 I/O-service dispatcher at `$DE00`
- functional Mini FDC PIO READ path for A:-D: 2D drives
- logical 128-byte to physical 256-byte sector deblocking
- cold-loader skeleton
- Makefile with binary-size/layout checks

WRITE, 2HD Standard-FDC transfer, warm boot reload, and the final boot-track image builder remain to be implemented.

## Source layout

```text
cpm22/bios/        8080 CP/M 2.2 BIOS
include/z80/       8080/Z80-side FM-11 definitions
include/6809/      6809-side FM-11 definitions
m6809/             loader and resident I/O service
tools/             build/layout helpers
external/cpm22/    local, untracked CCP+BDOS input
docs/              hardware, protocol, disk and build notes
```

## Reference media

Original Fujitsu CP/M disk images are used only as reverse-engineering references and are not part of this repository. CP/M system binaries whose redistribution terms are unclear should likewise be supplied externally by the user/build environment.
