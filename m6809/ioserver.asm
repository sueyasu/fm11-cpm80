* FM-11 resident 6809 I/O service.
*
* The service is linked at logical $E000 but does not reside in Z80 bank-0
* RAM.  The IPL loads it at physical $10000 and maps logical $E000-$EFFF to
* physical $10000-$10FFF through MMR14.
*
* Logical page D is reserved as a temporary 6809 window onto arbitrary Z80
* physical bank-0 pages.  CP/M DMA buffers are therefore accessed by physical
* address rather than by assuming the current 6809 logical map matches Z80.
*
* CPU hand-off is isolated in a small trampoline copied to the FM-11
* CPU-card fixed SRAM at $FE00.  That SRAM remains visible independently
* of the MMR, so the hand-off point is stable while the private service
* mapping is active.

        include "fm11.inc"

TRAMPOLINE_BASE equ    $FE00
CPM_SYSTEM_DEST equ    $DC00
CPM_SYSTEM_SECTORS equ 26
CPM_WBOOT_SECTORS equ  22
CPM_WORK_BASE   equ    $F9A0
CPM_WORK_LEN    equ    $0248
SYSTEM_TRACK    equ    1

        org     $E000

IoServerStart
        orcc    #$50            * mask IRQ/FIRQ while establishing service
        clr     MBOX_CMD
        clr     MBOX_STATUS

* Install the hand-off trampoline in MMR-independent CPU-card SRAM.
        ldx     #TrampolineTemplate
        ldy     #TRAMPOLINE_BASE
        ldb     #TrampolineTemplateEnd-TrampolineTemplate
InstallTrampoline
        lda     ,x+
        sta     ,y+
        decb
        bne     InstallTrampoline

* The ROM-loaded IPL intentionally stays on cylinder 0.  Once the complete
* resident service is running from private RAM, initialize the Mini FDC and
* load the single CP/M system image from cylinder 1.
        lbsr    ColdBootLoadSystem
        bcs     ColdBootFail

* Clear mutable CP/M disk workspace after the system image is resident.
        ldx     #CPM_WORK_BASE
        ldu     #CPM_WORK_LEN
        clra
ColdClearWorkspace
        sta     ,x+
        leau    -1,u
        cmpu    #0
        bne     ColdClearWorkspace

* Z80 is released from WAIT with PC=0000. Install JP $F200 and clear the
* following page-zero bytes used by the initial cold entry.
        lda     #$C3
        sta     >$0000
        ldd     #$00F2
        std     >$0001
        clra
        sta     >$0003
        sta     >$0004
        clr     MBOX_CMD
        clr     MBOX_STATUS

* Initial cold-boot hand-off uses the same fixed-SRAM path as later calls.
        jmp     TRAMPOLINE_BASE

ColdBootFail
        bra     ColdBootFail

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
        lbcs    ServiceBad
        lbsr    DecodeLogicalSector
        lbcs    ServiceBad

        lda     MBOX_DRIVE
        cmpa    #4
        bhs     ServiceRead2HD
        lbsr    MiniFdcReadSector
        bra     ServiceReadCopy
ServiceRead2HD
        lbsr    StdFdcReadSector
ServiceReadCopy
        lbcs    ServiceBad
        lbsr    CopyReadHalfToDma
        lbcs    ServiceBad

        lda     #MBSTAT_OK
        sta     MBOX_STATUS
        bra     ServiceDone

ServiceWrite
        lbsr    ValidateDiskRequest
        lbcs    ServiceBad
        lbsr    DecodeLogicalSector
        lbcs    ServiceBad

* All floppy formats use 256-byte physical sectors while CP/M writes 128-byte
* records. Preserve the neighbouring record with a read/modify/write cycle.
        lda     MBOX_DRIVE
        cmpa    #4
        bhs     ServiceWrite2HD
        lbsr    MiniFdcReadSector
        lbcs    ServiceBad
        lbsr    CopyDmaToWriteHalf
        lbcs    ServiceBad
        lbsr    MiniFdcWriteSector
        bra     ServiceWriteDone
