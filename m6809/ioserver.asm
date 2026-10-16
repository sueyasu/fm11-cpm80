* FM-11 resident 6809 I/O service.
*
* The service is linked at logical $D000 with $D000-$EFFF reserved as an
* 8 KiB resident window.  The IPL currently loads the image at physical
* $10000 and maps logical $D000-$DFFF to physical $10000-$10FFF; logical
* $E000-$EFFF is pre-mapped to physical $11000-$11FFF for future growth.
*
* A on entry identifies the boot floppy family: 0=2D Mini FDC, 1=2HD
* Standard FDC.  A:-D: always map to the boot family and E:-H: to the other.

        include "fm11.inc"

TRAMPOLINE_BASE equ    $FE00
CPM_SYSTEM_DEST equ    $DC00
CPM_SYSTEM_SECTORS equ 26
CPM_WBOOT_SECTORS equ  22
CPM_WORK_BASE   equ    $F970
CPM_WORK_LEN    equ    $0278
BOOTTYPE        equ    $FBF5
BOOT_2D         equ    $00
BOOT_2HD        equ    $01
SYSTEM_TRACK    equ    1

        org     $D000

IoServerStart
        orcc    #$50
        anda    #$01
        sta     BOOTTYPE
        clr     MBOX_CMD
        clr     MBOX_STATUS
        clr     LocalKeyValid
        clr     LocalKeyChar

        ldx     #TrampolineTemplate
        ldy     #TRAMPOLINE_BASE
        ldb     #TrampolineTemplateEnd-TrampolineTemplate
InstallTrampoline
        lda     ,x+
        sta     ,y+
        decb
        bne     InstallTrampoline

        lbsr    ColdBootLoadSystem
        bcs     ColdBootFail

        ldx     #CPM_WORK_BASE
        ldu     #CPM_WORK_LEN
        clra
ColdClearWorkspace
        sta     ,x+
        leau    -1,u
        cmpu    #0
        bne     ColdClearWorkspace

        lda     #$C3
        sta     >$0000
        ldd     #$00F2
        std     >$0001
        clra
        sta     >$0003
        sta     >$0004
        clr     MBOX_CMD
        clr     MBOX_STATUS
        jmp     TRAMPOLINE_BASE

ColdBootFail
        bra     ColdBootFail

ServiceLoop
        ldb     MBOX_CMD
        lbeq    ServiceDone
        cmpb    #MBCMD_READ
        beq     ServiceRead
        cmpb    #MBCMD_WRITE
        beq     ServiceWrite
        cmpb    #MBCMD_WBOOT
        lbeq    ServiceWBoot
        cmpb    #MBCMD_LOCAL_CONST
        lbeq    ServiceLocalConst
        cmpb    #MBCMD_LOCAL_CONIN
        lbeq    ServiceLocalIn
        cmpb    #MBCMD_LOCAL_CONOUT
        lbeq    ServiceLocalOut

ServiceBad
        lda     #MBSTAT_ERROR
        sta     MBOX_STATUS
        lbra    ServiceDone

ServiceRead
        lbsr    ValidateDiskRequest
        lbcs    ServiceBad
        lbsr    ResolveLogicalDrive
        lbcs    ServiceBad
        lbsr    DecodeLogicalSector
        lbcs    ServiceBad
        lda     PhysIs2HD
        bne     ServiceRead2HD
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
        lbsr    ResolveLogicalDrive
        lbcs    ServiceBad
        lbsr    DecodeLogicalSector
        lbcs    ServiceBad
        lda     PhysIs2HD
        bne     ServiceWrite2HD
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

* Local console services use the FM-11 Display Sub System protocol proven by
* the NitrOS-9 fm11console driver.  Output is native FM-11 character output;
* ANSI/VT100 translation is intentionally left for a later layer.
ServiceLocalOut
        lda     MBOX_DATA
        lbsr    LocalPutC
        lbcs    ServiceBad
        lda     #MBSTAT_OK
        sta     MBOX_STATUS
        bra     ServiceDone

