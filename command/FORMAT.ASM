; FM-11 FORMAT.COM, common Intel 8080 code for all CPU backends.
; Generated IPL templates follow the initialized variables.
        ORG 0100H
START   LXI SP,STACKTOP
        LXI D,MSGTITLE
        CALL PRINT
        LDA 0080H
        MOV B,A
        LXI H,0081H
        CALL SKIPSP
        JZ USAGE
        MOV A,M
        CPI 'H'
        JNZ DRIVELETTER
        MOV A,B
        CPI 3
        JC DRIVELETTER
        INX H
        MOV A,M
        DCX H
        CPI 'D'
        JNZ DRIVELETTER
        INX H
        INX H
        MOV A,M
        CPI 'D'
        JNZ USAGE
        INX H
        DCR B
        DCR B
        DCR B
        MVI A,8
        JMP GOTDRIVE
DRIVELETTER MOV A,B
        CPI 2
        JC USAGE
        MOV A,M
        SUI 'A'
        CPI 9
        JNC USAGE
        MOV C,A
        INX H
        MOV A,M
        CPI ':'
        JNZ USAGE
        INX H
        DCR B
        DCR B
        MOV A,C
GOTDRIVE STA TARGET
        XRA A
        STA MODE
        CALL SKIPSP
        JZ PARSED
        MOV A,B
        CPI 2
        JC USAGE
        MOV A,M
        CPI '/'
        JNZ USAGE
        INX H
        MOV A,M
        CPI 'S'
        JZ OPTSYS
        CPI 'L'
        JNZ USAGE
        MVI A,2
        JMP OPTSET
OPTSYS  MVI A,1
OPTSET  STA MODE
        INX H
        DCR B
        DCR B
        CALL SKIPSP
        JNZ USAGE
PARSED  LDA TARGET
        LXI H,0FBF4H
        CMP M
        JZ UNSAFE
        MVI C,25
        CALL 5
        STA CURRENT
        LXI H,TARGET
        CMP M
        JZ UNSAFE
        LDA TARGET
        CPI 8
        JNZ FINDAPI
        LDA MODE
        CPI 2
        JZ USAGE
FINDAPI LHLD 0001H
        LXI D,36H
        DAD D
        MOV A,M
        CPI 0C3H
        JNZ NOAPI
        SHLD APIENTRY+1
        MVI A,0BH
        CALL APIENTRY
        ORA A
        JNZ NOAPI
        LDA 0FBF9H
        CPI 3
        JNC NOAPI
        STA CPUTYPE
        LDA TARGET
        STA IODRV
        LXI H,0
        SHLD TRK
        CALL GEOMETRY
        CALL CHECKGEOM
        LDA HEADS
        STA TGTHEAD
        LHLD TOTAL
        SHLD TGTTOTAL
        LXI D,MSGWARN
        CALL PRINT
        LDA TARGET
        ADI 'A'
        MOV E,A
        MVI C,2
        CALL 5
        LXI D,MSGASK
        CALL PRINT
        MVI C,1
        CALL 5
        CPI 'Y'
        JZ CONFIRMED
        CPI 'y'
        JNZ CANCEL
CONFIRMED LXI D,MSGNL
        CALL PRINT
        LDA MODE
        CPI 1
        JNZ DESTROY
        LXI D,MSGSOURCE
        CALL PRINT
        CALL LOADSOURCE
DESTROY LDA TARGET
        STA IODRV
        LXI H,0
        SHLD TRK
        CALL GEOMETRY
        CALL CHECKGEOM
        LDA HEADS
        LXI H,TGTHEAD
        CMP M
        JNZ FAIL
        LHLD TOTAL
        XCHG
        LHLD TGTTOTAL
        MOV A,H
        CMP D
        JNZ FAIL
        MOV A,L
        CMP E
        JNZ FAIL
        LDA TARGET
        CPI 8
        JZ HDDCLEAR
        LXI D,MSGFORMAT
        CALL PRINT
FLOOP   CALL GEOMETRY
        CALL CHECKGEOM
        CALL FORMATONE
        LHLD TRK
        INX H
        SHLD TRK
        XCHG
        LHLD TGTTOTAL
        MOV A,H
        CMP D
        JNZ FLOOP
        MOV A,L
        CMP E
        JNZ FLOOP
        JMP AFTERCLEAR
