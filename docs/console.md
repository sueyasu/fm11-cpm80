# Console and resident service

CON: defaults to CRT. TTY and BAT use USART0; UC1 polls both local and
serial input, alternates when both are ready, and mirrors output with a
bounded USART wait. LIST/PUNCH/READER remain serial; LISTST reports TXRDY.

The ANSI parser accepts up to eight CSI parameters (values saturated at
255). Excess parameters cause the sequence to be ignored. Private modes
are ignored. WBOOT discards incomplete sequences. Native display errors
return mailbox failure; CONOUT cannot report an error to BDOS and does
not replay partially transmitted escape sequences. A timeout may still
leave the physical display state uncertain.

The 6809 resident stack starts at logical F000 (grows into E800-EFFF,
private physical 11800-11FFF). The default build assembles the resident
source directly, with the write-through floppy cache enabled by default.
The cache uses physical 12000-15FFF (within the minimum 128 KiB RAM
configuration). Use make clean followed by make FLOPPY_CACHE_FLAGS=
to build without the cache for diagnostics. Both builds retain the private
resident stack and the 6 KiB I/O-server disk-slot size check (D000-E7FF, physical 10000-117FF).

2D and 2HD boot images are built by make image2d and make image2hd.
