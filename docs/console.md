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

The 6809 resident stack starts at logical F000 (grows into E000-EFFF,
private physical 11000-11FFF). The default build assembles the resident
source directly, with the experimental cache disabled. FLOPPY_CACHE is
an optional assembler symbol for diagnostic development only; it requires
extra RAM and may exceed the current disk slot.

2D and 2HD boot images are built by make image2d and make image2hd.
