********************************************************************
* FM-11 CP/M-80 2D IPL
*
* FM-11 ROM IPL loads T0/H0/S1-S2 (512 bytes) to $0400 and jumps
* to $0400.  The IPL DMA-loads the CP/M system to Z80 bank-0 RAM and
* the resident 6809 I/O server to physical RAM above the Z80 space:
*
*   disk $0200-$1BFF -> physical $0C400-$0DDFF
*       CCP + BDOS + BIOS (system56.bin, $1A00 bytes)
*
*   disk $1C00-$1FFF -> physical $10E00-$111FF
*       resident 6809 I/O server slot (maximum $0400 bytes)
*
* The I/O server remains linked at logical $DE00.  Before entering it,
* MMR13/MMR14 map logical $D000-$EFFF to physical $10000-$11FFF.
* The complete disk stream still fits in the remaining 30 sectors of
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
SYSTEM_DEST         equ       $C400
SYSTEM_SECTORS      equ       26
IOSERVER_DMA_ADDR   equ       $0E00      * physical $10E00, bank=1
IOSERVER_DMA_BANK   equ       $01
IOSERVER_SECTORS    equ       4
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

* Boot from 2D drive 0.  CP/M itself is loaded to physical bank 0.
                    clr       >FM11_FDC_DRIVE
                    clr       >FM11_DMA0_MODE
                    clr       >FM11_DMA0_BANK

* The ROM has already read T0/H0/S1-S2.  system56.bin starts at S3.
                    clr       >FM11_FDC_TRACK
                    clr       >FM11_FDC_SIDE
                    lda       #3
                    sta       >FM11_FDC_SECTOR
                    ldx       #SYSTEM_DEST
                    ldy       #SYSTEM_SECTORS

load_system         lbsr      read_sector_dma
                    lbcs      boot_error
                    leay      -1,y
                    cmpy      #0
                    beq       system_loaded
                    lbsr      advance_chs
                    bra       load_system

system_loaded
* Move from the last CP/M system sector (T0/H1/S12) to the first I/O-server
* sector (T0/H1/S13), then redirect DMA to physical $10E00.
                    lbsr      advance_chs
                    lda       #IOSERVER_DMA_BANK
                    sta       >FM11_DMA0_BANK
                    ldx       #IOSERVER_DMA_ADDR
                    ldy       #IOSERVER_SECTORS

load_ioserver       lbsr      read_sector_dma
                    lbcs      boot_error
                    leay      -1,y
                    cmpy      #0
                    beq       load_done
                    lbsr      advance_chs
                    bra       load_ioserver

load_done
* Leave DMA channel 0 disabled and restore its bank register to bank 0.
                    clr       >FM11_DMA0_MODE
                    clr       >FM11_DMA0_BANK

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

* Build an explicit task-0 identity map while translation is disabled,
* then replace only logical pages D/E with the private server pages 10/11.
* Preserving the non-MMU bits of FD93 avoids changing ROM/RAM selection.
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

* Logical $DE00 now resolves to physical $10E00. IoServerStart installs the
* fixed-SRAM trampoline and performs the initial hand-off to the Z80.
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

* DMA one 256-byte physical sector directly to DMA-bank:X and advance X.
* The caller owns FM11_DMA0_BANK so the same routine can target bank 0 for
* CP/M and bank 1 for the private 6809 service image.
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
