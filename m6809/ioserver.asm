* FM-11 resident 6809 I/O service.
*
* The service is linked at logical $DE00 but no longer resides in Z80 bank-0
* RAM.  The IPL loads it at physical $10E00 and maps logical $D000-$EFFF to
* physical $10000-$11FFF through MMR13/MMR14.  The Z80 therefore retains its
* own independent RAM at $DE00-$EFFF.
*
* CPU hand-off is isolated in a small trampoline copied to the FM-11
* CPU-card fixed SRAM at $FE00.  That SRAM remains visible independently
* of the MMR, so the hand-off point is stable while the private service
* mapping is active.

        include "fm11.inc"

TRAMPOLINE_BASE equ    $FE00

        org     $DE00

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

* Initial cold-boot hand-off uses the same path as all later service calls.
        jmp     TRAMPOLINE_BASE

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
* Preserve the neighbouring record with a DMA read/modify/DMA write cycle.
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
        sta     MINIFDC_DRIVE

        lda     PhysSide
        anda    #$01
        sta     MINIFDC_SIDE
        lda     PhysTrack
        sta     MINIFDC_TRACK
        lda     PhysSector
        sta     MINIFDC_SECTOR
        rts

* Program DMA channel 0 for one 256-byte transfer to/from the private
* I/O-server mapping.  X is a logical address in $D000-$EFFF; adding $3000
* produces the low 16 bits of its physical $1xxxx address.
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

* Program DMA channel 0 for a physical bank-0 transfer at X.  WBOOT uses
* this path so CCP+BDOS can be reloaded into physical $C400-$D9FF even while
* logical page D is mapped to the private 6809 service.
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

* Warm boot reloads CCP+BDOS from the shared system image.  The destination
* is physical Z80 bank 0, so use FDC DMA directly rather than CPU copying
* through logical page D, which belongs to the private service mapping.
WarmBootReload
        clr     MBOX_DRIVE
        clr     PhysTrack
        clr     PhysSide
        lda     #3
        sta     PhysSector
        ldx     #$C400
        stx     WBootDest
        ldu     #22

WbrSector
        lbsr    MiniFdcReadWBoot
        bcs     WbrFail

        ldx     WBootDest
        leax    256,x
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

* Copy the requested 128-byte half of private PhysBuf to the CP/M DMA
* address.  CP/M 2.2 TPA addresses remain in identity-mapped pages below
* $D000; the fixed DIRBUF/CSV/ALV workspace remains in identity-mapped F000.
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

* Copy 128 bytes from the CP/M DMA address into the selected half of the
* private PhysBuf.
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

* Runtime copy placed at fixed CPU-card SRAM $FE00.  The CPUCTL write stops
* the 6809.  When the Z80 later writes CPUCTL=0, the 6809 resumes at the NOP
* and enters the private resident dispatcher through the logical $DE00 map.
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
PhysBuf         rmb     256