; HDD: clear reserved cylinder and exactly 16 KiB directory.
; Other data sectors are left alone; this is not a secure erase.
HDDCLEAR LXI D,MSGHDD
        CALL PRINT
        LDA TGTHEAD
        ADI 2
        MOV L,A
        MVI H,0
        SHLD LIMIT
        LXI H,0
        SHLD TRK
        MVI A,1
        STA SECNO
HLOOP   LXI H,BUFFER
        LXI B,256
        MVI D,0E5H
        CALL FILL
        CALL WRITEVERIFY
        CALL ADVANCE
        LHLD TRK
        XCHG
        LHLD LIMIT
        MOV A,H
        CMP D
        JNZ HLOOP
        MOV A,L
        CMP E
        JNZ HLOOP
AFTERCLEAR LDA MODE
        CPI 1
        JNZ FINISH
        LXI D,MSGINSTALL
        CALL PRINT
        CALL INSTALL
FINISH  LXI D,MSGDONE
        CALL PRINT
        JMP 0
FAIL    LXI D,MSGFAIL
        CALL PRINT
        ; WBOOT resets BDOS login/allocation state even after partial writes.
        JMP 0
USAGE   LXI D,MSGUSAGE
        CALL PRINT
        JMP 0
UNSAFE  LXI D,MSGUNSAFE
        CALL PRINT
        JMP 0
NOAPI   LXI D,MSGAPI
        CALL PRINT
        JMP 0
CANCEL  LXI D,MSGCANCEL
        CALL PRINT
        JMP 0
SKIPSP  MOV A,B
        ORA A
        RZ
        MOV A,M
        CPI 20H
        JNZ NOTSP
        INX H
        DCR B
        JMP SKIPSP
NOTSP   MVI A,1
        ORA A
        RET
PRINT   MVI C,9
        JMP 5
APIENTRY CALL 0
        RET

; Source is the actual boot disk, not an arbitrary logged-in data disk.
; Buffer exact native server (6144 bytes) and system (6656 bytes).
LOADSOURCE LDA 0FBF4H
        STA IODRV
        LXI H,0
        SHLD TRK
        CALL GEOMETRY
        CALL CHECKGEOM
        CALL NATIVEPOS
        LXI H,IMAGE
        SHLD IMGPTR
        LXI H,6144
        SHLD REMAIN
        CALL READIMAGE
        CALL SYSTEMPOS
        LXI H,6656
        SHLD REMAIN
        CALL READIMAGE
        ; Refuse an obviously invalid native or CCP/CBIOS image.
        LDA CPUTYPE
        ORA A
        JNZ CHECKX86
        LDA IMAGE
        CPI 1AH
        JNZ FAIL
        LDA IMAGE+1
        CPI 50H
        JNZ FAIL
        JMP CHECKCORE
CHECKX86 LDA IMAGE
        CPI 0FAH
        JNZ FAIL
CHECKCORE LDA IMAGE+6144
        CPI 0C3H
        JNZ FAIL
        LDA IMAGE+6144+5632
        CPI 0C3H
        JNZ FAIL
        RET
; IPL starts at side-track 0, sector 1, native follows 512 bytes.
NATIVEPOS LXI H,0
        SHLD TRK
        CALL GEOMETRY
        LDA NVAL
        ORA A
        MVI A,3
        JNZ NATSEC
        MVI A,5
NATSEC  STA SECNO
        RET
; FDD system starts at cylinder 1 / side-track 2. HDD starts LBA26.
SYSTEMPOS LDA IODRV
        CPI 8
        JZ SYSHDD
        LXI H,2
        SHLD TRK
        MVI A,1
        STA SECNO
        JMP GEOMETRY
SYSHDD  LXI H,0
        SHLD TRK
        MVI A,27
        STA SECNO
        JMP GEOMETRY
READIMAGE MVI A,8
        CALL PHYS
        ORA A
        JNZ FAIL
        LXI H,BUFFER
        XCHG
        LHLD IMGPTR
        CALL GETCOUNT
RILP    LDAX D
        MOV M,A
        INX D
        INX H
        DCX B
        MOV A,B
        ORA C
        JNZ RILP
        SHLD IMGPTR
        CALL DECSIZE
        RZ
        CALL ADVANCE
        JMP READIMAGE
