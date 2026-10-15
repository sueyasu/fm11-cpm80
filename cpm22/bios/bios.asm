; FM-11 CP/M 2.2 BIOS
;
; 56K system layout compatible with the Fujitsu memory arrangement:
;   CCP  = C400h
;   BDOS = CC00h
;   BIOS = DA00h
;   6809 resident service starts at DE00h
;
; Intel 8080 syntax for asm8080.

        include "../../include/z80/fm11.inc"

CCPBASE         equ     0C400h
BDOSENT         equ     0CC06h
BIOSBASE        equ     0DA00h

; CP/M mutable disk workspace lives in RAM shared with the 6809 service,
; but outside the service's DE00-EFFF code reservation.  These addresses
; do not emit bytes into the BIOS image.
DIRBUF          equ     0F000h
CSV0            equ     0F080h
CSV1            equ     CSV0+32
CSV2            equ     CSV1+32
CSV3            equ     CSV2+32
CSV4            equ     CSV3+32
CSV5            equ     CSV4+32
CSV6            equ     CSV5+32
CSV7            equ     CSV6+32
ALV0            equ     0F180h
ALV1            equ     ALV0+19
ALV2            equ     ALV1+19
ALV3            equ     ALV2+19
ALV4            equ     ALV3+19
ALV5            equ     ALV4+31
ALV6            equ     ALV5+31
ALV7            equ     ALV6+31

        org     BIOSBASE

        jmp     boot
        jmp     wboot
        jmp     const
        jmp     conin
        jmp     conout
        jmp     list
        jmp     punch
        jmp     reader
        jmp     home
        jmp     seldsk
        jmp     settrk
        jmp     setsec
        jmp     setdma
        jmp     read
        jmp     write
        jmp     listst
        jmp     sectran

; ----------------------------------------------------------------------
; BOOT / WBOOT
; ----------------------------------------------------------------------

boot:
        xra     a
        sta     curdrv
        lxi     h,0080h
        shld    curdma
        call    setvec
        jmp     CCPBASE

wboot:
        mvi     a,MBCMD_WBOOT
        call    mbox_simple
        ora     a
        jnz     wboot           ; warm boot loader not implemented yet
        call    setvec
        jmp     CCPBASE

setvec:
        mvi     a,0C3h          ; JMP opcode
        sta     0000h
        lxi     h,wboot
        shld    0001h
        sta     0005h
        lxi     h,BDOSENT
        shld    0006h
        ret

; ----------------------------------------------------------------------
; Console: direct access to the Z80-visible standard 8251.
; The 6809 loader/firmware initializes its mode/clock environment first.
; ----------------------------------------------------------------------

const:
        lda     FM11_SER_STAT
        ani     I8251_RXRDY
        ret

conin:
.conin_wait:
        lda     FM11_SER_STAT
        ani     I8251_RXRDY
        jz      .conin_wait
        lda     FM11_SER_DATA
        ani     07Fh
        ret

conout:
        push    psw
.conout_wait:
        lda     FM11_SER_STAT
        ani     I8251_TXRDY
        jz      .conout_wait
        pop     psw
        mov     a,c
        sta     FM11_SER_DATA
        ret

list:
        jmp     conout

punch:
        jmp     conout

reader:
        jmp     conin

listst:
        mvi     a,0FFh
        ret

; ----------------------------------------------------------------------
; Disk parameter state
; ----------------------------------------------------------------------

home:
        lxi     b,0
        jmp     settrk

; C = CP/M drive number.  A:-D: are 2D, E:-H: are 2HD.
; Returns HL=DPH or HL=0 if unsupported.
seldsk:
        mov     a,c
        cpi     8
        jnc     .bad_drive
        sta     curdrv
        mov     l,a
        mvi     h,0
        dad     h               ; word table
        lxi     d,dphtab
        dad     d
        mov     e,m
        inx     h
        mov     d,m
        xchg
        ret
.bad_drive:
        lxi     h,0
        ret

