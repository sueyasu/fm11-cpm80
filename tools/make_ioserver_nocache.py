#!/usr/bin/env python3
"""Generate an I/O-server source with the floppy cache bypassed.

This is a diagnostic build helper.  It keeps the cache implementation in the
source tree but restores the pre-cache direct FDC read/read-modify-write paths
so failures can be compared without changing the console or boot layout.

The resident 6809 service must not inherit the IPL's temporary $2000 stack:
that address is inside the CP/M TPA.  Move S to the top of the private
E000-EFFF resident page before the service makes any subroutine calls.
"""

from pathlib import Path
import sys


if len(sys.argv) != 3:
    raise SystemExit(f"usage: {sys.argv[0]} INPUT OUTPUT")

src = Path(sys.argv[1]).read_text()

old_stack_defs = """CACHE_PAGE_BASE equ    $12
CACHE_MAX_SECTORS equ  52

        org     $D000

IoServerStart
        orcc    #$50
"""
new_stack_defs = """CACHE_PAGE_BASE equ    $12
CACHE_MAX_SECTORS equ  52

* The IPL uses $2000 only as a temporary stage-1 stack.  Once CP/M starts,
* $0000-$DBFF is TPA and must never be touched by the resident 6809 service.
* Logical E000-EFFF is permanently mapped to private physical $11000-$11FFF,
* so use its upper boundary as the downward-growing resident stack.
IOSERVER_STACK_TOP equ $F000

        org     $D000

IoServerStart
        orcc    #$50
        lds     #IOSERVER_STACK_TOP
"""

old_read = """        lbsr    ReadPhysicalCached
        lbcs    ServiceBad
        lbsr    CopyReadHalfToDma
"""
new_read = """        lda     PhysIs2HD
        bne     ServiceRead2HDNoCache
        lbsr    MiniFdcReadSector
        bra     ServiceReadCopyNoCache
ServiceRead2HDNoCache
        lbsr    StdFdcReadSector
ServiceReadCopyNoCache
        lbcs    ServiceBad
        lbsr    CopyReadHalfToDma
"""

old_write = """        lbsr    ReadPhysicalCached
        lbcs    ServiceBad
        lbsr    CopyDmaToWriteHalf
"""
new_write = """        lda     PhysIs2HD
        bne     ServiceWriteRead2HDNoCache
        lbsr    MiniFdcReadSector
        bra     ServiceWriteReadDoneNoCache
ServiceWriteRead2HDNoCache
        lbsr    StdFdcReadSector
ServiceWriteReadDoneNoCache
        lbcs    ServiceBad
        lbsr    CopyDmaToWriteHalf
"""

old_store = """ServiceWriteCommit
        bcs     ServiceWriteFail
        lbsr    CacheStoreSector
        lda     #MBSTAT_OK
"""
new_store = """ServiceWriteCommit
        bcs     ServiceWriteFail
        lda     #MBSTAT_OK
"""

for old, new, name in (
    (old_stack_defs, new_stack_defs, "resident stack setup"),
    (old_read, new_read, "read path"),
    (old_write, new_write, "write read-modify path"),
    (old_store, new_store, "write cache store"),
):
    count = src.count(old)
    if count != 1:
        raise SystemExit(f"error: expected exactly one {name} pattern, found {count}")
    src = src.replace(old, new, 1)

Path(sys.argv[2]).write_text(src)
