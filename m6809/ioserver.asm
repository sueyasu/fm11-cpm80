* FM-11 resident 6809 I/O service.
*
* This code remains resident while CP/M runs on the Z80.  FDC access is
* owned by the 6809; the Z80 BIOS communicates only through the EC00
* mailbox and CPU hand-off at FD05.

        include "../include/6809/fm11.inc"

        org     $DE00

IoServerStart
        orcc    #$50            * mask IRQ/FIRQ while establishing service
        clr     MBOX_CMD
        clr     MBOX_STATUS

* Initial hand-off to the Z80.  When the Z80 later writes CPUCTL=0, the
* 6809 resumes at the instruction after STA.
IoServerArm
        lda     #$01
        sta     CPUCTL
        nop

ServiceLoop
        ldb     MBOX_CMD
        beq     ServiceDone
        cmpb    #MBCMD_READ
        beq     ServiceRead
        cmpb    #MBCMD_WRITE
        beq     ServiceWrite
        cmpb    #MBCMD_WBOOT
        beq     ServiceWBoot

ServiceBad
        lda     #MBSTAT_ERROR
        sta     MBOX_STATUS
        bra     ServiceDone

ServiceRead
        bsr     ValidateDiskRequest
        bcs     ServiceBad
        bsr     DecodeLogicalSector
        bcs     ServiceBad

* First functional target: A:-D: (2D / Mini FDC).  E:-H: explicitly fail
* until the Standard FDC path is implemented.
        lda     MBOX_DRIVE
        cmpa    #4
        bhs     ServiceBad

        bsr     MiniFdcReadSector
        bcs     ServiceBad
        bsr     CopyReadHalfToDma
        bcs     ServiceBad

        lda     #MBSTAT_OK
        sta     MBOX_STATUS
        bra     ServiceDone

ServiceWrite
        bsr     ValidateDiskRequest
        bcs     ServiceBad
        bsr     DecodeLogicalSector
        bcs     ServiceBad

* WRITE is deliberately not claimed yet.  It will use a 256-byte
* read/modify/write so one CP/M 128-byte record cannot corrupt its neighbour.
        lda     #MBSTAT_ERROR
        sta     MBOX_STATUS
        bra     ServiceDone

ServiceWBoot
* System-track reload is intentionally deferred until the on-disk system
* layout/build process is fixed.  Never claim success before it exists.
        lda     #MBSTAT_ERROR
        sta     MBOX_STATUS
        bra     ServiceDone

ServiceDone
        clr     MBOX_CMD
        lda     #$01
        sta     CPUCTL          * stop 6809, resume Z80
        nop                     * resume here on the next Z80 request
        bra     ServiceLoop

* ----------------------------------------------------------------------
* Validate drive 0..7.  Carry set on failure.
* ----------------------------------------------------------------------
ValidateDiskRequest
        lda     MBOX_DRIVE
        cmpa    #8
        bhs     VdrBad
        andcc   #$FE
        rts
VdrBad
        orcc    #$01
        rts

* ----------------------------------------------------------------------
* Convert a CP/M 128-byte logical sector to FDC geometry.
*
* Inputs:
*   MBOX_DRIVE     0..3 = 2D, 4..7 = 2HD
*   MBOX_TRACK_*   cylinder (big endian)
*   MBOX_SECTOR_*  logical record within cylinder (big endian)
*
* Outputs:
*   PhysTrack      cylinder low byte
*   PhysSide       0 or 1
*   PhysSector     1-based physical sector number
*   PhysHalf       0=first 128 bytes, 1=second 128 bytes
*   PhysFdcBase    MINIFDC or STDFDC
*
* Carry set if track/sector is outside the selected format.
* ----------------------------------------------------------------------
DecodeLogicalSector
        lda     MBOX_TRACK_H
        bne     DlsBad
        lda     MBOX_TRACK_L
        sta     PhysTrack

        lda     MBOX_SECTOR_H
        bne     DlsBad
        ldb     MBOX_SECTOR_L

        lda     MBOX_DRIVE
        cmpa    #4
        bhs     Dls2HD

