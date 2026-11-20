; FM-11 CP/M 2.2 common CBIOS
;
; 62K system layout:
;   CCP  = DC00h
;   BDOS = E400h
;   BIOS = F200h
;   disk workspace        = F970h-FBE7h
;   boot drive            = FBF4h (0=A, 4=E)
;   boot type             = FBF5h (0=2D, 1=2HD)
;   mailbox               = FBF6h-FBFFh
;
; Intel 8080 syntax for asm8080. All hardware access is via the mailbox
; and the target-specific CPU_INIT / CPU_IOCALL hooks.

CCPBASE EQU     0DC00H
BDOSENT EQU     0E406H
BIOSBASE EQU     0F200H
WBOOTENT EQU     BIOSBASE+3
BOOTTYPE EQU     0FBF5H
BOOT_2D EQU     00H
BOOT_2HD EQU     01H

; CP/M mutable disk workspace is packed directly below the shared boot-type
; byte and mailbox. All eight ALVs retain the larger 2HD size to keep
; the existing workspace layout.
DIRBUF EQU     0F970H
CSV0 EQU     0F9F0H
CSV1 EQU     CSV0+32
CSV2 EQU     CSV1+32
CSV3 EQU     CSV2+32
CSV4 EQU     CSV3+32
CSV5 EQU     CSV4+32
CSV6 EQU     CSV5+32
CSV7 EQU     CSV6+32
ALV0 EQU     0FAF0H
ALV1 EQU     ALV0+31
ALV2 EQU     ALV1+31
ALV3 EQU     ALV2+31
ALV4 EQU     ALV3+31
ALV5 EQU     ALV4+31
ALV6 EQU     ALV5+31
ALV7 EQU     ALV6+31

        ORG     BIOSBASE

        JMP     BOOT
        JMP     WBOOT
        JMP     CONST
        JMP     CONIN
        JMP     CONOUT
        JMP     LIST
        JMP     PUNCH
        JMP     READER
        JMP     HOME
        JMP     SELDSK
        JMP     SETTRK
        JMP     SETSEC
        JMP     SETDMA
        JMP     READ
        JMP     WRITE
        JMP     LISTST
        JMP     SECTRAN

; ----------------------------------------------------------------------
; BOOT / WBOOT
; ----------------------------------------------------------------------

BOOT EQU     $
        ; Establish the common boot stack before calling any target hook.
        ; CPU_INIT may clobber A/flags, but must return on this stack.
        LXI     SP,0F960H
        CALL    CPU_INIT
        MVI     A,1
        STA     0003H  ; IOBYTE: CON:=CRT selects FM-11 local console
        XRA     A
        STA     UC1_NEXT
        LDA     BOOTDRV
        STA     0004H  ; user 0, actual boot drive
        STA     CURDRV
        LXI     H,0080H
        SHLD    CURDMA
        CALL    SETVEC
        CALL    COLD_BANNER
        LDA     BOOTDRV
        MOV     C,A  ; CCP entry C = uuuudddd
        JMP     CCPBASE

; Cold-boot presentation is local-console only.  FM-11 native control $16
; clears both graphic and character screens.  Do not repeat this on WBOOT.
COLD_BANNER  MVI     C,016H
        CALL    LOCAL_CONOUT
        LXI     H,BOOTMSG
COLD_BANNER_COLD_BANNER_LOOP  MOV     A,M
        ORA     A
        JZ      COLD_BANNER_COLD_BANNER_DONE
        MOV     C,A
        PUSH    H
        CALL    LOCAL_CONOUT
        POP     H
        INX     H
        JMP     COLD_BANNER_COLD_BANNER_LOOP
COLD_BANNER_COLD_BANNER_DONE  MVI     C,00DH
        CALL    LOCAL_CONOUT
        MVI     C,00AH
        CALL    LOCAL_CONOUT
        RET

BOOTMSG  DB      'CP/M-80 v2.2 for FM-11 series.',0

