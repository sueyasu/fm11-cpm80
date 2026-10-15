# FM-11 CP/M-80 I/O protocol

The Z80 card does not use the FM-11 peripheral bus as a general-purpose Z80 I/O bus.  The initial implementation therefore follows the hardware architecture rather than attempting direct Z80 FDC access.

## CPU hand-off

1. Z80 fills the mailbox at `0xEC00`.
2. Z80 writes `0` to `$FD05` bit 0.  The Z80 stops and the main 6809 resumes.
3. The resident 6809 service performs the requested operation.
4. The 6809 writes the result status to the mailbox.
5. The 6809 writes `1` to `$FD05` bit 0.  The 6809 stops and the Z80 resumes at the instruction following its hand-off write.

This is synchronous.  The first implementation deliberately does not depend on Z80 interrupts.

## Mailbox

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

## Commands

- `00` idle/no command
- `01` read one CP/M 128-byte logical sector
- `02` write one CP/M 128-byte logical sector
- `03` warm-boot system reload (reserved for the next implementation stage)

## Division of responsibility

The Z80 BIOS keeps the current CP/M drive, track, sector and DMA address.  `READ` and `WRITE` copy these parameters to the mailbox and hand control to the 6809.

The 6809 service owns:

- Mini FDC for 2D drives A:-D:
- Standard FDC for 2HD drives E:-H:
- physical 256-byte sector operations
- 128/256-byte deblocking
- retry/error handling
- later DMA optimisation

The first low-level disk implementation should use polling/PIO where practical.  DMA can be introduced after the command path is proven.
