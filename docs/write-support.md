# 2D disk write support

The FM-11 CP/M BIOS presents 128-byte logical sectors, while the Mini FDC transfers 256-byte physical sectors.  Therefore a BIOS WRITE cannot directly overwrite one physical sector without preserving the neighbouring CP/M record.

For drives A:-D:, the resident 6809 I/O server performs a read/modify/write cycle:

1. decode the CP/M track/sector into physical track, side, sector, and 128-byte half,
2. read the complete 256-byte physical sector into `PhysBuf`,
3. replace only the requested 128-byte half from the CP/M DMA address,
4. write the complete 256-byte sector back through the Mini FDC,
5. return `MBSTAT_OK` only after the FDC reports completion without an error.

The CP/M WRITE type passed in register C is retained in `MBOX_FLAGS`; the first implementation deliberately uses the same safe read/modify/write path for normal, directory, and unallocated writes.

Drives E:-H: still return an error because the Standard FDC path is not implemented yet.
