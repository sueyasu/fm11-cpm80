* FM-11 resident 6809 I/O service skeleton.
*
* This code is intended to remain resident while CP/M runs on the Z80.
* It deliberately owns floppy-controller access; the Z80 BIOS communicates
* only through the EC00 mailbox and CPU hand-off at FD05.

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

* TODO next commit:
*   - select Mini FDC for A:-D: or Standard FDC for E:-H:
*   - read one 256-byte physical sector into PhysBuf
*   - copy the selected 128-byte half to the CP/M DMA address
*   - retry and return controller errors appropriately
        lda     #MBSTAT_ERROR
        sta     MBOX_STATUS
        bra     ServiceDone

ServiceWrite
        bsr     ValidateDiskRequest
        bcs     ServiceBad
        bsr     DecodeLogicalSector
        bcs     ServiceBad

* TODO next commit:
*   - read-modify-write a 256-byte physical sector where required
*   - honour MBOX_FLAGS CP/M write type once basic writes are proven
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
* Validate drive 0..7 and basic logical-sector range.
* Carry set on failure.
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
*   PhysTrack      cylinder low byte (40/77 cylinder media)
*   PhysSide       0 or 1
*   PhysSector     1-based physical sector number
*   PhysHalf       0=first 128 bytes, 1=second 128 bytes
*   PhysFdcBase    MINIFDC or STDFDC
*
* Carry set if the logical sector is outside the selected format.
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

* 2D: 64 records/cylinder, 32 records/side, 16 x 256-byte sectors/side.
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
* 2HD: 104 records/cylinder, 52 records/side, 26 x 256-byte sectors/side.
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

PhysTrack       rmb     1
PhysSide        rmb     1
PhysSector      rmb     1
PhysHalf        rmb     1
PhysFdcBase     rmb     2

* Physical-sector bounce buffer used by 128/256-byte deblocking.
PhysBuf         rmb     256
