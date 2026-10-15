* FM-11 hardware definitions for the 6809 resident service.
*
* The mailbox is in RAM shared with the Z80 while bank 0 is active.

CPUCTL          equ     $FD05

MBOX_BASE       equ     $EC00
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

MBCMD_NONE      equ     $00
MBCMD_READ      equ     $01
MBCMD_WRITE     equ     $02
MBCMD_WBOOT     equ     $03

MBSTAT_OK       equ     $00
MBSTAT_ERROR    equ     $01

* FDC bases confirmed from the Fujitsu CP/M image and emulator source.
MINIFDC         equ     $FD18       * 2D, A:-D:
STDFDC          equ     $FD30       * 2HD, E:-H:
