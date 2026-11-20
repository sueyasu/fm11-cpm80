# FM-11 CP/M-80 I/O protocol

The Z80 card does not use the FM-11 peripheral bus as a general-purpose Z80 I/O bus. The implementation therefore follows the hardware architecture rather than attempting direct Z80 FDC access.

## CPU hand-off

The Z80-visible mailbox occupies the top ten bytes of Z80 RAM, `$FBF6-$FBFF`. The 6809 hand-off trampoline is copied at cold start to CPU-card fixed SRAM at `$FE00`, which remains visible independently of the MMR.

1. Z80 fills the mailbox at `$FBF6-$FBFF`.
2. Z80 writes `0` to `$FD05` bit 0. The Z80 stops and the main 6809 resumes inside the fixed-SRAM trampoline at `$FE00`.
3. The trampoline jumps to the resident 6809 service at `$D000`.
4. The resident service performs the requested operation and writes result status to the mailbox.
5. The service jumps back to the `$FE00` trampoline.
6. The trampoline writes `1` to `$FD05` bit 0. The 6809 stops and the Z80 resumes at the instruction following its hand-off write.

This is synchronous. The implementation deliberately does not depend on Z80 interrupts.

Keeping the trampoline in fixed CPU-card SRAM means the CPU-switch point does not depend on the 6809 MMR mapping. This is intended to allow the resident service to move to high physical RAM later without changing the hand-off mechanism.

For 8088+Z80, `i8086/cpu_z80.inc` handles FD05 directly from private
native RAM. Its loop calls the common `server_dispatch` once per
request; that routine returns with CMD cleared and STATUS written,
rather than switching CPUs itself. See [8088 backend](8088-z80.md)
for the native calling contract.

## CBIOS target hooks

The common 8080 CBIOS (`cpm22/bios/bios.asm`) uses the mailbox definitions
in `include/8080/mailbox.inc`. All CPU-specific operations are implemented
by `cpm22/bios/cpu_z80.asm` (CPU_IOCALL) and the target-specific
`init_z80_6809.asm` / `init_z80_8088.asm` (CPU_INIT).

- `CPU_INIT`: called once on cold boot after the common stack is set up.
  Selects Z80 bank 0 for 6809 or bank 1 for 8088; not called on WBOOT.
- `CPU_IOCALL`: called with a complete mailbox request already posted.
  Returns only after native service completion. The main CPU may be 6809
  or 8088 when using a Z80 card; the implemented V20 backend uses CALLN.

Both hooks preserve BC, DE, HL and the caller's stack; A and flags may be
clobbered. The backend owns interrupt handling (Z80 retains DI, hardware
handoff, NOP, EI). The common MBOX_EXEC reads STATUS and sets A/Z after
return; the backend does not interpret or erase the result. Mailbox addresses
are CP/M logical addresses and must resolve to the same shared memory on
both sides. The V20 hook is `cpm22/bios/cpu_v20.asm`; CPU_INIT returns directly,
CPU_IOCALL invokes CALLN 41h, and the native gateway returns with IRET.

## Mailbox

Base address: `$FBF6`. The ten-byte block ends exactly at the top of Z80-visible RAM (`$FBFF`) so lower RAM remains free for CP/M use.

| Offset | Name | Meaning |
|---:|---|---|
| `+0` | CMD | command |
| `+1` | STATUS | result, 0=success |
| `+2` | DRIVE | CP/M drive 0..8 (0-3=2D, 4-7=2HD, 8=HDD) |
| `+3` | FLAGS / DATA | disk write flags or console character/status |
| `+4,+5` | TRACK_H/L | FDD cylinder or HDD side-track, big-endian |
| `+6,+7` | SECTOR_H/L | CP/M 128-byte logical sector |
| `+8,+9` | DMA_H/L | CP/M DMA address, big-endian for the 6809 |

The Z80 writes 16-bit parameters in high-byte/low-byte order so that the 6809 can load them naturally.

If the protocol later needs more fields, the mailbox can grow downward from `$FBF6` while keeping its upper end at `$FBFF`.

## Commands