settrk:
        mov     h,b
        mov     l,c
        shld    curtrk
        ret

setsec:
        mov     h,b
        mov     l,c
        shld    cursec
        ret

setdma:
        mov     h,b
        mov     l,c
        shld    curdma
        ret

read:
        mvi     a,MBCMD_READ
        jmp     disk_call

write:
        mov     a,c
        sta     MBOX_FLAGS      ; CP/M write type for future optimisation
        mvi     a,MBCMD_WRITE
        jmp     disk_call

; BC = logical sector, DE = translation table.  No skew table initially.
sectran:
        mov     h,b
        mov     l,c
        ret

; ----------------------------------------------------------------------
; Z80 -> 6809 synchronous service call
; ----------------------------------------------------------------------

disk_call:
        sta     MBOX_CMD
        xra     a
        sta     MBOX_STATUS

        lda     curdrv
        sta     MBOX_DRIVE

        lhld    curtrk
        mov     a,h
        sta     MBOX_TRACK_H
        mov     a,l
        sta     MBOX_TRACK_L

        lhld    cursec
        mov     a,h
        sta     MBOX_SECTOR_H
        mov     a,l
        sta     MBOX_SECTOR_L

        lhld    curdma
        mov     a,h
        sta     MBOX_DMA_H
        mov     a,l
        sta     MBOX_DMA_L

        di
        xra     a
        sta     FM11_CPUCTL     ; stop Z80, resume 6809
        nop                     ; Z80 resumes here
        ei
        lda     MBOX_STATUS
        ora     a
        ret

mbox_simple:
        sta     MBOX_CMD
        xra     a
        sta     MBOX_STATUS
        di
        sta     FM11_CPUCTL
        nop
        ei
        lda     MBOX_STATUS
        ora     a
        ret

; ----------------------------------------------------------------------
; DPH / DPB
; ----------------------------------------------------------------------

; DPH: XLT, 3 scratch words, DIRBUF, DPB, CSV, ALV

dph0:
        dw      0,0,0,0,DIRBUF,dpb2d,CSV0,ALV0
dph1:
        dw      0,0,0,0,DIRBUF,dpb2d,CSV1,ALV1
dph2:
        dw      0,0,0,0,DIRBUF,dpb2d,CSV2,ALV2
dph3:
        dw      0,0,0,0,DIRBUF,dpb2d,CSV3,ALV3
dph4:
        dw      0,0,0,0,DIRBUF,dpb2hd,CSV4,ALV4
dph5:
        dw      0,0,0,0,DIRBUF,dpb2hd,CSV5,ALV5
dph6:
        dw      0,0,0,0,DIRBUF,dpb2hd,CSV6,ALV6
dph7:
        dw      0,0,0,0,DIRBUF,dpb2hd,CSV7,ALV7

dphtab:
        dw      dph0,dph1,dph2,dph3
        dw      dph4,dph5,dph6,dph7

; Fujitsu-compatible 2D DPB: 40 cyl, 2 sides, 16 x 256 B/side.
dpb2d:
        dw      64              ; SPT
        db      4               ; BSH, 2 KiB blocks
        db      15              ; BLM
        db      1               ; EXM
        dw      151             ; DSM
        dw      127             ; DRM
        db      0C0h            ; AL0
        db      00h             ; AL1
        dw      32              ; CKS
        dw      2               ; OFF

; Fujitsu-compatible 2HD DPB: 77 cyl, 2 sides, 26 x 256 B/side.
dpb2hd:
        dw      104             ; SPT
        db      5               ; BSH, 4 KiB blocks
        db      31              ; BLM
        db      3               ; EXM
        dw      242             ; DSM
        dw      127             ; DRM
        db      080h            ; AL0
        db      00h             ; AL1
        dw      32              ; CKS
        dw      2               ; OFF

curdrv:
        db      0
curtrk:
        dw      0
cursec:
        dw      0
curdma:
        dw      0080h

        end
