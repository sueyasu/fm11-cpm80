#!/usr/bin/env python3
"""Generate an I/O-server source with the floppy cache bypassed.

This is a diagnostic build helper.  It keeps the cache implementation in the
source tree but restores the pre-cache direct FDC read/read-modify-write paths
so failures can be compared without changing the console or boot layout.
"""

from pathlib import Path
import sys


if len(sys.argv) != 3:
    raise SystemExit(f"usage: {sys.argv[0]} INPUT OUTPUT")

src = Path(sys.argv[1]).read_text()

old_read = """        lbsr    ReadPhysicalCached\n        lbcs    ServiceBad\n        lbsr    CopyReadHalfToDma\n"""
new_read = """        lda     PhysIs2HD\n        bne     ServiceRead2HDNoCache\n        lbsr    MiniFdcReadSector\n        bra     ServiceReadCopyNoCache\nServiceRead2HDNoCache\n        lbsr    StdFdcReadSector\nServiceReadCopyNoCache\n        lbcs    ServiceBad\n        lbsr    CopyReadHalfToDma\n"""

old_write = """        lbsr    ReadPhysicalCached\n        lbcs    ServiceBad\n        lbsr    CopyDmaToWriteHalf\n"""
new_write = """        lda     PhysIs2HD\n        bne     ServiceWriteRead2HDNoCache\n        lbsr    MiniFdcReadSector\n        bra     ServiceWriteReadDoneNoCache\nServiceWriteRead2HDNoCache\n        lbsr    StdFdcReadSector\nServiceWriteReadDoneNoCache\n        lbcs    ServiceBad\n        lbsr    CopyDmaToWriteHalf\n"""

old_store = """ServiceWriteCommit\n        bcs     ServiceWriteFail\n        lbsr    CacheStoreSector\n        lda     #MBSTAT_OK\n"""
new_store = """ServiceWriteCommit\n        bcs     ServiceWriteFail\n        lda     #MBSTAT_OK\n"""

for old, new, name in (
    (old_read, new_read, "read path"),
    (old_write, new_write, "write read-modify path"),
    (old_store, new_store, "write cache store"),
):
    count = src.count(old)
    if count != 1:
        raise SystemExit(f"error: expected exactly one {name} pattern, found {count}")
    src = src.replace(old, new, 1)

Path(sys.argv[2]).write_text(src)