ServiceWrite2HD
        lbsr    StdFdcReadSector
        lbcs    ServiceBad
        lbsr    CopyDmaToWriteHalf
        lbcs    ServiceBad
        lbsr    StdFdcWriteSector
ServiceWriteDone
        lbcs    ServiceBad

        lda     #MBSTAT_OK
        sta     MBOX_STATUS
        bra     ServiceDone

ServiceWBoot
        lbsr    WarmBootReload
        lbcs    ServiceBad
        lda     #MBSTAT_OK
        sta     MBOX_STATUS
        bra     ServiceDone

ServiceDone
        clr     MBOX_CMD
        jmp     TRAMPOLINE_BASE

ValidateDiskRequest
        lda     MBOX_DRIVE
        cmpa    #8
        bhs     VdrBad
        andcc   #$FE
        rts
VdrBad
        orcc    #$01
        rts

* A CP/M logical record is 128 bytes.  Reject a DMA address whose complete
* record would extend beyond the last Z80 RAM byte at $FBFF.
ValidateDmaRange
        ldd     MBOX_DMA_H
        cmpd    #$FB80
        bhi     VdmBad
        andcc   #$FE
        rts
VdmBad
        orcc    #$01
        rts

* Convert a CP/M 128-byte logical sector to physical FDC geometry.
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
        lsrb
        incb
        stb     PhysSector
        andcc   #$FE
        rts

DlsBad
        orcc    #$01
        rts

MiniFdcSelect
        lda     MBOX_DRIVE
        anda    #$03
        ora     #MINIFDC_MOTOR
        sta     MINIFDC_DRIVE

        lda     PhysSide
        anda    #$01
        sta     MINIFDC_SIDE
        lda     PhysTrack
        sta     MINIFDC_TRACK
        lda     PhysSector
        sta     MINIFDC_SECTOR
        rts

* Wait for a Mini-FDC type-I command to finish.  During BUSY only bit 0 is
* interpreted; seek/not-ready status is checked after command completion.
MiniFdcWaitType1
        ldx     #$FFFF
MftWait
        lda     MINIFDC_STATUS
        bita    #FDC_ST_BUSY
        beq     MftDone
        leax    -1,x
        cmpx    #0
        bne     MftWait
        bra     MftFail
MftDone
        bita    #FDC_SEEKERR
        bne     MftFail
        lda     MINIFDC_IRQ
        andcc   #$FE
        rts
MftFail
        lda     MINIFDC_IRQ
        orcc    #$01
        rts

* Establish a known physical head position before reading the system image.
* This is deliberately done here, after the ROM/IPL boot phase has ended.
MiniFdcPrepareSystemTrack
        lda     #MINIFDC_MOTOR
        sta     MINIFDC_DRIVE
        clr     MINIFDC_SIDE
        lda     MINIFDC_IRQ

        lda     #FDC_CMD_RESTORE
        sta     MINIFDC_STATUS
        lbsr    MiniFdcWaitType1
        bcs     MfpFail

        lda     #SYSTEM_TRACK
        sta     MINIFDC_DATA
        lda     #FDC_CMD_SEEK
        sta     MINIFDC_STATUS
        lbsr    MiniFdcWaitType1
        bcs     MfpFail

        lda     MINIFDC_TRACK
        cmpa    #SYSTEM_TRACK
        bne     MfpFail
        andcc   #$FE
        rts
MfpFail
        orcc    #$01
        rts

* Program DMA channel 0 for one 256-byte transfer to/from the private
* I/O-server mapping.  X is a logical address in $E000-$EFFF; adding $2000
* wraps to the low 16 bits of its physical $1xxxx address.
MiniDmaSetupPrivate
        clr     DMA0_MODE
        tfr     x,d
        addd    #IOSERVER_PHYS_DELTA
        sta     DMA0_ADDR_H
        stb     DMA0_ADDR_L
        lda     #$01
        sta     DMA0_BANK
        lda     #$01
        sta     DMA0_COUNT_H
        clr     DMA0_COUNT_L
        rts

