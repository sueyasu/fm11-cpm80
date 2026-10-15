* FM-11 resident 6809 I/O service.
*
* This code remains resident while CP/M runs on the Z80.  FDC access is
* owned by the 6809; the Z80 BIOS communicates only through the EC00
* mailbox and CPU hand-off at FD05.

        include "fm11.inc"

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
        lbsr    ValidateDiskRequest
        bcs     ServiceBad
        lbsr    DecodeLogicalSector
        bcs     ServiceBad

* First functional target: A:-D: (2D / Mini FDC).  E:-H: explicitly fail
* until the Standard FDC path is implemented.
        lda     MBOX_DRIVE
        cmpa    #4
        bhs     ServiceBad

        lbsr    MiniFdcReadSector
        bcs     ServiceBad
        lbsr    CopyReadHalfToDma
        bcs     ServiceBad

        lda     #MBSTAT_OK
        sta     MBOX_STATUS
        bra     ServiceDone

ServiceWrite
        lbsr    ValidateDiskRequest
        bcs     ServiceBad
        lbsr    DecodeLogicalSector
        bcs     ServiceBad

* A:-D: use 256-byte physical sectors while CP/M writes 128-byte records.
* Preserve the neighbouring record with a read/modify/write cycle.
        lda     MBOX_DRIVE
        cmpa    #4
        bhs     ServiceBad

        lbsr    MiniFdcReadSector
        bcs     ServiceBad
        lbsr    CopyDmaToWriteHalf
        bcs     ServiceBad
        lbsr    MiniFdcWriteSector
        bcs     ServiceBad

        lda     #MBSTAT_OK
        sta     MBOX_STATUS
        bra     ServiceDone

ServiceWBoot
        lbsr    WarmBootReload
        bcs     ServiceBad
        lda     #MBSTAT_OK
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
* Select Mini FDC geometry for the current request.
* ----------------------------------------------------------------------
MiniFdcSelect
        lda     MBOX_DRIVE
        anda    #$03
        sta     MINIFDC_DRIVE

        lda     PhysSide
        anda    #$01
        sta     MINIFDC_SIDE
        lda     PhysTrack
        sta     MINIFDC_TRACK
        lda     PhysSector
        sta     MINIFDC_SECTOR
        rts

* ----------------------------------------------------------------------
* Read one 256-byte sector from the Mini FDC into PhysBuf.
* ----------------------------------------------------------------------
MiniFdcReadSector
        lbsr    MiniFdcSelect

        lda     MINIFDC_IRQ
        lda     #FDC_CMD_READSEC
        sta     MINIFDC_STATUS

        ldy     #PhysBuf
        clrb                    * 0 means 256 iterations with DECB/BNE
MfrByte
        ldx     #$FFFF
MfrWaitDrq
        lda     MINIFDC_STATUS
        bita    #FDC_READERR
        bne     MfrFailAck
        bita    #FDC_ST_DRQ
        bne     MfrHaveByte
        leax    -1,x
        bne     MfrWaitDrq
        bra     MfrFailAck
MfrHaveByte
        lda     MINIFDC_DATA
        sta     ,y+
        decb
        bne     MfrByte

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
* Write PhysBuf as one 256-byte Mini FDC sector.
* ----------------------------------------------------------------------
MiniFdcWriteSector
        lbsr    MiniFdcSelect

        lda     MINIFDC_IRQ
        lda     #FDC_CMD_WRITESEC
        sta     MINIFDC_STATUS

        ldy     #PhysBuf
        clrb                    * 0 means 256 iterations with DECB/BNE
MfwByte
        ldx     #$FFFF
MfwWaitDrq
        lda     MINIFDC_STATUS
        bita    #FDC_WRITEERR
        bne     MfwFailAck
        bita    #FDC_ST_DRQ
        bne     MfwHaveByte
        leax    -1,x
        bne     MfwWaitDrq
        bra     MfwFailAck
MfwHaveByte
        lda     ,y+
        sta     MINIFDC_DATA
        decb
        bne     MfwByte

        lda     MINIFDC_STATUS
        bita    #FDC_WRITEERR
        bne     MfwFailAck
        lda     MINIFDC_IRQ
        andcc   #$FE
        rts
MfwFailAck
        lda     MINIFDC_IRQ
        orcc    #$01
        rts

* ----------------------------------------------------------------------
* Warm boot: reload CCP+BDOS from the same system image used by cold boot.
* The image begins at raw offset $0200 (T0/H0/S3).  CCP+BDOS is exactly
* $1600 bytes = 22 physical sectors and maps directly to Z80 $C400-$D9FF.
* BIOS and the resident 6809 I/O server remain resident and are not reloaded.
* ----------------------------------------------------------------------
WarmBootReload
        clr     MBOX_DRIVE      * warm boot always uses system drive A:
        clr     PhysTrack
        clr     PhysSide
        lda     #3
        sta     PhysSector
        ldx     #$C400
        stx     WBootDest
        ldu     #22

WbrSector
        lbsr    MiniFdcReadSector
        bcs     WbrFail

        ldy     #PhysBuf
        ldx     WBootDest
        clrb                    * copy all 256 bytes
WbrCopy
        lda     ,y+
        sta     ,x+
        decb
        bne     WbrCopy
        stx     WBootDest

        leau    -1,u
        cmpu    #0
        beq     WbrDone

        inc     PhysSector
        lda     PhysSector
        cmpa    #17
        blo     WbrSector
        lda     #1
        sta     PhysSector
        lda     #1
        sta     PhysSide
        bra     WbrSector

WbrDone
        andcc   #$FE
        rts
WbrFail
        orcc    #$01
        rts

* ----------------------------------------------------------------------
* Copy the requested 128-byte half of PhysBuf to the CP/M DMA address.
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

* ----------------------------------------------------------------------
* Copy 128 bytes from the CP/M DMA address into the selected half of PhysBuf.
* ----------------------------------------------------------------------
CopyDmaToWriteHalf
        ldx     #PhysBuf
        lda     PhysHalf
        beq     CwhDestReady
        leax    128,x
CwhDestReady
        ldy     MBOX_DMA_H
        ldb     #128
CwhLoop
        lda     ,y+
        sta     ,x+
        decb
        bne     CwhLoop
        andcc   #$FE
        rts

PhysTrack       rmb     1
PhysSide        rmb     1
PhysSector      rmb     1
PhysHalf        rmb     1
PhysFdcBase     rmb     2
WBootDest       rmb     2
PhysBuf         rmb     256