ServiceLocalConst
        lbsr    LocalKeyPoll
        lbcs    ServiceBad
        lda     LocalKeyValid
        beq     SlcNone
        lda     #$FF
        bra     SlcStore
SlcNone
        clra
SlcStore
        sta     MBOX_DATA
        lda     #MBSTAT_OK
        sta     MBOX_STATUS
        bra     ServiceDone

ServiceLocalIn
SliWait
        lbsr    LocalKeyPoll
        lbcs    ServiceBad
        tst     LocalKeyValid
        beq     SliWait
        lda     LocalKeyChar
        sta     MBOX_DATA
        clr     LocalKeyValid
        lda     #MBSTAT_OK
        sta     MBOX_STATUS

ServiceDone
        clr     MBOX_CMD
        jmp     TRAMPOLINE_BASE

* Send A through Display Sub System CHARACTER OUT ($12).  FD05 bit 7 controls
* the subsystem while bit 0 remains clear so the 6809 retains the machine.
LocalPutC
        pshs    b,x
        tfr     a,b
        ldx     #SUB_WAIT_MAX
LpcWaitReady
        lda     >CPUCTL
        bpl     LpcHalt
        leax    -1,x
        cmpx    #0
        bne     LpcWaitReady
        bra     LpcFail
LpcHalt
        lda     #SUB_HALT
        sta     >CPUCTL
        ldx     #SUB_WAIT_MAX
LpcWaitHalt
        lda     >CPUCTL
        bmi     LpcInstall
        leax    -1,x
        cmpx    #0
        bne     LpcWaitHalt
        clr     >CPUCTL
        bra     LpcFail
LpcInstall
        clr     >FM11_SUB_SHARED
        clr     >FM11_SUB_SHARED+1
        lda     #SUB_CHAR_OUT
        sta     >FM11_SUB_SHARED+2
        stb     >FM11_SUB_SHARED+3
        clr     >CPUCTL
        ldx     #SUB_WAIT_MAX
LpcWaitDone
        lda     >CPUCTL
        bpl     LpcDone
        leax    -1,x
        cmpx    #0
        bne     LpcWaitDone
LpcFail
        orcc    #$01
        puls    b,x,pc
LpcDone
        andcc   #$FE
        puls    b,x,pc

* Poll INKEY 2 ($2D).  ASCII/control keys are cached for CONST/CONIN.  The
* confirmed FM-11 extended DEL code $0114 is normalized to ASCII DEL; other
* extended keys are ignored until the ANSI keyboard-sequence layer is added.
LocalKeyPoll
        tst     LocalKeyValid
        bne     LkpReady
        lbsr    LocalKeyFetch
        bcs     LkpFail
        tsta
        beq     LkpNone
        sta     LocalKeyChar
        lda     #1
        sta     LocalKeyValid
LkpReady
        andcc   #$FE
        rts
LkpNone
        andcc   #$FE
        rts
LkpFail
        orcc    #$01
        rts

LocalKeyFetch
        pshs    b,x
        ldx     #SUB_WAIT_MAX
LkfWaitReady
        lda     >CPUCTL
        bpl     LkfHalt
        leax    -1,x
        cmpx    #0
        bne     LkfWaitReady
        bra     LkfFail
LkfHalt
        lda     #SUB_HALT
        sta     >CPUCTL
        ldx     #SUB_WAIT_MAX
LkfWaitHalt
        lda     >CPUCTL
        bmi     LkfInstall
        leax    -1,x
        cmpx    #0
        bne     LkfWaitHalt
        clr     >CPUCTL
        bra     LkfFail
LkfInstall
        clr     >FM11_SUB_SHARED
        clr     >FM11_SUB_SHARED+1
        lda     #SUB_INKEY2
        sta     >FM11_SUB_SHARED+2
        clr     >FM11_SUB_SHARED+3
        clr     >FM11_SUB_SHARED+4
        clr     >CPUCTL
        ldx     #SUB_WAIT_MAX
LkfWaitDone
        lda     >CPUCTL
        bpl     LkfResult
        leax    -1,x
        cmpx    #0
        bne     LkfWaitDone
        bra     LkfFail