* Program DMA channel 0 for a physical bank-0 transfer at X.  Cold boot and
* WBOOT use this path for the CP/M system image at $DC00-$F5FF.
MiniDmaSetupBank0
        clr     DMA0_MODE
        clr     DMA0_BANK
        tfr     x,d
        sta     DMA0_ADDR_H
        stb     DMA0_ADDR_L
        lda     #$01
        sta     DMA0_COUNT_H
        clr     DMA0_COUNT_L
        rts

* Start/complete one Mini-FDC physical-sector read after DMA has been set up.
MiniFdcReadArmed
        lda     #DMA_READ_MODE
        sta     DMA0_MODE
        lda     #FDC_CMD_READSEC
        sta     MINIFDC_STATUS

        ldx     #$FFFF
MfrWait
        lda     DMA0_MODE
        bita    #DMA_ERROR
        bne     MfrFail
        bita    #DMA_COMPLETE
        bne     MfrDone
        lda     MINIFDC_STATUS
        bita    #FDC_READERR
        bne     MfrFail
        leax    -1,x
        cmpx    #0
        bne     MfrWait
        bra     MfrFail

MfrDone
        clr     DMA0_MODE
        lda     MINIFDC_STATUS
        bita    #FDC_READERR
        bne     MfrFailAck
        lda     MINIFDC_IRQ
        andcc   #$FE
        rts

MfrFail
        clr     DMA0_MODE
MfrFailAck
        lda     MINIFDC_IRQ
        orcc    #$01
        rts

* DMA one physical sector from Mini FDC to private PhysBuf.
* X is scratch here; U is preserved for callers such as WarmBootReload.
MiniFdcReadSector
        lbsr    MiniFdcSelect
        lda     MINIFDC_IRQ
        ldx     #PhysBuf
        lbsr    MiniDmaSetupPrivate
        bra     MiniFdcReadArmed

* DMA one physical sector directly to physical bank 0 at WBootDest.
MiniFdcReadWBoot
        lbsr    MiniFdcSelect
        lda     MINIFDC_IRQ
        ldx     WBootDest
        lbsr    MiniDmaSetupBank0
        bra     MiniFdcReadArmed

* DMA private PhysBuf as one physical sector to the Mini FDC.
* X is scratch; do not consume U so higher-level counters remain intact.
MiniFdcWriteSector
        lbsr    MiniFdcSelect
        lda     MINIFDC_IRQ

        ldx     #PhysBuf
        lbsr    MiniDmaSetupPrivate
        lda     #DMA_WRITE_MODE
        sta     DMA0_MODE
        lda     #FDC_CMD_WRITESEC
        sta     MINIFDC_STATUS

        ldx     #$FFFF
MfwWait
        lda     DMA0_MODE
        bita    #DMA_ERROR
        bne     MfwFail
        bita    #DMA_COMPLETE
        bne     MfwDone
        lda     MINIFDC_STATUS
        bita    #FDC_WRITEERR
        bne     MfwFail
        leax    -1,x
        cmpx    #0
        bne     MfwWait
        bra     MfwFail

MfwDone
        clr     DMA0_MODE
        lda     MINIFDC_STATUS
        bita    #FDC_WRITEERR
        bne     MfwFailAck
        lda     MINIFDC_IRQ
        andcc   #$FE
        rts

MfwFail
        clr     DMA0_MODE
MfwFailAck
        lda     MINIFDC_IRQ
        orcc    #$01
        rts

* Select one of the four 2HD drives on the Standard FDC.  CP/M E:-H: map to
* controller drive numbers 0-3.  Track 0's special boot format is never used
* by normal CP/M I/O because the 2HD DPB has OFF=2.
StdFdcSelect
        lda     MBOX_DRIVE
        suba    #4
        anda    #$03
        sta     STDFDC_DRIVE
        lda     PhysSide
        anda    #$01
        sta     STDFDC_SIDE
        lda     PhysTrack
        sta     STDFDC_TRACK
        lda     PhysSector
        sta     STDFDC_SECTOR
        rts

