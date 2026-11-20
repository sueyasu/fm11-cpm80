; FM-11 hardware definitions for the 8080-compatible BIOS (Z80 card).
;
; The Z80 card sees memory from 0000-FBFF and memory-mapped I/O from
; FC00-FFFF. Only I/O explicitly intended for Z80 access should be used.

FM11_CPUCTL EQU     0FD05H  ; bit 0: 1=Z80 runs, 0=main CPU runs
FM11_BANK EQU     0FD2FH  ; Z80 bank register, x4000-xBFFF window
FM11_Z80INT EQU     0FD50H  ; Z80-card interrupt control (TBD)

; Standard 8251. The BIOS currently assumes firmware/loader has
; initialized its mode/baud-clock environment before Z80 hand-off.
FM11_SER_DATA EQU     0FD06H
FM11_SER_STAT EQU     0FD07H

I8251_TXRDY EQU     01H
I8251_RXRDY EQU     02H

; Shared mailbox. Place the ten-byte communication block at the very top
; of Z80-visible RAM so lower memory remains available to CP/M.
BOOTDRV EQU     0FBF4H  ; logical boot drive (0=2D, 4=2HD)
MBOX_BASE EQU     0FBF6H
MBOX_CMD EQU     MBOX_BASE+0
MBOX_STATUS EQU     MBOX_BASE+1
MBOX_DRIVE EQU     MBOX_BASE+2
MBOX_FLAGS EQU     MBOX_BASE+3
MBOX_DATA EQU     MBOX_FLAGS
MBOX_TRACK_H EQU     MBOX_BASE+4
MBOX_TRACK_L EQU     MBOX_BASE+5
MBOX_SECTOR_H EQU     MBOX_BASE+6
MBOX_SECTOR_L EQU     MBOX_BASE+7
MBOX_DMA_H EQU     MBOX_BASE+8
MBOX_DMA_L EQU     MBOX_BASE+9

MBCMD_NONE EQU     00H
MBCMD_READ EQU     01H
MBCMD_WRITE EQU     02H
MBCMD_WBOOT EQU     03H
MBCMD_LOCAL_CONST EQU     10H
MBCMD_LOCAL_CONIN EQU     11H
MBCMD_LOCAL_CONOUT EQU     12H

MBSTAT_OK EQU     00H
MBSTAT_ERROR EQU     01H
