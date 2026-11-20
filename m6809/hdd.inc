* MDC transport, using the same DMA2 register protocol as FM-11 NitrOS-9.
* Geometry is shared with the 8088 backend. All I/O is polling.
* PhysSide:PhysTrack = big-endian side-track; PhysSector=1..32.
HddEnsure
        tst     HddReady
        bne     HddGood
        lda     #$20
        sta     MDC_SELECT
        lda     #$14
        sta     MDC_CMD
        clr     MDC_DATA
        clr     MDC_DATA
        bsr     HddWaitResult
        bcs     HddBad
        lda     HddResult+4
        ldx     #HddModels
HddFind
        tst     ,x
        beq     HddBad
        cmpa    ,x
        beq     HddFound
        leax    6,x
        bra     HddFind
HddFound
        lda     1,x
        sta     HddHeads
        ldd     2,x
        std     HddTotalTracks
        ldd     4,x
        std     HddDsm
        lda     #$11
        sta     MDC_CMD
        lda     #$70
        sta     MDC_DATA
        clr     MDC_DATA
        bsr     HddWaitResult
        bcs     HddBad
        inc     HddReady
HddGood
        andcc   #$FE
        rts
HddBad
        orcc    #1
        rts

HddGeometry
        bsr     HddEnsure
        bcs     HddGeoDone
        ldd     HddDsm
        std     MBOX_TRACK_H
        clra
        ldb     HddHeads
        std     MBOX_SECTOR_H
        andcc   #$FE
HddGeoDone
        rts

HddWaitResult
        pshs    x
        ldx     #$FFFF
HddWait
        lda     MDC_CMD
        bita    #$40
        bne     HddDrainStart
        leax    -1,x
        bne     HddWait
        orcc    #1
        puls    x,pc
HddDrainStart
        ldx     #HddResult
        ldb     #10
HddDrain
        lda     MDC_DATA
        sta     ,x+
        decb
        bne     HddDrain
        lda     HddResult
        bita    #$80
        bne     HddResultBad
        andcc   #$FE
        puls    x,pc
HddResultBad
        orcc    #1
        puls    x,pc

HddDecode
        ldd     MBOX_TRACK_H
        cmpd    HddTotalTracks
        lbhs    HddBad
        sta     PhysSide
        stb     PhysTrack
        ldd     MBOX_SECTOR_H
        cmpd    #64
        bhs     HddBad
        tfr     b,a
        anda    #1
        sta     PhysHalf
        lsrb
        incb
        stb     PhysSector
        andcc   #$FE
        rts

HddReadSector
        lda     #$22
        ldb     #DMA_READ_MODE
        bra     HddTransfer
HddWriteSector
        lda     #$23
        ldb     #DMA_WRITE_MODE
HddTransfer
        pshs    d,x,y,u
        pshs    d
        lbsr    HddEnsure
        lbcs    HddTransferBad
        * Compute side-track * 32 + physical sector - 1 (24 bits).
        lda     PhysSide
        ldb     PhysTrack
        clr     HddLba
        ldx     #5
HddShift
        lslb
        rola
        rol     HddLba
        leax    -1,x
        bne     HddShift
        std     HddLba+1
        ldb     PhysSector
        decb
        orb     HddLba+2
        stb     HddLba+2
        clr     DMA2_MODE
        tst     HddRaw
        beq     HddPrivate
        ldd     MBOX_DMA_H
        std     DMA2_ADDR_H
        clr     DMA2_BANK
        bra     HddDmaCount
HddPrivate
        ldd     #PhysBuf+IOSERVER_PHYS_DELTA
        std     DMA2_ADDR_H
        lda     #1
        sta     DMA2_BANK
HddDmaCount
        ldd     #$0100
        std     DMA2_COUNT_H
        lda     #$20
        sta     MDC_SELECT
        puls    d
        stb     DMA2_MODE
        sta     MDC_CMD
        clr     MDC_DATA
        clr     MDC_DATA
        clr     MDC_DATA
        lda     HddLba
        sta     MDC_DATA
        lda     HddLba+1
        sta     MDC_DATA
        lda     HddLba+2
        sta     MDC_DATA
        lda     #1
        sta     MDC_DATA
        clr     MDC_DATA
        lbsr    HddWaitResult
        bcs     HddIoBad
        lda     DMA2_MODE
        anda    #DMA_ERROR+DMA_COMPLETE
        cmpa    #DMA_COMPLETE
        bne     HddIoBad
        clr     DMA2_MODE
        andcc   #$FE
        puls    d,x,y,u,pc
HddTransferBad
        leas    2,s
HddIoBad
        clr     DMA2_MODE
        orcc    #1
        puls    d,x,y,u,pc

* For BOOT/WBOOT use the same private buffer + MMR12 copy as 2HD.
HddReadWBoot
        lbsr    HddReadSector
        bcs     HddBootDone
        lbra    SrwCopy
HddBootDone
        rts
HddAdvanceBoot
        lda     PhysSector
        cmpa    #33
        blo     HddBootDone
        lda     #1
        sta     PhysSector
        inc     PhysTrack
        bne     HddBootDone
        inc     PhysSide
        rts

* type, heads, total side-tracks, DSM
HddModels
        fcb     $04,4
        fdb     628,311
        fcb     $08,2
        fdb     630,313
        fcb     $05,6
        fdb     942,467
        fcb     $09,4
        fdb     1260,627
        fcb     $0a,6
        fdb     1890,941
        fcb     $0c,8
        fdb     2520,1255
        fcb     $14,4
        fdb     2988,1491
        fcb     $15,7
        fdb     5229,2610
        fcb     $16,11
        fdb     8217,4102
        fcb     0
