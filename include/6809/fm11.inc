* FM-11 hardware definitions for the 6809 resident service.
*
* The mailbox occupies the top ten bytes of Z80-visible RAM.  Keeping it
* at $FBF6-$FBFF leaves the lower address space available for CP/M use.

CPUCTL          equ     $FD05

MBOX_BASE       equ     $FBF6
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

* FM-11 4 KiB memory mapper.  The I/O server is linked at logical $E000 and
* MMR14 maps that one page to physical $10000-$10FFF.  Keeping logical page D
* identity-mapped is important for 62K CP/M, whose TPA extends through $DBFF.
MMR_BASE        equ     $FD80
MMR_TASK        equ     $FD90
MMR_CTRL        equ     $FD93
MMR_ENABLE      equ     $80
MMR_PAGE_E      equ     MMR_BASE+$0E
IOSERVER_PAGE_E equ     $10
IOSERVER_PHYS_DELTA equ  $2000

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

* DMA channel 0 serves the Mini FDC.
DMA0_ADDR_H     equ     $FD40
DMA0_ADDR_L     equ     $FD41
DMA0_COUNT_H    equ     $FD42
DMA0_COUNT_L    equ     $FD43
DMA0_MODE       equ     $FD50
DMA0_BANK       equ     $FD94

DMA_DIR_READ    equ     $00            * I/O -> memory
DMA_DIR_WRITE   equ     $01            * memory -> I/O
DMA_ENABLE      equ     $04
DMA_ERROR       equ     $40
DMA_COMPLETE    equ     $80
DMA_READ_MODE   equ     DMA_DIR_READ+DMA_ENABLE
DMA_WRITE_MODE  equ     DMA_DIR_WRITE+DMA_ENABLE

* Standard FDC, reserved for the 2HD drives E:-H: (not implemented yet).
STDFDC          equ     $FD30
