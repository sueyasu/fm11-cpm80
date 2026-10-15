********************************************************************
* FM-11 CP/M-80 2D IPL
*
* FM-11 ROM IPL loads T0/H0/S1-S2 (512 bytes) to $0400 and jumps
* to $0400.  The IPL then loads the CP/M system directly to its final
* RAM addresses, beginning at $C400:
*
*   $C400-$DDFF  CCP + BDOS + BIOS (system56.bin, $1A00 bytes)
*   $DE00-$EBFF  resident 6809 I/O server slot ($0E00 bytes)
*
* The disk image stores those regions contiguously from raw offset $0200,
* so the IPL reads 40 physical sectors beginning at T0/H0/S3 directly to
* $C400-$EBFF.  The final 10 sectors are on cylinder 1 and require SEEK.
********************************************************************

                    org       $0400

FM11_FDC_CMD        equ       $FD18
FM11_FDC_TRACK      equ       $FD19
FM11_FDC_SECTOR     equ       $FD1A
FM11_FDC_DATA       equ       $FD1B
FM11_FDC_SIDE       equ       $FD1C
FM11_FDC_DRIVE      equ       $FD1D
FM11_DMA0_MODE      equ       $FD50

FDC_SEEK            equ       $10
FDC_READSEC         equ       $80
FDC_BUSY            equ       $01
FDC_DRQ             equ       $02
FDC_ERRMASK         equ       $90
DMA_ENABLE          equ       $04

STAGE1_STACK        equ       $2000
SYSTEM_DEST         equ       $C400
SYSTEM_SECTORS      equ       40
SECTORS_PER_SIDE    equ       16

MBOX_BASE           equ       $EC00
MBOX_LEN            equ       10
CPM_WORK_BASE       equ       $F000
CPM_WORK_LEN        equ       $0248
IOSERVER_BASE       equ       $DE00

start               bra       main
                    fcb       0,0,0,0,0,0,0,0,0,0,0

main                orcc      #$50
                    lds       #STAGE1_STACK

* Boot from 2D drive 0 and force programmed I/O rather than DMA.
                    clr       >FM11_FDC_DRIVE
                    lda       >FM11_DMA0_MODE
                    anda      #^DMA_ENABLE
                    sta       >FM11_DMA0_MODE

* The ROM has already read T0/H0/S1-S2.  The direct-load system image
* starts at S3 and is contiguous in raw-image order.
                    clr       >FM11_FDC_TRACK
                    clr       >FM11_FDC_SIDE
                    lda       #3
                    sta       >FM11_FDC_SECTOR
                    ldx       #SYSTEM_DEST
                    ldy       #SYSTEM_SECTORS

load_loop           lbsr      read_sector
                    lbcs      boot_error
                    leay      -1,y
                    cmpy      #0
                    beq       load_done
                    lbsr      advance_chs
                    lbcs      boot_error
                    bra       load_loop

load_done
* Clear Z80/6809 mailbox.
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

* IoServerStart performs the initial FD05 hand-off to the Z80.
                    jmp       IOSERVER_BASE

* Advance 2D CHS in raw-image order:
*   Tn/H0/S1..16, Tn/H1/S1..16, T(n+1)/H0/...
advance_chs         inc       >FM11_FDC_SECTOR
                    lda       >FM11_FDC_SECTOR
                    cmpa      #SECTORS_PER_SIDE+1
                    blo       chs_ok
                    lda       #1
                    sta       >FM11_FDC_SECTOR
                    lda       >FM11_FDC_SIDE
                    beq       select_side1
                    clr       >FM11_FDC_SIDE
                    lbsr      seek_next_track
                    rts
select_side1        lda       #1
                    sta       >FM11_FDC_SIDE
chs_ok              andcc     #$FE
                    rts

* SEEK to the next cylinder.  WD17xx SEEK takes the destination track in
* the data register and updates the track register when the seek completes.
seek_next_track     lda       >FM11_FDC_TRACK
                    inca
                    sta       >FM11_FDC_DATA
                    lda       #FDC_SEEK
                    sta       >FM11_FDC_CMD
                    ldu       #$FFFF
seek_wait           lda       >FM11_FDC_CMD
                    bita      #FDC_ERRMASK
                    bne       seek_fail
                    bita      #FDC_BUSY
                    beq       seek_done
                    leau      -1,u
                    cmpu      #0
                    bne       seek_wait
seek_fail           orcc      #$01
                    rts
seek_done           andcc     #$FE
                    rts

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
