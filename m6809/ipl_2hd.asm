********************************************************************
* FM-11 CP/M-80 2HD IPL
*
* FM-11 ROM IPL loads T0/H0/S1-S4.  The 2HD boot track is the
* standard IBM-style special track: T0/H0 has 26 x 128-byte sectors.
* The IPL loads the current resident 6809 I/O-server image from S5-S20
* into private physical RAM $10000-$107FF, establishes an 8 KiB logical
* resident window at $D000-$EFFF, and enters the I/O server with A=BOOT_2HD.
********************************************************************

                    include   "fm11.inc"

                    org       $0400

STAGE1_STACK        equ       $2000
IOSERVER_DMA_ADDR   equ       $0000      * physical $10000, bank=1
IOSERVER_DMA_BANK   equ       $01
IOSERVER_SECTORS    equ       16         * 16 x 128 = $0800
IOSERVER_FIRSTSEC   equ       5
BOOT_SECTOR_SIZE    equ       128

MBOX_LEN            equ       10
IOSERVER_BASE       equ       $D000
BOOT_2HD            equ       $01

start               bra       main
                    fcb       0,0,0,0,0,0,0,0,0,0,0

main                orcc      #$50
                    lds       #STAGE1_STACK

* The ROM has already positioned the Standard FDC at T0/H0.
                    clr       >STDFDC_DRIVE
                    clr       >DMA1_MODE
                    lda       #IOSERVER_DMA_BANK
                    sta       >DMA1_BANK
                    clr       >STDFDC_TRACK
                    clr       >STDFDC_SIDE
                    lda       #IOSERVER_FIRSTSEC
                    sta       >STDFDC_SECTOR
                    ldx       #IOSERVER_DMA_ADDR
                    ldy       #IOSERVER_SECTORS

load_ioserver       lbsr      read_sector_dma
                    lbcs      boot_error
                    leay      -1,y
                    cmpy      #0
                    beq       load_done
                    inc       >STDFDC_SECTOR
                    bra       load_ioserver

load_done
                    clr       >DMA1_MODE
                    clr       >DMA1_BANK

* Ensure the mailbox starts idle before the I/O server takes ownership.
                    ldx       #MBOX_BASE
                    ldu       #MBOX_LEN
                    clra
clear_mailbox       sta       ,x+
                    leau      -1,u
                    cmpu      #0
                    bne       clear_mailbox

* Build task-0 identity mapping while translation is disabled and reserve
* two consecutive logical pages for the resident I/O server.
                    lda       >MMR_CTRL
                    anda      #$7F
                    sta       >MMR_CTRL
                    clr       >MMR_TASK

                    ldx       #MMR_BASE
                    clra
init_mmr            sta       ,x+
                    inca
                    cmpa      #16
                    blo       init_mmr

                    lda       #IOSERVER_PAGE_D
                    sta       >MMR_PAGE_D
                    lda       #IOSERVER_PAGE_E
                    sta       >MMR_PAGE_E

                    lda       >MMR_CTRL
                    ora       #MMR_ENABLE
                    sta       >MMR_CTRL

* A tells the common resident service which controller family booted us.
                    lda       #BOOT_2HD
                    jmp       IOSERVER_BASE

* DMA one 128-byte boot-track sector directly to physical bank 1:X.
read_sector_dma
                    clr       >DMA1_MODE
                    tfr       x,d
                    sta       >DMA1_ADDR_H
                    stb       >DMA1_ADDR_L
                    clr       >DMA1_COUNT_H
                    lda       #BOOT_SECTOR_SIZE
                    sta       >DMA1_COUNT_L
                    lda       #DMA_READ_MODE
                    sta       >DMA1_MODE

                    lda       #FDC_CMD_READSEC
                    sta       >STDFDC_STATUS

                    ldu       #$FFFF
dma_wait            lda       >DMA1_MODE
                    bita      #DMA_ERROR
                    bne       dma_fail
                    bita      #DMA_COMPLETE
                    bne       dma_done
                    lda       >STDFDC_STATUS
                    bita      #FDC_READERR
                    bne       dma_fail
                    leau      -1,u
                    cmpu      #0
                    bne       dma_wait

dma_fail            clr       >DMA1_MODE
                    orcc      #$01
                    rts

dma_done            clr       >DMA1_MODE
                    lda       >STDFDC_STATUS
                    bita      #FDC_READERR
                    bne       dma_fail
                    leax      BOOT_SECTOR_SIZE,x
                    andcc     #$FE
                    rts

boot_error          bra       boot_error

                    end       start
