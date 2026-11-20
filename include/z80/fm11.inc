; FM-11 hardware definitions for the 8080-compatible BIOS (Z80 card).
;
; The Z80 card sees memory from 0000-FBFF and memory-mapped I/O from
; FC00-FFFF. Only I/O explicitly intended for Z80 access should be used.

FM11_CPUCTL EQU     0FD05H  ; bit 0: 1=Z80 runs, 0=main CPU runs
FM11_BANK EQU     0FD2FH  ; Z80 bank register, x4000-xBFFF window
FM11_Z80INT EQU     0FD50H  ; Z80-card interrupt control (TBD)
