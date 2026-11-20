* FM-11 standard 6809 ROM loads HDD records 0-1 at $0400.
* Load LBA2-25 into physical $10000, map resident, enter with A=2.
        include "fm11.inc"
        org     $0400
start   orcc    #$50
        lds     #$2000
        lda     #$20
        sta     MDC_SELECT
        lda     #$11
        sta     MDC_CMD
        lda     #$70
        sta     MDC_DATA
        clr     MDC_DATA
        lbsr    WaitResult
        lbcs    fail
        ldx     #0
        lda     #2
        sta     sector
nextsec clr     DMA2_MODE
        lda     #1
        sta     DMA2_BANK
        stx     DMA2_ADDR_H
        ldd     #$0100
        std     DMA2_COUNT_H
        lda     #DMA_READ_MODE
        sta     DMA2_MODE
        lda     #$22
        sta     MDC_CMD
        clr     MDC_DATA
        clr     MDC_DATA
        clr     MDC_DATA
        clr     MDC_DATA
        clr     MDC_DATA
        lda     sector
        sta     MDC_DATA
        lda     #1
        sta     MDC_DATA
        clr     MDC_DATA
        lbsr    WaitResult
        bcs     fail
        lda     DMA2_MODE
        anda    #DMA_ERROR+DMA_COMPLETE
        cmpa    #DMA_COMPLETE
        bne     fail
        clr     DMA2_MODE
        leax    256,x
        inc     sector
        lda     sector
        cmpa    #26
        blo     nextsec
        clr     DMA2_BANK
        lda     MMR_CTRL
        anda    #$7F
        sta     MMR_CTRL
        clr     MMR_TASK
        ldx     #MMR_BASE
        clra
initmmr sta     ,x+
        inca
        cmpa    #16
        blo     initmmr
        lda     #IOSERVER_PAGE_D
        sta     MMR_PAGE_D
        lda     #IOSERVER_PAGE_E
        sta     MMR_PAGE_E
        lda     MMR_CTRL
        ora     #MMR_ENABLE
        sta     MMR_CTRL
        lda     #2
        jmp     $D000
fail    clr     DMA2_MODE
stop    bra     stop
WaitResult
        pshs    x
        ldx     #$FFFF
wait    lda     MDC_CMD
        bita    #$40
        bne     ready
        leax    -1,x
        bne     wait
        orcc    #1
        puls    x,pc
ready   lda     MDC_DATA
        pshs    a
        ldb     #9
drain   lda     MDC_DATA
        decb
        bne     drain
        puls    a
        bita    #$80
        bne     bad
        andcc   #$FE
        puls    x,pc
bad     orcc    #1
        puls    x,pc
sector  fcb     2
        end     start
