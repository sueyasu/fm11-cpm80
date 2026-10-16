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
MBOX_DATA       equ     MBOX_FLAGS
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
MBCMD_LOCAL_CONST equ   $10
MBCMD_LOCAL_CONIN equ   $11
MBCMD_LOCAL_CONOUT equ  $12

MBSTAT_OK       equ     $00
MBSTAT_ERROR    equ     $01

* Display Sub System interface used by the FM-11 local console.  FD05 has
* independent control bits: bit 0 selects the Z80/main-CPU owner, while bit 7
* halts/releases the Display Sub System.  Console service runs with bit 0 clear.
FM11_SUB_SHARED equ     $FC80
SUB_CHAR_OUT    equ     $12
SUB_INKEY2      equ     $2D
SUB_HALT        equ     $80
SUB_WAIT_MAX    equ     $FFFF

* FM-11 4 KiB memory mapper.  Reserve logical $D000-$EFFF as an 8 KiB
* resident window for the I/O server: MMR13 maps physical $10000-$10FFF and
* MMR14 maps physical $11000-$11FFF.  The current image is still smaller than
* 4 KiB and is loaded at physical $10000, but it can grow into the second page
* later without moving its logical base.  Logical page C remains available as
* a temporary window onto arbitrary Z80 bank-0 pages.
MMR_BASE        equ     $FD80
MMR_TASK        equ     $FD90
MMR_CTRL        equ     $FD93
MMR_ENABLE      equ     $80
MMR_PAGE_C      equ     MMR_BASE+$0C
MMR_PAGE_D      equ     MMR_BASE+$0D
MMR_PAGE_E      equ     MMR_BASE+$0E
IOSERVER_PAGE_D equ     $10
IOSERVER_PAGE_E equ     $11
IOSERVER_PHYS_DELTA equ  $3000
Z80_WINDOW_BASE equ     $C000
Z80_WINDOW_END  equ     $D000

* Mini FDC, used by the 2D drives A:-D:.
MINIFDC         equ     $FD18
MINIFDC_STATUS  equ     MINIFDC+0      * read status / write command
MINIFDC_TRACK   equ     MINIFDC+1
MINIFDC_SECTOR  equ     MINIFDC+2
MINIFDC_DATA    equ     MINIFDC+3
MINIFDC_SIDE    equ     MINIFDC+4      * bit 0 = side
MINIFDC_DRIVE   equ     MINIFDC+5      * bits 0-1 = drive, bit 7 = motor
MINIFDC_AUX     equ     MINIFDC+6
MINIFDC_IRQ     equ     MINIFDC+7      * read acknowledges FDC IRQ
MINIFDC_MOTOR   equ     $80

FDC_CMD_RESTORE equ     $0B            * head load, slowest step rate
FDC_CMD_SEEK    equ     $1B            * head load, slowest step rate
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
FDC_SEEKERR     equ     FDC_ST_RNF+FDC_ST_NOTRDY
FDC_READERR     equ     FDC_ST_LOST+FDC_ST_CRC+FDC_ST_RNF+FDC_ST_NOTRDY
FDC_WRITEERR    equ     FDC_ST_LOST+FDC_ST_CRC+FDC_ST_RNF+FDC_ST_WRFAULT+FDC_ST_WRPROT+FDC_ST_NOTRDY

* DMA channel 0 serves the Mini FDC.
DMA0_ADDR_H     equ     $FD40
DMA0_ADDR_L     equ     $FD41
DMA0_COUNT_H    equ     $FD42
DMA0_COUNT_L    equ     $FD43
DMA0_MODE       equ     $FD50
DMA0_BANK       equ     $FD94

* Standard FDC, used by the 2HD drives E:-H:.
STDFDC          equ     $FD30
STDFDC_STATUS   equ     STDFDC+0       * read status / write command
STDFDC_TRACK    equ     STDFDC+1
STDFDC_SECTOR   equ     STDFDC+2
STDFDC_DATA     equ     STDFDC+3
STDFDC_SIDE     equ     STDFDC+4       * bit 0 = side
STDFDC_DRIVE    equ     STDFDC+5       * bits 0-1 = drive
STDFDC_AUX      equ     STDFDC+6
STDFDC_IRQ      equ     STDFDC+7       * read acknowledges FDC IRQ

* DMA channel 1 serves the Standard FDC.
DMA1_ADDR_H     equ     $FD44
DMA1_ADDR_L     equ     $FD45
DMA1_COUNT_H    equ     $FD46
DMA1_COUNT_L    equ     $FD47
DMA1_MODE       equ     $FD51
DMA1_BANK       equ     $FD95

DMA_DIR_READ    equ     $00            * I/O -> memory
DMA_DIR_WRITE   equ     $01            * memory -> I/O
DMA_ENABLE      equ     $04
DMA_ERROR       equ     $40
DMA_COMPLETE    equ     $80
DMA_READ_MODE   equ     DMA_DIR_READ+DMA_ENABLE
DMA_WRITE_MODE  equ     DMA_DIR_WRITE+DMA_ENABLE