* Program DMA channel 1 for one 256-byte transfer to/from private PhysBuf.
StdDmaSetupPrivate
        clr     DMA1_MODE
        ldx     #PhysBuf
        tfr     x,d
        addd    #IOSERVER_PHYS_DELTA
        sta     DMA1_ADDR_H
        stb     DMA1_ADDR_L
        lda     #$01
        sta     DMA1_BANK
        lda     #$01
        sta     DMA1_COUNT_H
        clr     DMA1_COUNT_L
        rts

* Start/complete one Standard-FDC sector read through DMA channel 1.
StdFdcReadSector
        lbsr    StdFdcSelect
        lda     STDFDC_IRQ
        lbsr    StdDmaSetupPrivate
        lda     #DMA_READ_MODE
        sta     DMA1_MODE
        lda     #FDC_CMD_READSEC
        sta     STDFDC_STATUS

        ldx     #$FFFF
SfrWait
        lda     DMA1_MODE
        bita    #DMA_ERROR
        bne     SfrFail
        bita    #DMA_COMPLETE
        bne     SfrDone
        lda     STDFDC_STATUS
        bita    #FDC_READERR
        bne     SfrFail
        leax    -1,x
        cmpx    #0
        bne     SfrWait
        bra     SfrFail

SfrDone
        clr     DMA1_MODE
        lda     STDFDC_STATUS
        bita    #FDC_READERR
        bne     SfrFailAck
        lda     STDFDC_IRQ
        andcc   #$FE
        rts
SfrFail
        clr     DMA1_MODE
SfrFailAck
        lda     STDFDC_IRQ
        orcc    #$01
        rts

* DMA private PhysBuf as one physical sector to the Standard FDC.
StdFdcWriteSector
        lbsr    StdFdcSelect
        lda     STDFDC_IRQ
        lbsr    StdDmaSetupPrivate
        lda     #DMA_WRITE_MODE
        sta     DMA1_MODE
        lda     #FDC_CMD_WRITESEC
        sta     STDFDC_STATUS

        ldx     #$FFFF
SfwWait
        lda     DMA1_MODE
        bita    #DMA_ERROR
        bne     SfwFail
        bita    #DMA_COMPLETE
        bne     SfwDone
        lda     STDFDC_STATUS
        bita    #FDC_WRITEERR
        bne     SfwFail
        leax    -1,x
        cmpx    #0
        bne     SfwWait
        bra     SfwFail

SfwDone
        clr     DMA1_MODE
        lda     STDFDC_STATUS
        bita    #FDC_WRITEERR
        bne     SfwFailAck
        lda     STDFDC_IRQ
        andcc   #$FE
        rts
SfwFail
        clr     DMA1_MODE
SfwFailAck
        lda     STDFDC_IRQ
        orcc    #$01
        rts

* Advance within cylinder 1, whose 2D system image starts at H0/S1.
AdvanceSystemSector
        inc     PhysSector
        lda     PhysSector
        cmpa    #17
        blo     AssDone
        lda     #1
        sta     PhysSector
        lda     #1
        sta     PhysSide
AssDone
        rts

* Cold boot loads the one on-disk system62 image from cylinder 1.  It reads
* all 26 physical sectors: CCP+BDOS ($1600) followed by BIOS ($0400).
ColdBootLoadSystem
        lbsr    MiniFdcPrepareSystemTrack
        bcs     CblFail
        clr     MBOX_DRIVE
        lda     #SYSTEM_TRACK
        sta     PhysTrack
        clr     PhysSide
        lda     #1
        sta     PhysSector
        ldx     #CPM_SYSTEM_DEST
        stx     WBootDest
        ldu     #CPM_SYSTEM_SECTORS

CblSector
        lbsr    MiniFdcReadWBoot
        bcs     CblFail
        ldx     WBootDest
        leax    256,x
        stx     WBootDest
        leau    -1,u
        cmpu    #0
        beq     CblDone
        lbsr    AdvanceSystemSector
        bra     CblSector
CblDone
        andcc   #$FE
        rts
CblFail
        orcc    #$01
        rts