LkfResult
        lda     >FM11_SUB_SHARED+3
        beq     LkfAscii
        cmpa    #$01
        bne     LkfNoKey
        lda     >FM11_SUB_SHARED+4
        cmpa    #$14
        bne     LkfNoKey
        lda     #$7F
        andcc   #$FE
        puls    b,x,pc
LkfAscii
        lda     >FM11_SUB_SHARED+4
        andcc   #$FE
        puls    b,x,pc
LkfNoKey
        clra
        andcc   #$FE
        puls    b,x,pc
LkfFail
        clra
        orcc    #$01
        puls    b,x,pc

ValidateDiskRequest
        lda     MBOX_DRIVE
        cmpa    #8
        bhs     VdrBad
        andcc   #$FE
        rts
VdrBad
        orcc    #$01
        rts

ResolveLogicalDrive
        lda     MBOX_DRIVE
        cmpa    #8
        bhs     RldBad
        anda    #$03
        sta     PhysDrive
        lda     BOOTTYPE
        anda    #$01
        sta     PhysIs2HD
        lda     MBOX_DRIVE
        bita    #$04
        beq     RldDone
        lda     PhysIs2HD
        eora    #$01
        sta     PhysIs2HD
RldDone
        andcc   #$FE
        rts
RldBad
        orcc    #$01
        rts

ValidateDmaRange
        ldd     MBOX_DMA_H
        cmpd    #$FB80
        bhi     VdmBad
        andcc   #$FE
        rts
VdmBad
        orcc    #$01
        rts

DecodeLogicalSector
        lda     MBOX_TRACK_H
        bne     DlsBad
        lda     MBOX_TRACK_L
        sta     PhysTrack
        lda     MBOX_SECTOR_H
        bne     DlsBad
        ldb     MBOX_SECTOR_L
        lda     PhysIs2HD
        bne     Dls2HD

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
        lda     PhysDrive
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

MiniDmaSetupPrivate
        clr     DMA0_MODE
        tfr     x,d
        addd    #IOSERVER_PHYS_DELTA
        sta     DMA0_ADDR_H
        stb     DMA0_ADDR_L
        lda     #$01
        sta     DMA0_BANK
        sta     DMA0_COUNT_H
        clr     DMA0_COUNT_L
        rts

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

MiniFdcReadSector
        lbsr    MiniFdcSelect
        lda     MINIFDC_IRQ
        ldx     #PhysBuf
        lbsr    MiniDmaSetupPrivate
        bra     MiniFdcReadArmed

MiniFdcReadWBoot
        lbsr    MiniFdcSelect
        lda     MINIFDC_IRQ
        ldx     WBootDest
        lbsr    MiniDmaSetupBank0
        bra     MiniFdcReadArmed

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

StdFdcSelect
        lda     PhysDrive
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

StdFdcWaitType1
        ldx     #$FFFF
SftWait
        lda     STDFDC_STATUS
        bita    #FDC_ST_BUSY
        beq     SftDone
        leax    -1,x
        cmpx    #0
        bne     SftWait
        bra     SftFail
SftDone
        bita    #FDC_SEEKERR
        bne     SftFail
        lda     STDFDC_IRQ
        andcc   #$FE
        rts
SftFail
        lda     STDFDC_IRQ
        orcc    #$01
        rts

StdFdcPrepareSystemTrack
        clr     STDFDC_DRIVE
        clr     STDFDC_SIDE
        lda     STDFDC_IRQ
        lda     #FDC_CMD_RESTORE
        sta     STDFDC_STATUS
        lbsr    StdFdcWaitType1
        bcs     SfpFail
        lda     #SYSTEM_TRACK
        sta     STDFDC_DATA
        lda     #FDC_CMD_SEEK
        sta     STDFDC_STATUS
        lbsr    StdFdcWaitType1
        bcs     SfpFail
        lda     STDFDC_TRACK
        cmpa    #SYSTEM_TRACK
        bne     SfpFail
        andcc   #$FE
        rts
