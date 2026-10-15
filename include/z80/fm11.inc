; FM-11 hardware definitions for the Z80 side.
;
; The Z80 card sees memory from 0000-FBFF and memory-mapped I/O from
; FC00-FFFF.  Only I/O explicitly intended for Z80 access should be used.

FM11_CPUCTL     equ     0FD05h  ; bit 0: 1=Z80 runs, 0=main CPU runs
FM11_BANK       equ     0FD2Fh  ; Z80 bank register, x4000-xBFFF window
FM11_Z80INT     equ     0FD50h  ; Z80-card interrupt control (TBD)

; Standard 8251.  The BIOS currently assumes firmware/loader has
; initialized its mode/baud-clock environment before Z80 hand-off.
FM11_SER_DATA   equ     0FD06h
FM11_SER_STAT   equ     0FD07h

I8251_TXRDY     equ     01h
I8251_RXRDY     equ     02h

; Shared mailbox.  This is deliberately outside the CP/M 56K system image
; and follows the area used by Fujitsu's CP/M implementation.
MBOX_BASE       equ     0EC00h
MBOX_CMD        equ     MBOX_BASE+0
MBOX_STATUS     equ     MBOX_BASE+1
MBOX_DRIVE      equ     MBOX_BASE+2
MBOX_FLAGS      equ     MBOX_BASE+3
MBOX_TRACK_H    equ     MBOX_BASE+4
MBOX_TRACK_L    equ     MBOX_BASE+5
MBOX_SECTOR_H   equ     MBOX_BASE+6
MBOX_SECTOR_L   equ     MBOX_BASE+7
MBOX_DMA_H      equ     MBOX_BASE+8
MBOX_DMA_L      equ     MBOX_BASE+9

MBCMD_NONE      equ     00h
MBCMD_READ      equ     01h
MBCMD_WRITE     equ     02h
MBCMD_WBOOT     equ     03h

MBSTAT_OK       equ     00h
MBSTAT_ERROR    equ     01h