- `00` idle/no command
- `01` read one CP/M 128-byte logical sector
- `02` write one CP/M 128-byte logical sector
- `03` warm-boot system reload (synchronize/reset cache before reload)
- `04` CACHE_SYNC: write all pending sectors, retain valid cache and FDC positions
- `05` CACHE_RESET: synchronize, then invalidate all cache entries and FDC positions
- `06` HDD_GEOM: all native servers; TRACK=DSM, SECTOR=OFF, both big-endian
- `07` RAW_GEOM (F239h physical API)
- `08` RAW_READ (one physical sector)
- `09` RAW_WRITE (one physical sector)
- `0A` RAW_FORMAT (FDD WRITE TRACK)
- `0B` CPU_TYPE (0=6809+Z80, 1=8088+Z80, 2=V20)


- `10` local console status (DATA=00h/FFh)
- `11` local console input (DATA=character)
- `12` local console output (DATA=character)
- `13` serial RX status (DATA=00h/FFh, nonblocking, does not consume input)
- `14` serial input (DATA=character, blocks until RXRDY)
- `15` serial output (DATA=character, blocks until TXRDY)
- `16` serial TX status (DATA=00h/FFh, nonblocking)
- `17` serial mirror output (DATA=character, bounded TXRDY wait; STATUS=01h on timeout)

For all console commands, STATUS=00h indicates successful service completion;
DATA is separate from STATUS. Serial input is masked to seven bits by the
CBIOS, as before. Serial initialization is native cold-boot work, not a
mailbox command. The command numbers and byte layout are common to all three implemented
CPU configurations.

## Cache extension ABI

Three FM-11 extension JMP vectors follow the 17 standard CP/M 2.2 BIOS
vectors. All three builds use identical offsets:

| API | BIOS-relative offset | Current address | Mailbox CMD |
|---|---|---|---|
| CACHE_SYNC | 0033h | F233h | 04h |
| CACHE_RESET | 0036h | F236h | 05h |
| RAW_DISK_API | 0039h | F239h | 07h–0Bh |

Call with no arguments. A=00h, Z=1 on success; A=01h, Z=0 on error.
BC/DE/HL and SP are preserved. Other flags are unspecified; do not test
carry. Both operations apply to all drives and do not use or change the
CBIOS-selected drive, track, sector or DMA address. Native services clear
CMD and return STATUS as for existing commands. The standard jump table
indices, ten-byte mailbox layout and CP/M geometry remain unchanged.

Both native servers use two 8 KiB write-back side-track windows.
CACHE_SYNC writes all dirty sectors. CACHE_RESET additionally
invalidates cache and remembered FDC head positions after a successful
flush. Failed write-back retains unwritten dirty data and prevents
cache reassignment or reset; the FDC transport may mark a failed drive's
position unknown to force a retry to re-home it.
WBOOT calls the native cache-reset operation before reloading CCP/BDOS;
on failure it returns an error and the existing CBIOS retry path is used.

The RAW_DISK_API validates the guest buffer and flushes/invalidates the
cache automatically before each physical transfer. A separate utility
bypassing RAW_DISK_API must explicitly synchronize and reset the cache.
Synchronize before replacing/removing media or shutting down an emulator;
reset before a media change to discard old cached data and position state.
These are FM-11-specific extensions, not standard CP/M 2.2 BIOS calls.

WRITE retains the CP/M write type in FLAGS: 0 normal, 1 directory, 2 first
record of an unallocated block. No new fields are needed for write-back.
On both servers, types 0 and 2 are deferred; type 1 flushes all windows
before and after the update.

## Division of responsibility

The common CBIOS keeps the CP/M drive, track, sector and DMA address.
`READ` and `WRITE` post mailbox parameters; the CPU-specific hook enters
the 6809 or 8088 native server (or the V20 CALLN gateway).

The native 6809/8088 I/O service owns:

- Mini FDC for 2D drives A:-D:
- Standard FDC for 2HD drives E:-H:
- MDC HDD I: and 24-bit LBA / DMA channel 2
- physical 256-byte sector operations
- 128/256-byte deblocking
- DMA transfer and error handling
- local console and USART0 initialization / serial I/O
- CPU-specific hand-off (6809 fixed-SRAM trampoline, 8088 FD05 loop,
  or V20 CALLN/IRET)

## Physical disk extension

RAW_DISK_API at BIOS+39h (F239h), operations 07h..0Bh. See
[format-api.md](format-api.md) for the physical address, length, and
cache contract.
