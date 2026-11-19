********************************************************************
* FM-11 CP/M-80 2D IPL
*
* FM-11 ROM IPL loads T0/H0/S1-S2 (512 bytes) to $0400 and jumps
* to $0400.  The IPL stays on cylinder 0 and loads only the resident
* 6809 I/O server:
*
*   disk $0200-$19FF -> physical $10000-$117FF
*       resident 6809 I/O-server image (maximum $1800 bytes)
*
* The first 14 sectors come from T0/H0/S3-S16 and the final 10 from
* T0/H1/S1-S10. The server is linked at logical $D000.
* MMR13/14 map $D000-$EFFF to physical $10000-$11FFF; the upper
* 2 KiB ($E800-$EFFF) are reserved for its downward-growing stack.
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
FM11_MMR_PAGE_D     equ       FM11_MMR_BASE+$0D
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
IOSERVER_SECTORS    equ       24         * 24 x 256 = $1800
IOSERVER_FIRSTSEC   equ       3

MBOX_BASE           equ       $FBF6
MBOX_LEN            equ       10
IOSERVER_BASE       equ       $D000

start               bra       main
                    fcb       0,0,0,0,0,0,0,0,0,0,0

main                orcc      #$50
                    lds       #STAGE1_STACK

* Boot from 2D drive 0.  The first 14 I/O-server sectors are the remainder
* of T0/H0 after the ROM-loaded IPL; then continue at T0/H1/S1.
                    lda       #$80
                    sta       >FM11_FDC_DRIVE
                    clr       >FM11_DMA0_MODE
                    lda       #IOSERVER_DMA_BANK
                    sta       >FM11_DMA0_BANK
                    clr       >FM11_FDC_SIDE
                    lbsr      restore_cylinder_zero
                    lbcs      boot_error
                    lda       #IOSERVER_FIRSTSEC
                    sta       >FM11_FDC_SECTOR
                    ldx       #IOSERVER_DMA_ADDR
                    ldy       #IOSERVER_SECTORS

load_ioserver       lbsr      read_sector_dma
                    lbcs      boot_error
                    leay      -1,y
                    cmpy      #0
                    beq       load_done

* FD1C also reports FDC completion in bit 6.  Examine only
* the side-select latch (bit 0), or the read of sector 16 on
* head 0 incorrectly advances to nonexistent sector 17.
                    lda       >FM11_FDC_SIDE
                    bita      #$01
                    bne       load_next_sector
                    lda       >FM11_FDC_SECTOR
                    cmpa      #16
                    blo       load_next_sector
                    lda       #1
                    sta       >FM11_FDC_SIDE
                    sta       >FM11_FDC_SECTOR
                    bra       load_ioserver

load_next_sector    inc       >FM11_FDC_SECTOR
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
* then reserve two consecutive logical pages for the resident I/O server.
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
                    sta       >FM11_MMR_PAGE_D
                    lda       #$11
                    sta       >FM11_MMR_PAGE_E

                    lda       >FM11_MMR_CTRL
                    ora       #FM11_MMR_ENABLE
                    sta       >FM11_MMR_CTRL

* A identifies the controller family used for boot to the common I/O server.
                    clra
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

* DMA is disabled while a Type I command positions the physical head.
restore_cylinder_zero
                    lda       >$FD1F
                    lda       #$0B
                    sta       >FM11_FDC_CMD
                    ldu       #$FFFF
restore_wait        lda       >FM11_FDC_CMD
                    bita      #$01
                    beq       restore_done
                    leau      -1,u
                    cmpu      #0
                    bne       restore_wait
                    bra       restore_fail
restore_done        bita      #$90
                    bne       restore_fail
                    lda       >$FD19
                    bne       restore_fail
                    lda       >$FD1F
                    andcc     #$FE
                    rts
restore_fail        lda       >$FD1F
                    orcc      #$01
                    rts

boot_error          bra       boot_error

                    end       start
