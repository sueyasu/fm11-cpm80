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
print("PASS: 8088/V20 RAW FORMAT/verify retains head position; CACHE_RESET unchanged")
