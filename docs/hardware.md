# FM-11 CP/M-80 hardware assumptions

The 6809+Z80 and 8088+Z80 versions use the Z80 card; the V20 version
runs CP/M in 8080 emulation mode without the Z80 card. The native CPU
controls disk, DMA, console and serial hardware.

## Z80 memory view

The Z80 address space is RAM from `0000-FBFF` and memory-mapped I/O from
`FC00-FFFF`.

The bank register at `$FD2F` affects only the middle 32 KiB window:

- `0000-3FFF`: fixed RAM
- `4000-BFFF`: banked window, physical `x4000-xBFFF`
- `C000-FBFF`: fixed RAM
- `FC00-FFFF`: memory-mapped I/O

`x` is selected by the low four bits of `$FD2F`. The Z80 backends initialize the mapping to bank 0 (6809) or bank 1
(8088); V20 instead uses segment 1000h and CALLN.

The shared native I/O service mailbox occupies the highest ten bytes of CP/M RAM,
`$FBF6-$FBFF`.

## 6809 private I/O-server memory

The IPL reserves logical D000-EFFF in MMR task 0:

```text
6809 logical        Physical RAM       Use
D000-E7FF     ->    10000-117FF        I/O server, code and data
E800-EFFF     ->    11800-11FFF        private stack (initial S=F000)
                    12000-15FFF        two 8 KiB write-back cache windows
```

Logical page C (C000-CFFF) is the temporary 6809 window onto Z80
bank-0 RAM or cache RAM through MMR12. Its previous mapping is saved
and restored. Records crossing a 4 KiB boundary are copied in two segments.

This window exists only in the 6809 logical address space. The Z80 memory map is
unchanged, so CP/M applications can use DMA buffers in TPA, CCP/BDOS, or other
RAM without depending on the 6809 service mapping.

The CPU-card SRAM at `$FE00-$FFEF` is fixed and is not affected by the MMR. The
CPU hand-off trampoline is installed at `$FE00`, so control can safely cross
between Z80 execution and the remapped 6809 service.

## CPU arbitration

At reset the Z80 is held in WAIT. The main CPU starts execution.

- main CPU writes `$FD05` bit 0 = 1: main CPU stops, Z80 starts
- Z80 writes `$FD05` bit 0 = 0: Z80 stops, main CPU resumes

Both Z80-card backends use this deterministic hand-off. V20 uses
CALLN/IRET and does not switch to an optional Z80 card.

## Guest-visible I/O

The Z80-card backend uses these interfaces directly:

- `$FD05` CPU arbitration
- `$FD2F` Z80 bank register
- shared memory/status interfaces where documented

FDC, DMA, USART0 and 6809 MMR registers are owned by the main CPU service
rather than accessed directly by the Z80. The Z80 CPU hand-off is in `cpu_z80.asm`, while bank initialization
is in `init_z80_6809.asm` or `init_z80_8088.asm`. V20's separate
`cpu_v20.asm` backend invokes the native CALLN gateway.

## Floppy controllers

The Fujitsu CP/M image confirms two controller bases:

- `$FD18`: Mini FDC, used for 2D drives
- `$FD30`: Standard FDC, used for 2HD drives

The logical drive mapping is compatible with Fujitsu CP/M:

- A:-D: 2D units 0-3
- E:-H: 2HD units 0-3

MDC HDD drive I: uses DMA channel 2; 2D/2HD FDCs use DMA 0/1.
Nine HDD models are supported; bubble memory is not.
See [hdd-data.md](hdd-data.md) and [boot-hdd.md](boot-hdd.md).
The FM-11 standard ROM is used for all boot media.

## DRAM refresh

While the Z80 is bus master it is responsible for the Z80-side DRAM refresh behaviour. Normal Z80 instruction execution supplies refresh cycles; emulator accuracy in this area should be checked separately when hardware-faithful execution becomes necessary.