SfpFail
        orcc    #$01
        rts

StdDmaSetupPrivate
        clr     DMA1_MODE
        ldx     #PhysBuf
        tfr     x,d
        addd    #IOSERVER_PHYS_DELTA
        sta     DMA1_ADDR_H
        stb     DMA1_ADDR_L
        lda     #$01
        sta     DMA1_BANK
        sta     DMA1_COUNT_H
        clr     DMA1_COUNT_L
        rts

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

* Copy a 256-byte Standard-FDC sector from PhysBuf to WBootDest using the
* existing MMR window copy path.  This avoids consuming another DMA setup path.
StdFdcReadWBoot
        lbsr    StdFdcReadSector
        bcs     SrwFail
        ldd     WBootDest
        std     MBOX_DMA_H
        clr     PhysHalf
        lbsr    CopyReadHalfToDma
        bcs     SrwFail
        ldd     WBootDest
        addd    #128
        std     MBOX_DMA_H
        lda     #1
        sta     PhysHalf
        lbsr    CopyReadHalfToDma
SrwFail
        rts

PrepareBootSystemTrack
        lda     BOOTTYPE
        bne     Pbst2HD
        lbra    MiniFdcPrepareSystemTrack
Pbst2HD
        lbra    StdFdcPrepareSystemTrack

BootReadWBoot
        lda     PhysIs2HD
        bne     Brw2HD
        lbra    MiniFdcReadWBoot
Brw2HD
        lbra    StdFdcReadWBoot

AdvanceSystemSector
        inc     PhysSector
        lda     PhysIs2HD
        beq     Ass2D
        lda     PhysSector
        cmpa    #27
        blo     AssDone
        bra     AssWrap
Ass2D
        lda     PhysSector
        cmpa    #17
        blo     AssDone
AssWrap
        lda     #1
        sta     PhysSector
        lda     #1
        sta     PhysSide
AssDone
        rts

InitBootSystemRead
        clr     MBOX_DRIVE
        clr     PhysDrive
        lda     BOOTTYPE
        anda    #$01
        sta     PhysIs2HD
        lda     #SYSTEM_TRACK
        sta     PhysTrack
        clr     PhysSide
        lda     #1
        sta     PhysSector
        ldx     #CPM_SYSTEM_DEST
        stx     WBootDest
        rts

ColdBootLoadSystem
        lbsr    PrepareBootSystemTrack
        bcs     CblFail
        lbsr    InitBootSystemRead
        ldu     #CPM_SYSTEM_SECTORS
CblSector
        lbsr    BootReadWBoot
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

WarmBootReload
        lbsr    PrepareBootSystemTrack
        bcs     WbrFail
        lbsr    InitBootSystemRead
        ldu     #CPM_WBOOT_SECTORS
WbrSector
        lbsr    BootReadWBoot
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

MapZ80DmaWindow
        lda     MMR_PAGE_C
        sta     SavedMmrC
        ldy     MBOX_DMA_H
        tfr     y,d
        lsra
        lsra
        lsra
        lsra
        sta     MMR_PAGE_C
        tfr     y,d
        anda    #$0F
        ora     #$C0
        tfr     d,y
        rts

RestoreZ80Window
        lda     SavedMmrC
        sta     MMR_PAGE_C
        rts

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
        inc     MMR_PAGE_C
        ldy     #Z80_WINDOW_BASE
        bra     CrhLoop
CrhDone
        lbsr    RestoreZ80Window
        andcc   #$FE
        rts
CrhBad
        orcc    #$01
        rts

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
        inc     MMR_PAGE_C
        ldy     #Z80_WINDOW_BASE
        bra     CwhLoop
CwhDone
        lbsr    RestoreZ80Window
        andcc   #$FE
        rts
CwhBad
        orcc    #$01
        rts

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
PhysDrive       rmb     1
PhysIs2HD       rmb     1
WBootDest       rmb     2
SavedMmrC       rmb     1
LocalKeyValid   rmb     1
LocalKeyChar    rmb     1
PhysBuf         rmb     256