; Reload CCP+BDOS from the reserved system tracks on the boot disk.
; CP/M page zero byte 0004h is uuuudddd: high nibble = user number,
; low nibble = current drive. CCP requires that complete byte in C on entry.
;
; WBOOT can be entered from inside BDOS via JP 0000h, leaving SP in memory
; that is part of the CCP/BDOS image about to be reloaded. Switch to a fixed
; stack immediately below the BIOS disk workspace before making any calls.
; F960h lies above the reload range (DC00h-F1FFh), while the downward-growing
; stack remains below DIRBUF at F970h.
;
; A fatal BDOS disk error can leave 0004h naming the drive that failed. Before
; restoring a non-boot drive after WBOOT, probe its first data track. If the
; drive/media is unavailable, fall back to the boot drive, whose availability has already
; been proven by the successful system reload above.
WBOOT   LXI     SP,0F960H
        LDA     0004H
        STA     WBOOTINFO
WBOOT_WBOOT_RETRY  MVI     A,MBCMD_WBOOT
        CALL    MBOX_SIMPLE
        ORA     A
        JNZ     WBOOT_WBOOT_RETRY  ; retry on boot-media/FDC error

        LDA     WBOOTINFO
        ANI     00FH
        CPI     8
        JNC     WBOOT_WBOOT_FALLBACK
        MOV     B,A
        LDA     BOOTDRV
        CMP     B
        JZ      WBOOT_WBOOT_DRIVE_OK
        MOV     A,B
        STA     CURDRV
        LXI     B,2  ; OFF=2 for both supported floppy formats
        PUSH    H
        MOV     H,B
        MOV     L,C
        SHLD    CURTRK
        POP     H
        LXI     B,0
        PUSH    H
        MOV     H,B
        MOV     L,C
        SHLD    CURSEC
        POP     H
        LXI     H,DIRBUF
        SHLD    CURDMA
        MVI     A,MBCMD_READ
        CALL    DISK_CALL
        ORA     A
        JZ      WBOOT_WBOOT_DRIVE_OK

WBOOT_WBOOT_FALLBACK  LDA     WBOOTINFO
        ANI     0F0H  ; preserve user, select actual boot drive
        MOV     B,A
        LDA     BOOTDRV
        ORA     B
        STA     WBOOTINFO

WBOOT_WBOOT_DRIVE_OK  LDA     WBOOTINFO
        STA     0004H
        MOV     C,A
        ANI     00FH
        STA     CURDRV
        LXI     H,0080H
        SHLD    CURDMA
        CALL    SETVEC
        JMP     CCPBASE

; CP/M page-zero ABI:
;   0000h-0002h = JP to the BIOS WBOOT jump-table entry
;   0003h       = IOBYTE
;   0004h       = current user/drive byte
;   0005h-0007h = JP to the BDOS entry
; Keep 0001h pointing at the WBOOT entry in the BIOS jump table, not at the
; wboot implementation routine.  CP/M software may derive the other BIOS
; entry points from this standard vector.
SETVEC  MVI     A,0C3H  ; JP opcode
        STA     0000H
        LXI     H,WBOOTENT
        SHLD    0001H
        STA     0005H
        LXI     H,BDOSENT
        SHLD    0006H
        RET

; ----------------------------------------------------------------------
; Console.
;
; CP/M IOBYTE bits 0-1 select CON:. CRT (01) is the default and selects the
; FM-11 local screen/keyboard through the resident I/O server. TTY (00)
; and BAT use the serial mailbox services; UC1 polls both inputs and mirrors output.
; LIST/PUNCH/READER stay on the serial device and do not follow CON:.
; USART initialization is performed by the native I/O server at cold boot.
; ----------------------------------------------------------------------

CONST   LDA     0003H
        ANI     03H
        CPI     01H
        JZ      LOCAL_CONST
        CPI     03H
        JNZ     SERIAL_CONST
        CALL    LOCAL_CONST
        ORA     A
        RNZ

SERIAL_CONST  MVI     A,MBCMD_SERIAL_CONST
        JMP     SERIAL_STATUS

; Status services return 00h/FFh in MBOX_DATA; a service error is not ready.
SERIAL_STATUS  CALL    MBOX_SIMPLE
        ORA     A
        JNZ     SERIAL_NOT_READY
        LDA     MBOX_DATA
        ORA     A
        RET
SERIAL_NOT_READY  XRA     A
        RET