INSTALL CALL SELECTIPL
        SHLD IMGPTR
        LXI H,0
        SHLD TRK
        CALL GEOMETRY
        MVI A,1
        STA SECNO
        LXI H,512
        SHLD REMAIN
        CALL WRITEIMAGE
        CALL NATIVEPOS
        LXI H,IMAGE
        SHLD IMGPTR
        LXI H,6144
        SHLD REMAIN
        CALL WRITEIMAGE
        CALL SYSTEMPOS
        LXI H,6656
        SHLD REMAIN
        CALL WRITEIMAGE
        RET
SELECTIPL LDA CPUTYPE
        ORA A
        JNZ IPLX86
        LXI H,IPL092D
        JMP IPLMEDIA
IPLX86  LXI H,IPL862D
IPLMEDIA LDA TARGET
        CPI 4
        RC
        LXI D,512
        DAD D
        CPI 8
        RC
        DAD D
        RET
WRITEIMAGE LHLD IMGPTR
        LXI D,BUFFER
        CALL GETCOUNT
WILP    MOV A,M
        STAX D
        INX D
        INX H
        DCX B
        MOV A,B
        ORA C
        JNZ WILP
        SHLD IMGPTR
        CALL WRITEVERIFY
        CALL DECSIZE
        RZ
        CALL ADVANCE
        JMP WRITEIMAGE
GETCOUNT PUSH H
        LHLD SIZE
        MOV B,H
        MOV C,L
        POP H
        RET
DECSIZE LHLD SIZE
        XCHG
        LHLD REMAIN
        MOV A,L
        SUB E
        MOV L,A
        MOV A,H
        SBB D
        MOV H,A
        JC FAIL
        SHLD REMAIN
        ORA L
        RET
ADVANCE LDA SECNO
        LXI H,SPT
        CMP M
        JZ NEXTTRACK
        INR A
        STA SECNO
        RET
NEXTTRACK MVI A,1
        STA SECNO
        LHLD TRK
        INX H
        SHLD TRK
        ; Only the 2HD boundary between tracks 0 and 1 changes size.
        LDA IODRV
        CPI 4
        RC
        CPI 8
        RNC
        MOV A,H
        ORA A
        RNZ
        MOV A,L
        CPI 1
        RNZ
        JMP GEOMETRY
; Save intended bytes, write, read into an independent cleared buffer,
; compare all physical bytes. All writes are checked before continuing.
WRITEVERIFY LXI H,BUFFER
        LXI D,SAVED
        CALL GETCOUNT
WVCPY   MOV A,M
        STAX D
        INX H
        INX D
        DCX B
        MOV A,B
        ORA C
        JNZ WVCPY
        MVI A,9
        CALL PHYS
        ORA A
        JNZ FAIL
        LXI H,BUFFER
        CALL GETCOUNT
        MVI D,0
        CALL FILL
        MVI A,8
        CALL PHYS
        ORA A
        JNZ FAIL
        LXI H,BUFFER
        LXI D,SAVED
        CALL GETCOUNT
WVCHK   LDAX D
        CMP M
        JNZ FAIL
        INX H
        INX D
        DCX B
        MOV A,B
        ORA C
        JNZ WVCHK
        RET
PHYS    PUSH PSW
        LDA IODRV
        STA 0FBF8H
        LHLD TRK
        MOV A,H
        STA 0FBFAH
        MOV A,L
        STA 0FBFBH
        XRA A
        STA 0FBFCH
        LDA SECNO
        STA 0FBFDH
        LXI H,BUFFER
        MOV A,H
        STA 0FBFEH
        MOV A,L
        STA 0FBFFH
        POP PSW
        JMP APIENTRY
GEOMETRY MVI A,7
        CALL PHYS
        ORA A
        JNZ GEOFAIL
        LDA 0FBFAH
        MOV H,A
        LDA 0FBFBH
        MOV L,A
        SHLD TOTAL
        MOV A,H
        ORA L
        JZ GEOFAIL
        LDA 0FBF9H
        STA HEADS
        LDA 0FBFCH
        STA SPT
        LDA 0FBFDH
        STA NVAL
        CPI 2
        JNC GEOFAIL
        LXI H,128
        ORA A
        JZ SETSIZE
        DAD H
SETSIZE SHLD SIZE
        RET
CHECKGEOM LDA IODRV
        CPI 8
        JZ GEOHDD
        LDA HEADS
        CPI 2
        JNZ GEOFAIL
        LDA IODRV
        CPI 4
        JNC GEOHD
        LDA SPT
        CPI 16
        JNZ GEOFAIL
        LDA NVAL
        CPI 1
        JNZ GEOFAIL
        LHLD TOTAL
        LXI D,80
        JMP GEOCMP
