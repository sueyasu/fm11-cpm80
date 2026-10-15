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

* Mini FDC, used by the 2D drives A:-D:.
MINIFDC         equ     $FD18
MINIFDC_STATUS  equ     MINIFDC+0      * read status / write command
MINIFDC_TRACK   equ     MINIFDC+1
MINIFDC_SECTOR  equ     MINIFDC+2
MINIFDC_DATA    equ     MINIFDC+3
MINIFDC_SIDE    equ     MINIFDC+4      * bit 0 = side
MINIFDC_DRIVE   equ     MINIFDC+5      * bits 0-1 = drive
MINIFDC_AUX     equ     MINIFDC+6
MINIFDC_IRQ     equ     MINIFDC+7      * read acknowledges FDC IRQ

FDC_CMD_READSEC equ     $80
FDC_CMD_WRITESEC equ    $A0
FDC_ST_BUSY     equ     $01
FDC_ST_DRQ      equ     $02
FDC_ST_LOST     equ     $04
FDC_ST_CRC      equ     $08
FDC_ST_RNF      equ     $10
FDC_ST_WRFAULT  equ     $20
FDC_ST_WRPROT   equ     $40
FDC_ST_NOTRDY   equ     $80
FDC_READERR     equ     FDC_ST_LOST+FDC_ST_CRC+FDC_ST_RNF+FDC_ST_NOTRDY
FDC_WRITEERR    equ     FDC_ST_LOST+FDC_ST_CRC+FDC_ST_RNF+FDC_ST_WRFAULT+FDC_ST_WRPROT+FDC_ST_NOTRDY

* Standard FDC, reserved for the 2HD drives E:-H: (not implemented yet).
STDFDC          equ     $FD30