* Warm boot uses the same cylinder-1 system image but reloads only CCP+BDOS.
* BIOS remains resident while the service call is in progress.
WarmBootReload
        lbsr    MiniFdcPrepareSystemTrack
        bcs     WbrFail
        clr     MBOX_DRIVE
        lda     #SYSTEM_TRACK
        sta     PhysTrack
        clr     PhysSide
        lda     #1
        sta     PhysSector
        ldx     #CPM_SYSTEM_DEST
        stx     WBootDest
        ldu     #CPM_WBOOT_SECTORS

WbrSector
        lbsr    MiniFdcReadWBoot
        bcs     WbrFail
        ldx     WBootDest
        leax    256,x
        stx     WBootDest
        leau    -1,u
        cmpu    #0
        beq     WbrDone
        lbsr    AdvanceSystemSector
        bra     WbrSector
WbrDone
        andcc   #$FE
        rts
WbrFail
        orcc    #$01
        rts

* Map the physical Z80 bank-0 page containing MBOX_DMA into logical page D.
* Returns Y = $D000 + the original 12-bit DMA offset.  The original MMR13
* value is saved so callers can restore the exact pre-call mapping.
MapZ80DmaWindow
        lda     MMR_PAGE_D
        sta     SavedMmrD
        ldy     MBOX_DMA_H
        tfr     y,d
        lsra
        lsra
        lsra
        lsra
        sta     MMR_PAGE_D
        tfr     y,d
        anda    #$0F
        ora     #$D0
        tfr     d,y
        rts

RestoreZ80Window
        lda     SavedMmrD
        sta     MMR_PAGE_D
        rts

* Copy the requested 128-byte half of private PhysBuf to the CP/M DMA
* address.  MMR13 is a temporary window onto Z80 physical bank-0 RAM, so the
* copy remains correct even when the DMA buffer lies in BDOS or other pages
* not visible at the same logical address to the 6809.  A 4 KiB crossing is
* handled by advancing MMR13 and restarting the D-window at $D000.
CopyReadHalfToDma
        lbsr    ValidateDmaRange
        bcs     CrhBad
        lbsr    MapZ80DmaWindow

        ldx     #PhysBuf
        lda     PhysHalf
        beq     CrhSourceReady
        leax    128,x
CrhSourceReady
        ldb     #128
CrhLoop
        lda     ,x+
        sta     ,y+
        decb
        beq     CrhDone
        cmpy    #Z80_WINDOW_END
        bne     CrhLoop
        inc     MMR_PAGE_D
        ldy     #Z80_WINDOW_BASE
        bra     CrhLoop
CrhDone
        lbsr    RestoreZ80Window
        andcc   #$FE
        rts
CrhBad
        orcc    #$01
        rts

* Copy 128 bytes from the CP/M DMA address into the selected half of private
* PhysBuf using the same temporary physical-memory window.
CopyDmaToWriteHalf
        lbsr    ValidateDmaRange
        bcs     CwhBad
        lbsr    MapZ80DmaWindow

        ldx     #PhysBuf
        lda     PhysHalf
        beq     CwhDestReady
        leax    128,x
CwhDestReady
        ldb     #128
CwhLoop
        lda     ,y+
        sta     ,x+
        decb
        beq     CwhDone
        cmpy    #Z80_WINDOW_END
        bne     CwhLoop
        inc     MMR_PAGE_D
        ldy     #Z80_WINDOW_BASE
        bra     CwhLoop
CwhDone
        lbsr    RestoreZ80Window
        andcc   #$FE
        rts
CwhBad
        orcc    #$01
        rts

* Runtime copy placed at fixed CPU-card SRAM $FE00.  The CPUCTL write stops
* the 6809.  When the Z80 later writes CPUCTL=0, the 6809 resumes at the NOP
* and enters the private resident dispatcher through logical $E000.
TrampolineTemplate
        lda     #$01
        sta     >CPUCTL
        nop
        jmp     ServiceLoop
TrampolineTemplateEnd

PhysTrack       rmb     1
PhysSide        rmb     1
PhysSector      rmb     1
PhysHalf        rmb     1
PhysFdcBase     rmb     2
WBootDest       rmb     2
SavedMmrD       rmb     1
PhysBuf         rmb     256