LOCAL_CONST  MVI     A,MBCMD_LOCAL_CONST
        CALL    MBOX_SIMPLE
        ORA     A
        JNZ     LOCAL_CONST_NOT_READY
        LDA     MBOX_DATA
        RET
LOCAL_CONST_NOT_READY  XRA     A
        RET

CONIN   LDA     0003H
        ANI     03H
        CPI     01H
        JZ      LOCAL_CONIN
        CPI     03H
        JZ      SHARED_CONIN

SERIAL_CONIN  MVI     A,MBCMD_SERIAL_CONIN
        CALL    MBOX_SIMPLE
        ORA     A
        JNZ     SERIAL_CONIN
        LDA     MBOX_DATA
        ANI     07FH
        RET

LOCAL_CONIN EQU     $
LOCAL_CONIN_LOCAL_CONIN_RETRY  MVI     A,MBCMD_LOCAL_CONIN
        CALL    MBOX_SIMPLE
        ORA     A
        JNZ     LOCAL_CONIN_LOCAL_CONIN_RETRY
        LDA     MBOX_DATA
        ANI     07FH
        RET

SHARED_CONIN  PUSH    B
SHARED_CONIN_SHARED_WAIT  CALL    LOCAL_CONST
        MOV     B,A
        CALL    SERIAL_CONST
        ORA     A
        JZ      SHARED_CONIN_NO_SERIAL
        MOV     A,B
        ORA     A
        JZ      SHARED_CONIN_SERIAL
        LDA     UC1_NEXT
        ORA     A
        JNZ     SHARED_CONIN_SERIAL
SHARED_CONIN_LOCAL  MVI     A,1
        STA     UC1_NEXT
        POP     B
        JMP     LOCAL_CONIN
SHARED_CONIN_NO_SERIAL  MOV     A,B
        ORA     A
        JZ      SHARED_CONIN_SHARED_WAIT
        JMP     SHARED_CONIN_LOCAL
SHARED_CONIN_SERIAL  XRA     A
        STA     UC1_NEXT
        POP     B
        JMP     SERIAL_CONIN

CONOUT  LDA     0003H
        ANI     03H
        CPI     01H
        JZ      LOCAL_CONOUT
        CPI     03H
        JZ      SHARED_CONOUT

SERIAL_CONOUT  PUSH    PSW
        MOV     A,C
        STA     MBOX_DATA
        MVI     A,MBCMD_SERIAL_CONOUT
        CALL    MBOX_SIMPLE
        POP     PSW
        MOV     A,C
        RET

; Mirror output without letting a stalled serial port block the local console.
; A timeout is not retried; the character has already been sent locally.
SHARED_CONOUT  CALL    LOCAL_CONOUT
        MOV     A,C
        STA     MBOX_DATA
        MVI     A,MBCMD_SERIAL_MIRROR
        JMP     MBOX_SIMPLE

LOCAL_CONOUT EQU     $
LOCAL_CONOUT_LOCAL_CONOUT_RETRY  MOV     A,C
        STA     MBOX_DATA
        MVI     A,MBCMD_LOCAL_CONOUT
        CALL    MBOX_SIMPLE
        ORA     A
        ; Do not replay a partially transmitted native escape.
        RET

LIST    JMP     SERIAL_CONOUT

PUNCH   JMP     SERIAL_CONOUT

READER  JMP     SERIAL_CONIN

LISTST  MVI     A,MBCMD_SERIAL_LISTST
        JMP     SERIAL_STATUS

; ----------------------------------------------------------------------
; Disk parameter state
; ----------------------------------------------------------------------

HOME    LXI     B,0
        JMP     SETTRK

; C = CP/M drive number 0..7. A:-D: always 2D, E:-H: always 2HD.
; Returns HL=DPH or HL=0 if unsupported. Each DPH has a fixed DPB.
SELDSK  MOV     A,C
        CPI     8
        JNC     SELDSK_BAD_DRIVE
        STA     CURDRV
        MOV     L,A
        MVI     H,0
        DAD     H  ; word table
        LXI     D,DPHTAB
        DAD     D
        MOV     E,M
        INX     H
        MOV     D,M
        XCHG      ; HL = selected DPH
        RET
SELDSK_BAD_DRIVE  LXI     H,0
        RET

SETTRK  PUSH    H
        MOV     H,B
        MOV     L,C
        SHLD    CURTRK
        POP     H
        RET

