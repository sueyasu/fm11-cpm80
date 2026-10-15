# FM-11 CP/M-80 I/O protocol

The Z80 card does not use the FM-11 peripheral bus as a general-purpose Z80 I/O bus. The implementation therefore follows the hardware architecture rather than attempting direct Z80 FDC access.

## CPU hand-off

The Z80-visible mailbox occupies the top ten bytes of Z80 RAM, `$FBF6-$FBFF`. The 6809 hand-off trampoline is copied at cold start to CPU-card fixed SRAM at `$FE00`, which remains visible independently of the MMR.

1. Z80 fills the mailbox at `$FBF6-$FBFF`.
2. Z80 writes `0` to `$FD05` bit 0. The Z80 stops and the main 6809 resumes inside the fixed-SRAM trampoline at `$FE00`.
3. The trampoline jumps to the resident 6809 service at `$DE00`.
4. The resident service performs the requested operation and writes result status to the mailbox.
5. The service jumps back to the `$FE00` trampoline.
6. The trampoline writes `1` to `$FD05` bit 0. The 6809 stops and the Z80 resumes at the instruction following its hand-off write.

This is synchronous. The implementation deliberately does not depend on Z80 interrupts.

Keeping the trampoline in fixed CPU-card SRAM means the CPU-switch point does not depend on the 6809 MMR mapping. This is intended to allow the resident service to move to high physical RAM later without changing the hand-off mechanism.

## Mailbox

Base address: `$FBF6`. The ten-byte block ends exactly at the top of Z80-visible RAM (`$FBFF`) so lower RAM remains free for CP/M use.

| Offset | Name | Meaning |
|---:|---|---|
| `+0` | CMD | command |
| `+1` | STATUS | result, 0=success |
| `+2` | DRIVE | CP/M drive 0..7 |
| `+3` | FLAGS | command-specific flags |
| `+4,+5` | TRACK_H/L | cylinder, big-endian for the 6809 |
| `+6,+7` | SECTOR_H/L | CP/M 128-byte logical sector |
| `+8,+9` | DMA_H/L | CP/M DMA address, big-endian for the 6809 |

The Z80 writes 16-bit parameters in high-byte/low-byte order so that the 6809 can load them naturally.

If the protocol later needs more fields, the mailbox can grow downward from `$FBF6` while keeping its upper end at `$FBFF`.

## Commands

- `00` idle/no command
- `01` read one CP/M 128-byte logical sector
- `02` write one CP/M 128-byte logical sector
- `03` warm-boot system reload

## Division of responsibility

The Z80 BIOS keeps the current CP/M drive, track, sector and DMA address. `READ` and `WRITE` copy these parameters to the mailbox and hand control to the 6809.

The 6809 service owns:

- Mini FDC for 2D drives A:-D:
- Standard FDC for 2HD drives E:-H:
- physical 256-byte sector operations
- 128/256-byte deblocking
- DMA transfer and error handling
- CPU hand-off through the fixed-SRAM trampoline
