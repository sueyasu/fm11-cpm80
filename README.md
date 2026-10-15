# FM-11 CP/M-80

Open-source BIOS, boot and I/O support for running CP/M-80 on the Fujitsu FM-11 with the Z80 card.

## Initial target

- CP/M 2.2, 56K system layout
- CCP at `$C400`, BDOS at `$CC00`, BIOS at `$DA00`
- A: through D: = 2D floppy drives 0 through 3
- E: through H: = 2HD floppy drives 0 through 3
- No HDD or bubble-memory support initially
- Z80 BIOS with a resident 6809 I/O service for floppy access
- synchronous Z80/6809 mailbox protocol using `$FD05` CPU hand-off

The implementation follows the FM-11 hardware architecture and Fujitsu disk formats where useful, without requiring binary compatibility with Fujitsu's original CP/M implementation.

## Current status

The framework contains:

- Z80 CP/M 2.2 BIOS jump table and basic state handling
- direct standard-8251 console routines
- Fujitsu-compatible DPH/DPB definitions for 2D and 2HD
- A:-H: logical drive mapping
- Z80/6809 mailbox definitions at `$EC00`
- resident 6809 I/O-service dispatcher at `$DE00`
- logical 128-byte to physical 256-byte sector geometry conversion
- Mini FDC PIO sector READ for A:-D: (2D)
- 256-byte bounce-buffer deblocking into the selected CP/M 128-byte DMA record
- cold-loader skeleton

The current functional disk milestone is the A:-D: 2D READ path. WRITE, the Standard FDC E:-H: 2HD path, WBOOT system-track reload and the boot-image builder remain to be implemented and tested.

## Source layout

```text
cpm22/bios/        Z80 CP/M 2.2 BIOS
include/z80/       Z80-side FM-11 definitions
include/6809/      6809-side FM-11 definitions
m6809/             loader and resident I/O service
docs/              hardware, protocol and disk-format notes
```

## Reference media

Original Fujitsu CP/M disk images are used only as reverse-engineering references and are not part of this repository. CP/M system binaries whose redistribution terms are unclear should likewise be supplied externally by the user/build environment.
