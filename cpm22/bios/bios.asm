; FM-11 CP/M 2.2 BIOS
;
; 62K system layout:
;   CCP  = DC00h
;   BDOS = E400h
;   BIOS = F200h
;   6809 resident service = physical RAM above 10000h
;   disk workspace        = F970h-FBE7h
;   boot type             = FBF5h (0=2D, 1=2HD)
;   mailbox               = FBF6h-FBFFh
;
; Z80 syntax for z80asm.

        include "fm11.inc"

CCPBASE:        equ     0DC00h
BDOSENT:        equ     0E406h
BIOSBASE:       equ     0F200h
BOOTTYPE:       equ     0FBF5h
BOOT_2D:        equ     00h
BOOT_2HD:       equ     01h

; CP/M mutable disk workspace is packed directly below the shared boot-type
; byte and mailbox. All eight ALVs reserve the larger 2HD size so logical
; drive letters can swap controller families according to the boot source.
DIRBUF:         equ     0F970h
CSV0:           equ     0F9F0h
CSV1:           equ     CSV0+32
CSV2:           equ     CSV1+32
CSV3:           equ     CSV2+32
CSV4:           equ     CSV3+32
CSV5:           equ     CSV4+32
CSV6:           equ     CSV5+32
CSV7:           equ     CSV6+32
ALV0:           equ     0FAF0h
ALV1:           equ     ALV0+31
ALV2:           equ     ALV1+31
ALV3:           equ     ALV2+31
ALV4:           equ     ALV3+31
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
        ld      (0004h),a       ; current disk/user = user 0, A:
        ld      (curdrv),a
        ld      hl,0080h
        ld      (curdma),hl
        call    serial_init
        call    setvec
        xor     a
        ld      c,a             ; CCP entry C = uuuudddd = 00h
        jp      CCPBASE

; Reload CCP+BDOS from the reserved system tracks on the boot disk.
; CP/M page zero byte 0004h is uuuudddd: high nibble = user number,
; low nibble = current drive.  CCP requires that complete byte in C on entry.
;
; WBOOT can be entered from inside BDOS via JP 0000h, leaving SP in memory
; that is part of the CCP/BDOS image about to be reloaded.  Switch to a fixed
; stack immediately below the BIOS disk workspace before making any calls.
; F960h lies above the reload range (DC00h-F1FFh), while the downward-growing
; stack remains below DIRBUF at F970h.
;
; A fatal BDOS disk error can leave 0004h naming the drive that failed.  Before
; restoring a non-A: drive after WBOOT, probe its first data track.  If the
; drive/media is unavailable, fall back to A:, whose availability has already
; been proven by the successful system reload above.
wboot:
        ld      sp,0F960h
        ld      a,(0004h)
        ld      (wbootinfo),a
.wboot_retry:
        ld      a,MBCMD_WBOOT
        call    mbox_simple
        or      a
        jr      nz,.wboot_retry ; retry on boot-media/FDC error

        ld      a,(wbootinfo)
        and     00Fh
        cp      8
        jr      nc,.wboot_fallback
        or      a
        jr      z,.wboot_drive_ok

        ld      (curdrv),a
        ld      bc,2            ; OFF=2 for both supported floppy formats
        ld      (curtrk),bc
        ld      bc,0
        ld      (cursec),bc
        ld      hl,DIRBUF
        ld      (curdma),hl
        ld      a,MBCMD_READ
        call    disk_call
        or      a
        jr      z,.wboot_drive_ok

.wboot_fallback:
        ld      a,(wbootinfo)
        and     0F0h            ; preserve user, select boot drive A:
        ld      (wbootinfo),a

.wboot_drive_ok:
        ld      a,(wbootinfo)
        ld      (0004h),a
        ld      c,a
        and     00Fh
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

; CP/M requires CONST to return 00h if no character is ready and FFh if one
; is ready.  Do not return the raw 8251 RxRDY bit (02h): BDOS masks bit 0
; while polling for console break/status input.
const:
        ld      a,(FM11_SER_STAT)
        and     I8251_RXRDY
        ret     z
        ld      a,0FFh
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

; C = CP/M drive number 0..7.  A:-D: always name the controller family from
; which CP/M booted; E:-H: name the other family.  BOOTTYPE=0 means
; A:-D:=2D and E:-H:=2HD. BOOTTYPE=1 reverses those assignments.
; Returns HL=DPH or HL=0 if unsupported. The selected DPH's DPB pointer is
; patched on every call so the same logical drive can describe either format.
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
        ex      de,hl           ; HL = selected DPH

        push    hl
        ld      a,(BOOTTYPE)
        and     01h             ; 0=2D primary, 1=2HD primary
        ld      b,a
        ld      a,c
        and     04h             ; E:-H: use the opposite controller family
        jr      z,.have_kind
        ld      a,b
        xor     01h
        jr      .pick_dpb
.have_kind:
        ld      a,b
.pick_dpb:
        ld      de,dpb2d
        or      a
        jr      z,.patch_dpb
        ld      de,dpb2hd
.patch_dpb:
        pop     hl
        push    hl
        ld      bc,10           ; DPH+10 = DPB pointer
        add     hl,bc
        ld      (hl),e
        inc     hl
        ld      (hl),d
        pop     hl
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

; DPH: XLT, 3 scratch words, DIRBUF, DPB, CSV, ALV.
; The DPB field is patched by SELDSK according to BOOTTYPE.

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
wbootinfo:
        db      0

        end
