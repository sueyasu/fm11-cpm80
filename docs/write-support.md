# 2D disk write support

The FM-11 CP/M BIOS presents 128-byte logical sectors, while the Mini FDC transfers 256-byte physical sectors. Therefore a BIOS WRITE cannot directly overwrite one physical sector without preserving the neighbouring CP/M record.

Both native I/O servers perform cached read/modify/write:

1. decode the CP/M cylinder/record into physical cylinder, side, sector and half,
2. select a side-track window, flushing a dirty victim before reuse,
3. on a miss, DMA-read the complete 256-byte sector into the bounce buffer and cache it,
4. replace only the requested 128-byte half and mark the sector dirty,
5. defer physical writes for types 0 and 2; for type 1 flush all windows before and after the update.

On 6809, copies between CP/M RAM and the cache use the existing `PhysBuf`
bounce buffer and sequential MMR12 mappings. On 8086, record copies use
segment registers. Physical writes on either CPU use the DMA bounce buffer.

Mini FDC transfers use DMA channel 0. `PhysBuf` remains necessary because CP/M records are 128 bytes while the physical sector is 256 bytes; direct DMA to the CP/M buffer would overwrite the neighbouring logical record.

The CP/M WRITE type passed in register C is retained in `MBOX_FLAGS`. All types preserve the neighbouring record; only directory writes impose the immediate flush barrier.

Drives E:-H: use the equivalent Standard FDC / DMA channel 1 path. Drive letters remain fixed regardless of the boot controller.

## Physical floppy positioning

The 6809 I/O server maintains independent cylinder positions for the four Mini FDC and four Standard FDC drives. Before physical reads and writes it disables the corresponding DMA channel, restores an unknown drive, restores the controller TRACK register from the selected drive's saved position, and issues SEEK only when the requested cylinder differs. Failed positioning or physical I/O invalidates that drive's position. Cold and warm boot invalidate all positions; system reload uses the same physical selection path as normal I/O. Both disk IPLs explicitly RESTORE cylinder zero before loading the resident server. The Z80 BIOS mailbox and logical geometry are unchanged.

## Cache synchronization

Both CPU configurations expose CACHE_SYNC (F233h) and CACHE_RESET (F236h).
Both flush two write-back windows. CACHE_RESET additionally clears cache
and saved cylinder positions after successful synchronization. Both report
A/Z status. Failed write-back retains unwritten dirty bits and prevents
replacement/reset. See [I/O protocol](io-protocol.md) for the calling
contract and media-change rules. Both implementations follow CP/M-86's
side-track algorithm; see [8088 target](8088-z80.md).
