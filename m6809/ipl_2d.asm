********************************************************************
* FM-11 CP/M-80 2D stage-1 IPL
*
* FM-11 ROM IPL loads T0/H0/S1-S2 (512 bytes) to $0400 and jumps
* to $0400.  This stage-1 then reads the remainder of cylinder 0 only
* (T0/H0/S3-S16 and T0/H1/S1-S16) to $2600 and jumps there.
* The stage-2 image is position independent and must fit in 30 sectors.
*
* $2600 is the established stage-2 execution address.  FM-11 testing has
* shown that starting the 6809 stage-2 at $4000 or above is unreliable,
* while execution from below $4000 is stable.  The stage-1 stack therefore
* lives separately at $2000.
********************************************************************

                    org       $0400

FM11_FDC_CMD        equ       $FD18
FM11_FDC_TRACK      equ       $FD19
FM11_FDC_SECTOR     equ       $FD1A
FM11_FDC_DATA       equ       $FD1B
FM11_FDC_SIDE       equ       $FD1C
FM11_FDC_DRIVE      equ       $FD1D
FM11_DMA0_MODE      equ       $FD50

FDC_READSEC         equ       $80
FDC_DRQ             equ       $02
FDC_ERRMASK         equ       $90
DMA_ENABLE          equ       $04

STAGE1_STACK        equ       $2000
STAGE2_DEST         equ       $2600
STAGE2_SECTORS      equ       30
SECTORS_PER_SIDE    equ       16

start               bra       main
                    fcb       0,0,0,0,0,0,0,0,0,0,0

main                orcc      #$50
                    lds       #STAGE1_STACK

* Boot from 2D drive 0 and force programmed I/O rather than DMA.
                    clr       >FM11_FDC_DRIVE
                    lda       >FM11_DMA0_MODE
                    anda      #^DMA_ENABLE
                    sta       >FM11_DMA0_MODE

* The ROM has already read T0/H0/S1-S2. Stage 2 starts at S3 and fits
* entirely in cylinder 0, so no physical track seek is required.
                    clr       >FM11_FDC_TRACK
                    clr       >FM11_FDC_SIDE
                    lda       #3
                    sta       >FM11_FDC_SECTOR
                    ldx       #STAGE2_DEST
                    ldy       #STAGE2_SECTORS

load_loop           lbsr      read_sector
                    lbcs      boot_error
                    leay      -1,y
                    cmpy      #0
                    beq       load_done
                    lbsr      advance_chs
                    bra       load_loop

load_done           jmp       STAGE2_DEST

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

* Read one 256-byte physical sector to ,X and advance X.
read_sector         lda       #FDC_READSEC
                    sta       >FM11_FDC_CMD
                    ldu       #256
read_byte           pshs      u
                    ldu       #0
wait_drq            lda       >FM11_FDC_CMD
                    bita      #FDC_ERRMASK
                    bne       read_fail_saved
                    bita      #FDC_DRQ
                    bne       have_byte
                    leau      -1,u
                    cmpu      #0
                    bne       wait_drq
                    puls      u
                    orcc      #$01
                    rts
read_fail_saved     puls      u
                    orcc      #$01
                    rts
have_byte           lda       >FM11_FDC_DATA
                    sta       ,x+
                    puls      u
                    leau      -1,u
                    cmpu      #0
                    bne       read_byte
                    lda       >FM11_FDC_CMD
                    bita      #FDC_ERRMASK
                    bne       read_fail
                    andcc     #$FE
                    rts
read_fail           orcc      #$01
                    rts

boot_error          bra       boot_error

                    end       start