SETSEC  PUSH    H
        MOV     H,B
        MOV     L,C
        SHLD    CURSEC
        POP     H
        RET

SETDMA  PUSH    H
        MOV     H,B
        MOV     L,C
        SHLD    CURDMA
        POP     H
        RET

READ    MVI     A,MBCMD_READ
        JMP     DISK_CALL

WRITE   MOV     A,C
        STA     MBOX_FLAGS  ; CP/M write type for future optimisation
        MVI     A,MBCMD_WRITE
        JMP     DISK_CALL

; BC = logical sector, DE = translation table. No skew table initially.
SECTRAN  MOV     H,B
        MOV     L,C
        RET

; ----------------------------------------------------------------------
; Common synchronous mailbox service call
; ----------------------------------------------------------------------

DISK_CALL  STA     MBOX_CMD
        XRA     A
        STA     MBOX_STATUS

        LDA     CURDRV
        STA     MBOX_DRIVE

        LHLD    CURTRK
        MOV     A,H
        STA     MBOX_TRACK_H
        MOV     A,L
        STA     MBOX_TRACK_L

        LHLD    CURSEC
        MOV     A,H
        STA     MBOX_SECTOR_H
        MOV     A,L
        STA     MBOX_SECTOR_L

        LHLD    CURDMA
        MOV     A,H
        STA     MBOX_DMA_H
        MOV     A,L
        STA     MBOX_DMA_L

        JMP     MBOX_EXEC

MBOX_SIMPLE  STA     MBOX_CMD
        XRA     A
        STA     MBOX_STATUS

; Target hook executes the posted command synchronously. It must preserve
; BC, DE, HL and SP; A/flags may change. Only the common code interprets
; MBOX_STATUS, so every backend returns A and Z consistently to BIOS callers.
MBOX_EXEC  CALL    CPU_IOCALL
        LDA     MBOX_STATUS
        ORA     A
        RET

; ----------------------------------------------------------------------
; DPH / DPB
; ----------------------------------------------------------------------

; DPH: XLT, 3 scratch words, DIRBUF, DPB, CSV, ALV.
; The DPB field is fixed for each logical drive.

DPH0    DW      0,0,0,0,DIRBUF,DPB2D,CSV0,ALV0
DPH1    DW      0,0,0,0,DIRBUF,DPB2D,CSV1,ALV1
DPH2    DW      0,0,0,0,DIRBUF,DPB2D,CSV2,ALV2
DPH3    DW      0,0,0,0,DIRBUF,DPB2D,CSV3,ALV3
DPH4    DW      0,0,0,0,DIRBUF,DPB2HD,CSV4,ALV4
DPH5    DW      0,0,0,0,DIRBUF,DPB2HD,CSV5,ALV5
DPH6    DW      0,0,0,0,DIRBUF,DPB2HD,CSV6,ALV6
DPH7    DW      0,0,0,0,DIRBUF,DPB2HD,CSV7,ALV7

DPHTAB  DW      DPH0,DPH1,DPH2,DPH3
        DW      DPH4,DPH5,DPH6,DPH7

; Fujitsu-compatible 2D DPB: 40 cyl, 2 sides, 16 x 256 B/side.
DPB2D   DW      64  ; SPT
        DB      4  ; BSH, 2 KiB blocks
        DB      15  ; BLM
        DB      1  ; EXM
        DW      151  ; DSM
        DW      127  ; DRM
        DB      0C0H  ; AL0
        DB      00H  ; AL1
        DW      32  ; CKS
        DW      2  ; OFF

; Fujitsu-compatible 2HD DPB: 77 cyl, 2 sides, 26 x 256 B/side.
DPB2HD  DW      104  ; SPT
        DB      5  ; BSH, 4 KiB blocks
        DB      31  ; BLM
        DB      3  ; EXM
        DW      242  ; DSM
        DW      127  ; DRM
        DB      080H  ; AL0
        DB      00H  ; AL1
        DW      32  ; CKS
        DW      2  ; OFF

CURDRV  DB      0
CURTRK  DW      0
CURSEC  DW      0
CURDMA  DW      0080H
WBOOTINFO  DB      0
UC1_NEXT  DB      0

