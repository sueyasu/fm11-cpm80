#!/usr/bin/env python3
"""Check that raw FORMAT/verify does not forget FDC head position per sector."""
from pathlib import Path
import re

raw = Path("i8086/raw_disk.inc").read_text()
cache = Path("i8086/track_cache.inc").read_text()

def routine(text, label):
    # NASM global label; local .labels remain inside the routine.
    match = re.search(r"(?m)^" + re.escape(label) + r":\s*$", text)
    assert match, f"missing {label}"
    next_global = re.search(r"(?m)^[A-Za-z_][A-Za-z_0-9]*:\s*$",
                            text[match.end():])
    return text[match.end():match.end() + next_global.start()] if next_global else text[match.end():]

raw_service = routine(raw, "raw_service")
assert "call cache_reset_raw" in raw_service, "RAW API must preserve physical head positions"
assert "call cache_reset\n" not in raw_service, "RAW API must not perform full cache reset"
cache_reset_raw = routine(cache, "cache_reset_raw")
assert "call cache_flush_all" in cache_reset_raw, "RAW must first flush dirty data"
assert "call cache_clear_windows" in cache_reset_raw, "RAW must invalidate cache windows"
assert "cache_invalidate" not in cache_reset_raw
assert "fdc_forget_all" not in cache_reset_raw
cache_init = routine(cache, "cache_init")
assert "fdc_forget_all" in cache_init, "Cold init still forgets drive positions"
cache_reset = routine(cache, "cache_reset")
assert "call cache_invalidate" in cache_reset, "Explicit CACHE_RESET semantics must remain"
# 6809 server must implement precisely the same split. Successful
# RAW WRITE TRACK and READ verification must retain the known cylinders.
raw09 = Path("m6809/raw_disk.inc").read_text()
cache09 = Path("m6809/track_cache.inc").read_text()
raw_transfer09 = raw09.split("\nRawTransfer\n", 1)[1].split("\nRawFdc\n", 1)[0]
assert "lbsr    CacheResetRaw" in raw_transfer09
assert "lbsr    CacheReset\n" not in raw_transfer09
reset_raw09 = cache09.split("\nCacheResetRaw\n", 1)[1].split("\n* Select the window", 1)[0]
assert "lbsr    CacheFlushAll" in reset_raw09
assert "lbsr    CacheInvalidate" in reset_raw09
assert "FdcInvalidatePositions" not in reset_raw09
reset09 = cache09.split("\nCacheReset\n", 1)[1].split("\nCacheResetRaw\n", 1)[0]
assert "lbsr    FdcInvalidatePositions" in reset09
fdc_success09 = raw09.split("\nRawFdcComplete\n", 1)[1].split("\nRawFdcBad\n", 1)[0]
assert "FdcInvalidatePositions" not in fdc_success09
fdc_fail09 = raw09.split("\nRawFdcBad\n", 1)[1].split("\nRawFdcExit\n", 1)[0]
assert "lbsr    FdcInvalidatePositions" in fdc_fail09
fdc_exit09 = raw09.split("\nRawFdcExit\n", 1)[1].split("\nRawHdd\n", 1)[0]
assert "FdcInvalidatePositions" not in fdc_exit09
print("PASS: 6809 and 8088/V20 RAW FORMAT/verify retain head position; CACHE_RESET unchanged")
