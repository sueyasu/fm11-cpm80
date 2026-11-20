********************************************************************
* Two-window side-track cache, matching the 8086/CP/M-86 policy.
* 32-bit valid/dirty maps per window; unused-first, round-robin victim.
* All physical I/O uses PhysBuf. MMR12 is restored after each copy.
* No routine switches CPUs or changes the mailbox.
********************************************************************

* Cold init, or invalidate only after successful flush.
CacheInvalidate
        clr     CacheUsed
        clr     CacheUsed+1
        clr     CacheNext
        clr     CacheSlot
        clr     CacheIndex
        ldx     #CacheValidMap
        ldb     #16             * contiguous valid and dirty maps
CiLoop
        clr     ,x+
        decb
        bne     CiLoop
        rts

CacheReset
        lbsr    CacheFlushAll
        bcs     CrDone
        lbsr    CacheInvalidate
        lbsr    FdcInvalidatePositions
        clr     HddReady
        andcc   #$FE
CrDone
        rts

* Select the window matching the requested drive/cylinder/side.
* A failed eviction leaves both tags and unwritten dirty bits intact.
CacheSelect
        clrb
CsSearch
        ldx     #CacheUsed
        tst     b,x
        beq     CsNext
        ldx     #CacheDrive
        lda     MBOX_DRIVE
        cmpa    b,x
        bne     CsNext
        ldx     #CacheTrack
        lda     PhysTrack
        cmpa    b,x
        bne     CsNext
        ldx     #CacheSide
        lda     PhysSide
        cmpa    b,x
        lbeq     CsFound
CsNext
        incb
        cmpb    #2
        blo     CsSearch
        clrb
        tst     CacheUsed
        beq     CsAllocate
        incb
        tst     CacheUsed+1
        beq     CsAllocate
        ldb     CacheNext
        lbsr    CacheFlushWindow
        lbcs     CsError
CsAllocate
        ldx     #CacheUsed
        lda     #1
        sta     b,x
        ldx     #CacheDrive
        lda     MBOX_DRIVE
        sta     b,x
        ldx     #CacheTrack
        lda     PhysTrack
        sta     b,x
        ldx     #CacheSide
        lda     PhysSide
        sta     b,x
        stb     CacheSlot
        lslb
        lslb
        ldx     #CacheValidMap
        abx
        clr     ,x
        clr     1,x
        clr     2,x
        clr     3,x
        ldx     #CacheDirtyMap
        abx
        clr     ,x
        clr     1,x
        clr     2,x
        clr     3,x
        ldb     CacheSlot
        tfr     b,a
        eora    #1
        sta     CacheNext
CsFound
        stb     CacheSlot
        andcc   #$FE
        rts
CsError
        orcc    #1
        rts

* X=map base, CacheSlot=0/1, CacheIndex=0..31.
* Return X=bitmap byte address, A=bit mask; B scratch.
CacheBit
        ldb     CacheSlot
        lslb
        lslb
        abx
        ldb     CacheIndex
        lsrb
        lsrb
        lsrb
        abx
        ldb     CacheIndex
        andb    #7
        lda     #1
        tstb
        beq     CbDone
CbShift
        lsla
        decb
        bne     CbShift
CbDone
        rts

* Map one sector of the selected slot, returning Y=logical address.
* The 256-byte sector cannot cross a 4 KiB boundary.
CacheMapSector
        lda     MMR_PAGE_C
        sta     SavedMmrC
        lda     CacheSlot
        lsla
        ldb     CacheIndex
        lsrb
        lsrb
        lsrb
        lsrb
        pshs    b
        adda    ,s+
        adda    #CACHE_PAGE_BASE
        sta     MMR_PAGE_C
        lda     CacheIndex
        anda    #$0F
        adda    #$C0
        clrb
        tfr     d,y
        rts

* Copy cached sector to bounce buffer. No valid/dirty state change.
CacheLoadSector
        lbsr    CacheMapSector
        ldx     #PhysBuf
        clrb
ClsCopy
        lda     ,y+
        sta     ,x+
        decb
        bne     ClsCopy
        lbra    RestoreZ80Window

* Copy bounce buffer to selected cache sector and mark valid.
CacheStoreSector
        lbsr    CacheMapSector
        ldx     #PhysBuf
        clrb
