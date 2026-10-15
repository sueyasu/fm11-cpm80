; FM-11 CP/M 2.2 BIOS skeleton
;
; Target memory layout follows the Fujitsu 56K system:
;   CCP  = C400h
;   BDOS = CC00h
;   BIOS = DA00h
;
; Syntax is intentionally kept to conventional Intel/Z80 notation.  The
; exact assembler/toolchain will be fixed once the first build is wired up.

        include "../../include/z80/fm11.inc"

CCPBASE         equ     0C400h
BDOSENT         equ     0CC06h
BIOSBASE        equ     0DA00h

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
        ld      (curdrv),a
        ld      hl,0080h
        ld      (curdma),hl
        call    setvec
        jp      CCPBASE

wboot:
        ld      a,MBCMD_WBOOT
        call    mbox_simple
        or      a
        jr      nz,wboot       ; low-level warm boot is not implemented yet
        call    setvec
        jp      CCPBASE

setvec:
        ld      a,0C3h         ; JP opcode
        ld      (0000h),a
        ld      hl,wboot
        ld      (0001h),hl
        ld      (0005h),a
        ld      hl,BDOSENT
        ld      (0006h),hl
        ret

; ----------------------------------------------------------------------
; Console: direct access to the Z80-visible standard 8251.
; The 6809 loader/firmware must initialize the serial interface first.
; ----------------------------------------------------------------------

const:
        ld      a,(FM11_SER_STAT)
        and     I8251_RXRDY
        ret                     ; 0=no char, nonzero=ready

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

; C = CP/M drive number.  A:-D: are 2D, E:-H: are 2HD.
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

; HL=logical sector, DE=translation table.  No skew table initially.
sectran:
        ex      de,hl           ; preserve DE conventionally
        ex      de,hl
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
        nop                     ; execution resumes here
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
DPH macro dpb,csv,alv
        dw      0
        dw      0,0,0
        dw      dirbuf
        dw      dpb
        dw      csv
        dw      alv
        endm

dph0:   DPH     dpb2d,csv0,alv0
dph1:   DPH     dpb2d,csv1,alv1
dph2:   DPH     dpb2d,csv2,alv2
dph3:   DPH     dpb2d,csv3,alv3
dph4:   DPH     dpb2hd,csv4,alv4
dph5:   DPH     dpb2hd,csv5,alv5
dph6:   DPH     dpb2hd,csv6,alv6
dph7:   DPH     dpb2hd,csv7,alv7

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

curdrv: db      0
curtrk: dw      0
cursec: dw      0
curdma: dw      0080h

dirbuf: ds      128

; 32-byte check vectors per drive.
csv0:   ds      32
csv1:   ds      32
csv2:   ds      32
csv3:   ds      32
csv4:   ds      32
csv5:   ds      32
csv6:   ds      32
csv7:   ds      32

; Allocation vectors: ceil((DSM+1)/8).
alv0:   ds      19
alv1:   ds      19
alv2:   ds      19
alv3:   ds      19
alv4:   ds      31
alv5:   ds      31
alv6:   ds      31
alv7:   ds      31
