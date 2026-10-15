; FM-11 CP/M 2.2 BIOS
;
; 56K system layout compatible with the Fujitsu memory arrangement:
;   CCP  = C400h
;   BDOS = CC00h
;   BIOS = DA00h
;   6809 resident service = DE00h-EBFFh
;   mailbox              = EC00h
;
; Z80 syntax for z80asm.

        include "fm11.inc"

CCPBASE:        equ     0C400h
BDOSENT:        equ     0CC06h
BIOSBASE:       equ     0DA00h

; CP/M mutable disk workspace lives in fixed RAM above the shared service
; area. These addresses do not emit bytes into the BIOS image.
DIRBUF:         equ     0F000h
CSV0:           equ     0F080h
CSV1:           equ     CSV0+32
CSV2:           equ     CSV1+32
CSV3:           equ     CSV2+32
CSV4:           equ     CSV3+32
CSV5:           equ     CSV4+32
CSV6:           equ     CSV5+32
CSV7:           equ     CSV6+32
ALV0:           equ     0F180h
ALV1:           equ     ALV0+19
ALV2:           equ     ALV1+19
ALV3:           equ     ALV2+19
ALV4:           equ     ALV3+19
ALV5:           equ     ALV4+31
ALV6:           equ     ALV5+31
ALV7:           equ     ALV6+31

        org     BIOSBASE

        jp      boot
        jp      wboot
        jp      const
        jp      conin
        jp      conout
        jp      list
        jp      punch
        jp      reader
        jp      home
        jp      seldsk
        jp      settrk
        jp      setsec
        jp      setdma
        jp      read
        jp      write
        jp      listst
        jp      sectran

; ----------------------------------------------------------------------
; BOOT / WBOOT
; ----------------------------------------------------------------------

boot:
        xor     a
        ld      (FM11_BANK),a   ; CP/M 2.2 always runs with Z80 bank 0
        ld      (0003h),a       ; IOBYTE
        ld      (0004h),a       ; current disk = A:
        ld      (curdrv),a
        ld      hl,0080h
        ld      (curdma),hl
        call    serial_init
        call    setvec
        jp      CCPBASE

; Reload CCP+BDOS+BIOS from the reserved warm-boot copy on A: system tracks.
; The 6809 performs the physical I/O while the Z80 is stopped.  The BIOS
; code being executed is replaced by an identical copy, so execution safely
; resumes at the instruction following the CPU hand-off.
wboot:
        ld      a,MBCMD_WBOOT
        call    mbox_simple
        or      a
        jr      nz,wboot        ; retry on media/FDC error

        ld      a,(0004h)       ; preserve CP/M current drive across reload
        ld      (curdrv),a
        ld      hl,0080h
        ld      (curdma),hl
        call    setvec
        jp      CCPBASE

setvec:
        ld      a,0C3h          ; JP opcode
        ld      (0000h),a
        ld      hl,wboot
        ld      (0001h),hl
        ld      (0005h),a
        ld      hl,BDOSENT
        ld      (0006h),hl
        ret

; ----------------------------------------------------------------------
; Console: direct access to the Z80-visible standard 8251.
;
; Use the conventional defensive 8251 initialization sequence. Three zero
; writes force a known command/mode phase, 40h performs an internal reset,
; 4Eh selects asynchronous x16, 8 data bits, no parity, one stop bit, and
; 27h enables Tx/Rx with DTR/RTS asserted.
;
; This also matches the FM-11 emulator's USART state machine, whose reset
; state otherwise leaves TXRDY low and would make the first CONOUT wait
; forever after the 6809 hands control to the Z80.
; ----------------------------------------------------------------------

serial_init:
        xor     a
        ld      (FM11_SER_STAT),a
        ld      (FM11_SER_STAT),a
        ld      (FM11_SER_STAT),a
        ld      a,040h
        ld      (FM11_SER_STAT),a
        ld      a,04Eh
        ld      (FM11_SER_STAT),a
        ld      a,027h
        ld      (FM11_SER_STAT),a
        ret

const:
        ld      a,(FM11_SER_STAT)
        and     I8251_RXRDY
        ret

conin:
.conin_wait:
        ld      a,(FM11_SER_STAT)
        and     I8251_RXRDY
        jr      z,.conin_wait
        ld      a,(FM11_SER_DATA)
        and     07Fh
        ret

conout:
        push    af
.conout_wait:
        ld      a,(FM11_SER_STAT)
        and     I8251_TXRDY
        jr      z,.conout_wait
        pop     af
        ld      a,c
        ld      (FM11_SER_DATA),a
        ret

list:
        jp      conout

punch:
        jp      conout

reader:
        jp      conin

listst:
        ld      a,0FFh
        ret

; ----------------------------------------------------------------------
; Disk parameter state
; ----------------------------------------------------------------------

home:
        ld      bc,0
        jp      settrk

; C = CP/M drive number. A:-D: are 2D, E:-H: are 2HD.
; Returns HL=DPH or HL=0 if unsupported.
seldsk:
        ld      a,c
        cp      8
        jr      nc,.bad_drive
        ld      (curdrv),a
        ld      l,a
        ld      h,0
        add     hl,hl           ; word table
        ld      de,dphtab
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ret
.bad_drive:
        ld      hl,0
        ret

settrk:
        ld      (curtrk),bc
        ret

setsec:
        ld      (cursec),bc
        ret

setdma:
        ld      (curdma),bc
        ret

read:
        ld      a,MBCMD_READ
        jp      disk_call

write:
        ld      a,c
        ld      (MBOX_FLAGS),a  ; CP/M write type for future optimisation
        ld      a,MBCMD_WRITE
        jp      disk_call

; BC = logical sector, DE = translation table. No skew table initially.
sectran:
        ld      h,b
        ld      l,c
        ret

; ----------------------------------------------------------------------
; Z80 -> 6809 synchronous service call
; ----------------------------------------------------------------------

disk_call:
        ld      (MBOX_CMD),a
        xor     a
        ld      (MBOX_STATUS),a

        ld      a,(curdrv)
        ld      (MBOX_DRIVE),a

        ld      hl,(curtrk)
        ld      a,h
        ld      (MBOX_TRACK_H),a
        ld      a,l
        ld      (MBOX_TRACK_L),a

        ld      hl,(cursec)
        ld      a,h
        ld      (MBOX_SECTOR_H),a
        ld      a,l
        ld      (MBOX_SECTOR_L),a

        ld      hl,(curdma)
        ld      a,h
        ld      (MBOX_DMA_H),a
        ld      a,l
        ld      (MBOX_DMA_L),a

        di
        xor     a
        ld      (FM11_CPUCTL),a ; stop Z80, resume 6809
        nop                     ; Z80 resumes here
        ei
        ld      a,(MBOX_STATUS)
        or      a
        ret

mbox_simple:
        ld      (MBOX_CMD),a
        xor     a
        ld      (MBOX_STATUS),a
        di
        ld      (FM11_CPUCTL),a
        nop
        ei
        ld      a,(MBOX_STATUS)
        or      a
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