CssCopy
        lda     ,x+
        sta     ,y+
        decb
        bne     CssCopy
        lbsr    RestoreZ80Window
        ldx     #CacheValidMap
        lbsr    CacheBit
        ora     ,x
        sta     ,x
        rts

CacheMarkDirty
        ldx     #CacheDirtyMap
        lbsr    CacheBit
        ora     ,x
        sta     ,x
        rts

* Ensure requested sector is in PhysBuf and its cache slot is selected.
* A failed read must not discard dirty data in this or the other slot.
ReadPhysical
        lbsr    CacheSelect
        bcs     RpDone
        lda     PhysSector
        deca
        sta     CacheIndex
        ldx     #CacheValidMap
        lbsr    CacheBit
        bita    ,x
        beq     RpMiss
        lbsr    CacheLoadSector
        bra     RpOK
RpMiss
        lda     PhysIs2HD
        cmpa    #2
        beq     RpHdd
        tsta
        bne     RpHD
        lbsr    MiniFdcReadSector
        bra     RpReadDone
RpHD
        lbsr    StdFdcReadSector
        bra     RpReadDone
RpHdd
        lbsr    HddReadSector
RpReadDone
        bcs     RpDone
        lbsr    CacheStoreSector
RpOK
        andcc   #$FE
RpDone
        rts

* Flush B=window. Preserve caller registers except carry; restore active
* cache coordinates and physical request on BOTH success and failure.
* PhysHalf, PhysFdcBase and mailbox fields are not changed.
CacheFlushWindow
        pshs    a,b,x,y,u
        stb     CacheFlushSlot
        lda     CacheSlot
        ldb     CacheIndex
        pshs    d
        lda     PhysDrive
        ldb     PhysIs2HD
        pshs    d
        lda     PhysTrack
        ldb     PhysSide
        pshs    d
        lda     PhysSector
        pshs    a
        ldb     CacheFlushSlot
        stb     CacheSlot
        ldx     #CacheUsed
        tst     b,x
        lbeq     CfwOK
        ldx     #CacheDrive
        lda     b,x
        cmpa    #8
        beq     CfwHddTag
        tfr     a,b
        anda    #3
        sta     PhysDrive
        andb    #4
        lsrb
        lsrb
        stb     PhysIs2HD
        bra     CfwTagReady
CfwHddTag
        clr     PhysDrive
        lda     #2
        sta     PhysIs2HD
CfwTagReady
        ldb     CacheSlot
        ldx     #CacheTrack
        lda     b,x
        sta     PhysTrack
        ldx     #CacheSide
        lda     b,x
        sta     PhysSide
        clr     CacheIndex
CfwLoop
        ldx     #CacheDirtyMap
        lbsr    CacheBit
        bita    ,x
        beq     CfwNext
        lda     CacheIndex
        inca
        sta     PhysSector
        lbsr    CacheLoadSector
        lda     PhysIs2HD
        cmpa    #2
        beq     CfwHddWrite
        tsta
        bne     CfwHD
        lbsr    MiniFdcWriteSector
        bra     CfwWritten
CfwHD
        lbsr    StdFdcWriteSector
        bra     CfwWritten
CfwHddWrite
        lbsr    HddWriteSector
CfwWritten
        bcs     CfwFail
        ldx     #CacheDirtyMap
        lbsr    CacheBit
        coma
        anda    ,x
        sta     ,x
CfwNext
        inc     CacheIndex
        lda     CacheIndex
        cmpa    #CACHE_MAX_SECTORS
        lblo     CfwLoop
CfwOK
        andcc   #$FE
        bra     CfwRestore
CfwFail
        orcc    #1
CfwRestore
        puls    a
        sta     PhysSector
        puls    d
        sta     PhysTrack
        stb     PhysSide
        puls    d
        sta     PhysDrive
        stb     PhysIs2HD
        puls    d
        sta     CacheSlot
        stb     CacheIndex
        puls    a,b,x,y,u,pc

CacheFlushAll
        clrb
        lbsr    CacheFlushWindow
        bcs     CfaDone
        ldb     #1
        lbsr    CacheFlushWindow
CfaDone
        rts
