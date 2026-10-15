# FM-11 Z80-card hardware assumptions

This project targets the FM-11 Z80 card as described by hardware analysis and cross-checked against Fujitsu's CP/M-80 image where possible.

## Z80 memory view

The Z80 address space is RAM from `0000-FBFF` and memory-mapped I/O from
`FC00-FFFF`.

The bank register at `$FD2F` affects only the middle 32 KiB window:

- `0000-3FFF`: fixed RAM
- `4000-BFFF`: banked window, physical `x4000-xBFFF`
- `C000-FBFF`: fixed RAM
- `FC00-FFFF`: memory-mapped I/O

`x` is selected by the low four bits of `$FD2F`. This banking model is not yet
required by CP/M 2.2 but is retained for a possible CP/M 3 port.

The shared Z80/6809 mailbox occupies the highest ten bytes of Z80-visible RAM,
`$FBF6-$FBFF`.

## 6809 private I/O-server memory

The FM-11 main CPU has sixteen 4 KiB MMR entries. CP/M uses hardware task 0 and
keeps that task identity-mapped except for logical page E:

```text
6809 logical        Physical RAM
$E000-$EFFF   ->    $10000-$10FFF
```

The I/O server is linked at logical `$E000` and loaded at physical `$10000`.
The complete current service is limited to `$0400` bytes, so it fits entirely
inside this one private page.

Keeping logical page D identity-mapped is intentional. The 62K CP/M TPA extends
through `$DBFF`, so CP/M DMA buffers in the upper TPA remain directly accessible
to the 6809 service without a temporary MMR remap.

The CPU-card SRAM at `$FE00-$FFEF` is fixed and is not affected by the MMR. The
CPU hand-off trampoline is installed at `$FE00`, so control can safely cross
between Z80 execution and the remapped 6809 service.

## CPU arbitration

At reset the Z80 is held in WAIT. The main CPU starts execution.

- main CPU writes `$FD05` bit 0 = 1: main CPU stops, Z80 starts
- Z80 writes `$FD05` bit 0 = 0: Z80 stops, main CPU resumes

The resident 6809 I/O service relies on this deterministic hand-off.

## Z80-visible I/O used initially

The project deliberately uses only interfaces known to be appropriate from the Z80 side:

- `$FD05` CPU arbitration
- `$FD2F` Z80 bank register
- standard 8251 serial data/status registers
- shared memory/status interfaces where documented

FDC, DMA and 6809 MMR registers are owned by the main CPU service rather than
accessed directly by the Z80.

## Floppy controllers

The Fujitsu CP/M image confirms two controller bases:

- `$FD18`: Mini FDC, used for 2D drives
- `$FD30`: Standard FDC, used for 2HD drives

The initial logical mapping is intentionally compatible with Fujitsu CP/M:

- A:-D: 2D units 0-3
- E:-H: 2HD units 0-3

Bubble memory and HDD support are not part of the initial target.

## DRAM refresh

While the Z80 is bus master it is responsible for the Z80-side DRAM refresh behaviour. Normal Z80 instruction execution supplies refresh cycles; emulator accuracy in this area should be checked separately when hardware-faithful execution becomes necessary.
