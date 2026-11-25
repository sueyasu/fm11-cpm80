* Public RAW_DISK_API. Direct physical DMA to Z80 bank zero.
RawService
        cmpb    #MBCMD_CPU_TYPE
        bne     RawDisk
        clr     MBOX_DATA
        andcc   #$FE
        rts
RawDisk
        stb     RawOp
        lbsr    RawDecode
        lbcs    RawDone
        lda     RawOp
        cmpa    #MBCMD_RAW_GEOM
        bne     RawTransfer
        ldd     RawTracks
        std     MBOX_TRACK_H
        lda     RawSpt
        ldb     RawN
        std     MBOX_SECTOR_H
        lda     RawHeads
        sta     MBOX_DATA
        andcc   #$FE
        rts
RawTransfer
        ldd     MBOX_DMA_H
        cmpd    #$0100
        lblo    RawBad
        addd    RawLength
        lbcs    RawBad
        cmpd    #$DC00
        lbhi    RawBad
        lbsr    CacheResetRaw
        lbcs    RawDone
        lbsr    RawDecode
        lbcs    RawDone
        lda     PhysIs2HD
        cmpa    #2
        lbeq     RawHdd
        tsta
        bne     RawStd
        lbsr    MiniFdcSelect
        lbcs    RawDone
        ldx     #DMA0_ADDR_H
        ldy     #MINIFDC
        ldu     #DMA0_MODE
        clr     DMA0_BANK
        bra     RawFdc
RawStd
        lbsr    StdFdcSelect
        lbcs    RawDone
        ldx     #DMA1_ADDR_H
        ldy     #STDFDC
        ldu     #DMA1_MODE
        clr     DMA1_BANK
RawFdc
        clr     ,u
        ldd     MBOX_DMA_H
        std     ,x
        ldd     RawLength
        std     2,x
        ldb     #FDC_CMD_READSEC
        lda     RawOp
        cmpa    #MBCMD_RAW_READ
        beq     RawStartRead
        lda     #DMA_WRITE_MODE
        ldb     #FDC_CMD_WRITESEC
        pshs    a
        lda     RawOp
        cmpa    #MBCMD_RAW_FORMAT
        bne     RawStartWrite
        ldb     #$F0
RawStartWrite
        puls    a
        bra     RawStart
RawStartRead
        lda     #DMA_READ_MODE
RawStart
        sta     ,u
        stb     ,y
        ldx     #$FFFF
RawPoll
        lda     ,u
        bita    #DMA_ERROR
        bne     RawFdcBad
        bita    #DMA_COMPLETE
        bne     RawFdcComplete
        lda     ,y
        bita    #FDC_ST_RNF+FDC_ST_NOTRDY
        bne     RawFdcBad
        leax    -1,x
        bne     RawPoll
        bra     RawFdcBad
RawFdcComplete
        lda     RawOp
        cmpa    #MBCMD_RAW_READ
        bne     RawCheckWrite
        lda     ,y
        bita    #FDC_READERR
        bra     RawCheckStatus
RawCheckWrite
        lda     ,y
        bita    #FDC_WRITEERR
RawCheckStatus
        bne     RawFdcBad
        andcc   #$FE
        bra     RawFdcExit
RawFdcBad
        orcc    #1
        * A failed command leaves the physical position uncertain.
        * Preserve success/failure carry while invalidating positions.
        pshs    cc
        lbsr    FdcInvalidatePositions
        puls    cc
RawFdcExit
        pshs    cc
        clr     ,u
        lda     7,y
        puls    cc,pc
RawHdd
        inc     HddRaw
        lda     RawOp
        cmpa    #MBCMD_RAW_READ
        bne     RawHddWrite
        lbsr    HddReadSector
        bra     RawHddExit
RawHddWrite
        lbsr    HddWriteSector
RawHddExit
        pshs    cc
        clr     HddRaw
        puls    cc
RawDone
        rts
RawBad
        orcc    #1
        rts

RawDecode
        lbsr    ResolveLogicalDrive
        lbcs     RawBad
        lda     #1
        sta     RawN
        lda     #2
        sta     RawHeads
        ldd     #256
        std     RawLength
        lda     PhysIs2HD
        beq     RawMiniGeom
        cmpa    #1
        beq     RawStdGeom
        ldd     HddTotalTracks
        std     RawTracks
        lda     HddHeads
        sta     RawHeads
        lda     #32
        bra     RawSetSpt
RawMiniGeom
        ldd     #80
        std     RawTracks
        lda     #16
        bra     RawSetSpt
RawStdGeom
        ldd     #154
        std     RawTracks
        ldd     MBOX_TRACK_H
        bne     RawStdNormal
        clr     RawN
        ldd     #128
        std     RawLength
RawStdNormal
        lda     #26
RawSetSpt
        sta     RawSpt
        ldd     MBOX_TRACK_H
        cmpd    RawTracks
        lbhs     RawBad
        lda     PhysIs2HD
        cmpa    #2
        beq     RawHddTrack
        ldb     MBOX_TRACK_L
        tfr     b,a
        anda    #1
        sta     PhysSide
        lsrb
        stb     PhysTrack
        bra     RawCheckOp
RawHddTrack
        ldd     MBOX_TRACK_H
        sta     PhysSide
        stb     PhysTrack
RawCheckOp
        lda     RawOp
        cmpa    #MBCMD_RAW_GEOM
        lbeq     RawDecodeOk
        cmpa    #MBCMD_RAW_FORMAT
        bne     RawSector
        lda     PhysIs2HD
        cmpa    #2
        lbeq     RawBad
        tsta
        beq     RawFormatMini
        ldd     #10900
        bra     RawFormatLen
RawFormatMini
        ldd     #6400
RawFormatLen
        std     RawLength
        lda     #1
        sta     PhysSector
        lbra     RawDecodeOk
RawSector
        ldd     MBOX_SECTOR_H
        tsta
        lbne     RawBad
        tstb
        lbeq     RawBad
        cmpb    RawSpt
        lbhi     RawBad
        stb     PhysSector
RawDecodeOk
        andcc   #$FE
        rts
