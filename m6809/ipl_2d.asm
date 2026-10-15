********************************************************************
* FM-11 CP/M-80 2D IPL
*
* FM-11 ROM IPL loads T0/H0/S1-S2 (512 bytes) to $0400 and jumps
* to $0400.  The IPL stays on cylinder 0 and loads only the resident
* 6809 I/O server:
*
*   disk $0200-$09FF -> physical $10000-$107FF
*       resident 6809 I/O server slot (maximum $0800 bytes)
*
* The I/O server is linked at logical $E000.  Before entering it, MMR14
* maps logical $E000-$EFFF to physical $10000-$10FFF.  The I/O server then
* performs the first cylinder seek and loads system62.bin from cylinder 1.
********************************************************************

                    org       $0400

FM11_FDC_CMD        equ       $FD18
FM11_FDC_SECTOR     equ       $FD1A
FM11_FDC_SIDE       equ       $FD1C
FM11_FDC_DRIVE      equ       $FD1D

FM11_DMA0_ADDR_H    equ       $FD40
FM11_DMA0_ADDR_L    equ       $FD41
FM11_DMA0_COUNT_H   equ       $FD42
FM11_DMA0_COUNT_L   equ       $FD43
FM11_DMA0_MODE      equ       $FD50
FM11_DMA0_BANK      equ       $FD94

FM11_MMR_BASE       equ       $FD80
FM11_MMR_TASK       equ       $FD90
FM11_MMR_CTRL       equ       $FD93
FM11_MMR_ENABLE     equ       $80
FM11_MMR_PAGE_E     equ       FM11_MMR_BASE+$0E

FDC_READSEC         equ       $80
FDC_ERRMASK         equ       $90

DMA_DIR_READ        equ       $00
DMA_ENABLE          equ       $04
DMA_ERROR           equ       $40
DMA_COMPLETE        equ       $80
DMA_READ_MODE       equ       DMA_DIR_READ+DMA_ENABLE

STAGE1_STACK        equ       $2000
IOSERVER_DMA_ADDR   equ       $0000      * physical $10000, bank=1
IOSERVER_DMA_BANK   equ       $01
IOSERVER_SECTORS    equ       8
IOSERVER_FIRSTSEC   equ       3

MBOX_BASE           equ       $FBF6
MBOX_LEN            equ       10
IOSERVER_BASE       equ       $E000

start               bra       main
                    fcb       0,0,0,0,0,0,0,0,0,0,0

main                orcc      #$50
                    lds       #STAGE1_STACK

* Boot from 2D drive 0.  Stay entirely on T0/H0 after the ROM-loaded S1-S2.
                    clr       >FM11_FDC_DRIVE
                    clr       >FM11_DMA0_MODE
                    lda       #IOSERVER_DMA_BANK
                    sta       >FM11_DMA0_BANK
                    clr       >FM11_FDC_SIDE
                    lda       #IOSERVER_FIRSTSEC
                    sta       >FM11_FDC_SECTOR
                    ldx       #IOSERVER_DMA_ADDR
                    ldy       #IOSERVER_SECTORS

load_ioserver       lbsr      read_sector_dma
                    lbcs      boot_error
                    leay      -1,y
                    cmpy      #0
                    beq       load_done
                    inc       >FM11_FDC_SECTOR
                    bra       load_ioserver

load_done
                    clr       >FM11_DMA0_MODE
                    clr       >FM11_DMA0_BANK

* Ensure the mailbox starts idle before the I/O server takes ownership.
                    ldx       #MBOX_BASE
                    ldu       #MBOX_LEN
                    clra
clear_mailbox       sta       ,x+
                    leau      -1,u
                    cmpu      #0
                    bne       clear_mailbox

* Build an explicit task-0 identity map while translation is disabled,
* then replace only logical page E with private physical page $10.
                    lda       >FM11_MMR_CTRL
                    anda      #$7F
                    sta       >FM11_MMR_CTRL
                    clr       >FM11_MMR_TASK

                    ldx       #FM11_MMR_BASE
                    clra
init_mmr            sta       ,x+
                    inca
                    cmpa      #16
                    blo       init_mmr

                    lda       #$10
                    sta       >FM11_MMR_PAGE_E

                    lda       >FM11_MMR_CTRL
                    ora       #FM11_MMR_ENABLE
                    sta       >FM11_MMR_CTRL

* The I/O server now owns the remaining cold-boot sequence, including the
* first seek to cylinder 1 and the system62.bin load.
                    jmp       IOSERVER_BASE

* DMA one 256-byte physical sector directly to DMA-bank:X and advance X.
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
