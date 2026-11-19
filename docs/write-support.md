# 2D disk write support

The FM-11 CP/M BIOS presents 128-byte logical sectors, while the Mini FDC transfers 256-byte physical sectors. Therefore a BIOS WRITE cannot directly overwrite one physical sector without preserving the neighbouring CP/M record.

For drives A:-D:, the resident 6809 I/O server performs a read/modify/write cycle:

1. decode the CP/M track/sector into physical track, side, sector, and 128-byte half,
2. DMA-read the complete 256-byte physical sector into `PhysBuf`,
3. replace only the requested 128-byte half from the CP/M DMA address,
4. DMA-write the complete 256-byte sector back through the Mini FDC,
5. return `MBSTAT_OK` only after both DMA and FDC completion report no error.

Mini FDC transfers use DMA channel 0. `PhysBuf` remains necessary because CP/M records are 128 bytes while the physical sector is 256 bytes; direct DMA to the CP/M buffer would overwrite the neighbouring logical record.

The CP/M WRITE type passed in register C is retained in `MBOX_FLAGS`; the implementation deliberately uses the same safe read/modify/write path for normal, directory, and unallocated writes.

Drives E:-H: still return an error because the Standard FDC path is not implemented yet.

## Physical floppy positioning

The 6809 I/O server maintains independent cylinder positions for the four Mini FDC and four Standard FDC drives. Before physical reads and writes it disables the corresponding DMA channel, restores an unknown drive, restores the controller TRACK register from the selected drive's saved position, and issues SEEK only when the requested cylinder differs. Failed positioning or physical I/O invalidates that drive's position. Cold and warm boot invalidate all positions; system reload uses the same physical selection path as normal I/O. Both disk IPLs explicitly RESTORE cylinder zero before loading the resident server. The Z80 BIOS mailbox, logical geometry, and write-through cache are unchanged.
