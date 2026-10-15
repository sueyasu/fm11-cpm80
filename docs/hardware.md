# FM-11 Z80-card hardware assumptions

This project targets the FM-11 Z80 card as described by hardware analysis and cross-checked against Fujitsu's CP/M-80 image where possible.

## Z80 memory view

The Z80 address space is RAM from `0000-FBFF` and I/O from `FC00-FFFF`.

The bank register at `$FD2F` affects only the middle 32 KiB window:

- `0000-3FFF`: fixed RAM
- `4000-BFFF`: banked window, physical `x4000-xBFFF`
- `C000-FBFF`: fixed RAM
- `FC00-FFFF`: I/O

`x` is selected by the low four bits of `$FD2F`.  This banking model is not yet required by CP/M 2.2 but is retained for a possible CP/M 3 port.

## CPU arbitration

At reset the Z80 is held in WAIT.  The main CPU starts execution.

- main CPU writes `$FD05` bit 0 = 1: main CPU stops, Z80 starts
- Z80 writes `$FD05` bit 0 = 0: Z80 stops, main CPU resumes

The resident 6809 I/O service relies on this deterministic hand-off.

## Z80-visible I/O used initially

The project deliberately uses only interfaces known to be appropriate from the Z80 side:

- `$FD05` CPU arbitration
- `$FD2F` Z80 bank register
- standard 8251 serial data/status registers
- shared memory/status interfaces where documented

FDC and DMA registers are owned by the 6809 service rather than accessed directly by the Z80.

## Floppy controllers

The Fujitsu CP/M image confirms two controller bases:

- `$FD18`: Mini FDC, used for 2D drives
- `$FD30`: Standard FDC, used for 2HD drives

The initial logical mapping is intentionally compatible with Fujitsu CP/M:

- A:-D: 2D units 0-3
- E:-H: 2HD units 0-3

Bubble memory and HDD support are not part of the initial target.

## DRAM refresh

While the Z80 is bus master it is responsible for the Z80-side DRAM refresh behaviour.  Normal Z80 instruction execution supplies refresh cycles; emulator accuracy in this area should be checked separately when hardware-faithful execution becomes necessary.
