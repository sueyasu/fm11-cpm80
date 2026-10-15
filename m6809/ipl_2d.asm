********************************************************************
* FM-11 CP/M-80 2D IPL
*
* FM-11 ROM IPL loads T0/H0/S1-S2 (512 bytes) to $0400 and jumps
* to $0400.  The IPL then DMA-loads the CP/M system directly to its
* final RAM addresses, beginning at $C400:
*
*   $C400-$DDFF  CCP + BDOS + BIOS (system56.bin, $1A00 bytes)
*   $DE00-       resident 6809 I/O server (maximum $0400 bytes here)
*
* The disk image stores those regions contiguously from raw offset $0200.
* The complete direct-load image fits in the remaining 30 sectors of
* cylinder 0, so the IPL never performs SEEK/STEP during cold boot.
********************************************************************

                    org       $0400

FM11_FDC_CMD        equ       $FD18
FM11_FDC_TRACK      equ       $FD19
FM11_FDC_SECTOR     equ       $FD1A
FM11_FDC_SIDE       equ       $FD1C
FM11_FDC_DRIVE      equ       $FD1D

FM11_DMA0_ADDR_H    equ       $FD40
FM11_DMA0_ADDR_L    equ       $FD41
FM11_DMA0_COUNT_H   equ       $FD42
FM11_DMA0_COUNT_L   equ       $FD43
FM11_DMA0_MODE      equ       $FD50
FM11_DMA0_BANK      equ       $FD94

FDC_READSEC         equ       $80
FDC_ERRMASK         equ       $90

DMA_DIR_READ        equ       $00
DMA_ENABLE          equ       $04
DMA_ERROR           equ       $40
DMA_COMPLETE        equ       $80
DMA_READ_MODE       equ       DMA_DIR_READ+DMA_ENABLE

STAGE1_STACK        equ       $2000
SYSTEM_DEST         equ       $C400
SYSTEM_SECTORS      equ       30
SECTORS_PER_SIDE    equ       16

MBOX_BASE           equ       $FBF6
MBOX_LEN            equ       10
CPM_WORK_BASE       equ       $F000
CPM_WORK_LEN        equ       $0248
IOSERVER_BASE       equ       $DE00

start               bra       main
                    fcb       0,0,0,0,0,0,0,0,0,0,0

main                orcc      #$50
                    lds       #STAGE1_STACK

* Boot from 2D drive 0.  The whole direct-load destination is in the first
* physical 64 KiB, so DMA channel 0 always uses bank 0 (PA19-16 = 0).
                    clr       >FM11_FDC_DRIVE
                    clr       >FM11_DMA0_MODE
                    clr       >FM11_DMA0_BANK

* The ROM has already read T0/H0/S1-S2.  The direct-load system image
* starts at S3 and remains entirely within cylinder 0.
                    clr       >FM11_FDC_TRACK
                    clr       >FM11_FDC_SIDE
                    lda       #3
                    sta       >FM11_FDC_SECTOR
                    ldx       #SYSTEM_DEST
                    ldy       #SYSTEM_SECTORS

load_loop           lbsr      read_sector_dma
                    lbcs      boot_error
                    leay      -1,y
                    cmpy      #0
                    beq       load_done
                    lbsr      advance_chs
                    bra       load_loop

load_done
* Leave DMA channel 0 disabled before entering the resident service.
                    clr       >FM11_DMA0_MODE

* Clear Z80/6809 mailbox at the top of Z80-visible RAM.
                    ldx       #MBOX_BASE
                    ldu       #MBOX_LEN
                    clra
clear_mailbox       sta       ,x+
                    leau      -1,u
                    cmpu      #0
                    bne       clear_mailbox

* Clear CP/M mutable DIRBUF/CSV/ALV workspace.
                    ldx       #CPM_WORK_BASE
                    ldu       #CPM_WORK_LEN
                    clra
clear_workspace     sta       ,x+
                    leau      -1,u
                    cmpu      #0
                    bne       clear_workspace

* Z80 is released from WAIT with PC=0000. Install:
*     0000: C3 00 DA    JP DA00
                    lda       #$C3
                    sta       >$0000
                    ldd       #$00DA
                    std       >$0001
                    clra
                    sta       >$0003
                    sta       >$0004

* IoServerStart installs the fixed-SRAM trampoline and hands off to Z80.
                    jmp       IOSERVER_BASE

* Advance only within cylinder 0:
*   T0/H0/S3..16, then T0/H1/S1..16.
advance_chs         inc       >FM11_FDC_SECTOR
                    lda       >FM11_FDC_SECTOR
                    cmpa      #SECTORS_PER_SIDE+1
                    blo       chs_done
                    lda       #1
                    sta       >FM11_FDC_SECTOR
                    lda       #1
                    sta       >FM11_FDC_SIDE
chs_done            rts

* DMA one 256-byte physical sector directly to ,X and advance X.
*
* DMA channel 0 register map:
*   FD40/41 address H/L
*   FD42/43 byte count H/L
*   FD50    mode/status
*   FD94    physical address bank (PA19-16)
*
* For an FDC read the direction bit is 0.  Bit 2 enables the channel;
* status bit 7 signals completion and bit 6 signals a DMA error.
read_sector_dma
                    clr       >FM11_DMA0_MODE
                    tfr       x,d
                    sta       >FM11_DMA0_ADDR_H
                    stb       >FM11_DMA0_ADDR_L
                    lda       #$01
                    sta       >FM11_DMA0_COUNT_H
                    clr       >FM11_DMA0_COUNT_L
                    lda       #DMA_READ_MODE
                    sta       >FM11_DMA0_MODE

                    lda       #FDC_READSEC
                    sta       >FM11_FDC_CMD

                    ldu       #$FFFF
dma_wait            lda       >FM11_DMA0_MODE
                    bita      #DMA_ERROR
                    bne       dma_fail
                    bita      #DMA_COMPLETE
                    bne       dma_done
                    lda       >FM11_FDC_CMD
                    bita      #FDC_ERRMASK
                    bne       dma_fail
                    leau      -1,u
                    cmpu      #0
                    bne       dma_wait

dma_fail            clr       >FM11_DMA0_MODE
                    orcc      #$01
                    rts

dma_done            clr       >FM11_DMA0_MODE
                    lda       >FM11_FDC_CMD
                    bita      #FDC_ERRMASK
                    bne       dma_fail
                    leax      256,x
                    andcc     #$FE
                    rts

boot_error          bra       boot_error

                    end       start