* 2D: 40 cylinders, 64 records/cylinder, 32 records/side.
        lda     PhysTrack
        cmpa    #40
        bhs     DlsBad
        cmpb    #64
        bhs     DlsBad
        ldx     #MINIFDC
        stx     PhysFdcBase
        clr     PhysSide
        cmpb    #32
        blo     DlsHaveSide
        inc     PhysSide
        subb    #32
        bra     DlsHaveSide

Dls2HD
* 2HD: 77 cylinders, 104 records/cylinder, 52 records/side.
        lda     PhysTrack
        cmpa    #77
        bhs     DlsBad
        cmpb    #104
        bhs     DlsBad
        ldx     #STDFDC
        stx     PhysFdcBase
        clr     PhysSide
        cmpb    #52
        blo     DlsHaveSide
        inc     PhysSide
        subb    #52

DlsHaveSide
        tfr     b,a
        anda    #$01
        sta     PhysHalf
        lsrb                    * two 128-byte records per physical sector
        incb                    * FDC sector numbers are 1-based
        stb     PhysSector
        andcc   #$FE
        rts

DlsBad
        orcc    #$01
        rts

* ----------------------------------------------------------------------
* Read one 256-byte sector from the Mini FDC into PhysBuf.
*
* The FM-11 emulator exposes the next DRQ through a status read after each
* data byte.  Poll DRQ explicitly and use a bounded timeout; do not treat a
* transient BUSY=0 as completion while the 256-byte transfer is in progress.
*
* Carry clear = success, carry set = failure/timeout.
* ----------------------------------------------------------------------
MiniFdcReadSector
* A:-D: map directly to Mini-FDC units 0..3.
        lda     MBOX_DRIVE
        anda    #$03
        sta     MINIFDC_DRIVE

* Program side, cylinder and 1-based physical sector.
        lda     PhysSide
        anda    #$01
        sta     MINIFDC_SIDE
        lda     PhysTrack
        sta     MINIFDC_TRACK
        lda     PhysSector
        sta     MINIFDC_SECTOR

* Acknowledge any stale completion request before starting a new command.
        lda     MINIFDC_IRQ

        lda     #FDC_CMD_READSEC
        sta     MINIFDC_STATUS

        ldy     #PhysBuf
        clrb                    * 0 means 256 iterations with DECB/BNE

MfrByte
        ldx     #$FFFF          * bounded wait for one DRQ
MfrWaitDrq
        lda     MINIFDC_STATUS
        bita    #FDC_READERR
        bne     MfrFailAck
        bita    #FDC_ST_DRQ
        bne     MfrHaveByte
        leax    -1,x
        bne     MfrWaitDrq
        bra     MfrFailAck      * timeout

MfrHaveByte
        lda     MINIFDC_DATA
        sta     ,y+
        decb
        bne     MfrByte

* Transfer finished.  Check final controller status and acknowledge IRQ.
        lda     MINIFDC_STATUS
        bita    #FDC_READERR
        bne     MfrFailAck
        lda     MINIFDC_IRQ
        andcc   #$FE
        rts

MfrFailAck
        lda     MINIFDC_IRQ
        orcc    #$01
        rts

* ----------------------------------------------------------------------
* Copy the requested 128-byte half of PhysBuf to the CP/M DMA address.
* MBOX_DMA_H/L is big-endian so the 6809 can load it as a native pointer.
* CP/M 2.2 runs in Z80 bank 0, so this is the same physical RAM address.
* ----------------------------------------------------------------------
CopyReadHalfToDma
        ldx     #PhysBuf
        lda     PhysHalf
        beq     CrhSourceReady
        leax    128,x
CrhSourceReady
        ldy     MBOX_DMA_H
        ldb     #128
CrhLoop
        lda     ,x+
        sta     ,y+
        decb
        bne     CrhLoop
        andcc   #$FE
        rts

PhysTrack       rmb     1
PhysSide        rmb     1
PhysSector      rmb     1
PhysHalf        rmb     1
PhysFdcBase     rmb     2

* Physical-sector bounce buffer used by 128/256-byte deblocking.
PhysBuf         rmb     256
