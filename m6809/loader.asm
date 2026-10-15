* FM-11 CP/M-80 6809 stage-2 cold loader.
*
* This image is position independent. It embeds the Z80 56K CP/M system
* image and the resident 6809 I/O server, copies them to their execution
* addresses, installs a Z80 reset trampoline, then enters IoServerStart.
*
* Stage 1 must load the entire loader.bin to RAM that does not overlap the
* destination area C400-F247 and jump to the first byte of this image.

        include "fm11.inc"

CPM_SYSTEM_BASE equ     $C400
IOSERVER_BASE   equ     $DE00
MBOX_LEN        equ     10
CPM_WORK_BASE   equ     $F000
CPM_WORK_LEN    equ     $0248

LoaderEntry
        orcc    #$50            * IRQ/FIRQ off during cold boot

* Copy CCP+BDOS+BIOS (C400-DDFF).
        leax    SystemPayload,pcr
        ldy     #CPM_SYSTEM_BASE
        ldu     #SystemPayloadEnd-SystemPayload
CopySystem
        lda     ,x+
        sta     ,y+
        leau    -1,u
        cmpu    #0
        bne     CopySystem

* Copy resident 6809 I/O service (DE00-EBFF maximum).
        leax    IoServerPayload,pcr
        ldy     #IOSERVER_BASE
        ldu     #IoServerPayloadEnd-IoServerPayload
CopyIoServer
        lda     ,x+
        sta     ,y+
        leau    -1,u
        cmpu    #0
        bne     CopyIoServer

* Clear Z80/6809 mailbox.
        ldx     #MBOX_BASE
        ldu     #MBOX_LEN
        clra
ClearMailbox
        sta     ,x+
        leau    -1,u
        cmpu    #0
        bne     ClearMailbox

* Clear CP/M mutable DIRBUF/CSV/ALV workspace.
        ldx     #CPM_WORK_BASE
        ldu     #CPM_WORK_LEN
        clra
ClearWorkspace
        sta     ,x+
        leau    -1,u
        cmpu    #0
        bne     ClearWorkspace

* Z80 is released from WAIT with PC=0000. Install:
*     0000: C3 00 DA    JP DA00
        lda     #$C3
        sta     $0000
        ldd     #$00DA
        std     $0001

* Conventional CP/M IOBYTE/current-disk bytes start cleared.
        clra
        sta     $0003
        sta     $0004

* IoServerStart performs the initial FD05 hand-off to the Z80.
        jmp     IOSERVER_BASE

SystemPayload
        includebin "build/cpm22/system56.bin"
SystemPayloadEnd

IoServerPayload
        includebin "build/6809/ioserver.bin"
IoServerPayloadEnd