GEOHD   LDA SPT
        CPI 26
        JNZ GEOFAIL
        LHLD TRK
        MOV A,H
        ORA L
        JNZ GEOHDN1
        LDA NVAL
        ORA A
        JNZ GEOFAIL
        JMP GEONORMAL
GEOHDN1 LDA NVAL
        CPI 1
        JNZ GEOFAIL
GEONORMAL LHLD TOTAL
        LXI D,154
GEOCMP  MOV A,H
        CMP D
        JNZ GEOFAIL
        MOV A,L
        CMP E
        JNZ GEOFAIL
        RET
GEOHDD  LDA SPT
        CPI 32
        JNZ GEOFAIL
        LDA NVAL
        CPI 1
        JNZ GEOFAIL
        LDA HEADS
        CPI 2
        JC GEOFAIL
        RET
GEOFAIL JMP FAIL
; WD17xx stream: sync, FE/CHRN/F7, sync, FB/data/F7.
FORMATONE LXI H,BUFFER
        LXI B,6400
        LDA IODRV
        CPI 4
        JC FMTLEN
        LXI B,10900
FMTLEN  MVI D,4EH
        CALL FILL
        LXI H,BUFFER
        MVI A,1
        STA SECNO
FMTLOOP LXI B,5
        MVI D,0
        CALL FILL
        MVI M,0FEH
        INX H
        LDA TRK
        ORA A
        RAR
        MOV M,A
        INX H
        LDA TRK
        ANI 1
        MOV M,A
        INX H
        LDA SECNO
        MOV M,A
        INX H
        LDA NVAL
        MOV M,A
        INX H
        MVI M,0F7H
        INX H
        LXI B,5
        MVI D,0
        CALL FILL
        MVI M,0FBH
        INX H
        PUSH H
        LHLD SIZE
        MOV B,H
        MOV C,L
        POP H
        MVI D,0E5H
        CALL FILL
        MVI M,0F7H
        INX H
        LDA SECNO
        LXI D,SPT
        XCHG
        CMP M
        XCHG
        JZ FMTISSUE
        INR A
        STA SECNO
        JMP FMTLOOP
; Like CP/M-86, finish each track after successful WRITE TRACK.
; /S system installation still verifies its physical sector writes.
FMTISSUE MVI A,0AH
        CALL PHYS
        ORA A
        JNZ FAIL
        RET
FILL    MOV M,D
        INX H
        DCX B
        MOV A,B
        ORA C
        JNZ FILL
        RET
MATCH   MOV A,M
        CMP D
        JNZ FAIL
        INX H
        DCX B
        MOV A,B
        ORA C
        JNZ MATCH
        RET

MSGTITLE DB 'FM-11 CP/M-80 FORMAT',13,10,24H
MSGUSAGE DB 'Usage: FORMAT A:..I: or FORMAT HDD [/S|/L]',13,10
        DB '/S bootable, /L physical only (FDD)',13,10,24H
MSGUNSAFE DB 'Cannot format boot or current drive',13,10,24H
MSGAPI DB 'FM-11 physical disk BIOS API required',13,10,24H
MSGWARN DB 'ALL files on drive ',24H
MSGASK DB ': will be lost. Continue (Y/N)? ',24H
MSGCANCEL DB 13,10,'Cancelled',13,10,24H
MSGNL DB 13,10,24H
MSGSOURCE DB 'Reading system from boot disk...',13,10,24H
MSGFORMAT DB 'Formatting all floppy tracks...',13,10,24H
MSGHDD DB 'Initializing reserved cylinder and directory...',13,10,24H
MSGINSTALL DB 'Installing and verifying boot system...',13,10,24H
MSGDONE DB 'FORMAT complete',13,10,24H
MSGFAIL DB 'FORMAT failed. Target may be incomplete.',13,10,24H
TARGET DB 0
IODRV DB 0
CURRENT DB 0
MODE DB 0
CPUTYPE DB 0
TRK DW 0
TOTAL DW 0
TGTTOTAL DW 0
LIMIT DW 0
SIZE DW 0
IMGPTR DW 0
REMAIN DW 0
HEADS DB 0
TGTHEAD DB 0
SPT DB 0
NVAL DB 0
SECNO DB 0
; Six padded 512-byte IPL assets emitted by tools/mk_format_ipls.py.
