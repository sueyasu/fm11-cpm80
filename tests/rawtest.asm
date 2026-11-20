; RAWTEST X: is read-only. RAWTEST X: W destroys scratch media data.
        ORG 0100H
START   LXI SP,STKTOP
        LDA 005CH
        ORA A
        JZ USAGE
        DCR A
        CPI 9
        JNC USAGE
        STA TARGET
        XRA A
        STA WRMODE
        LDA 006DH
        ORA A
        JZ INIT
        CPI 20H
        JZ INIT
        CPI 'W'
        JNZ USAGE
        LDA 006EH
        CPI 20H
        JNZ USAGE
        LDA TARGET
        LXI H,0FBF4H
        CMP M
        JZ UNSAFE
        MVI C,25
        CALL 5
        LXI H,TARGET
        CMP M
        JZ UNSAFE
        MVI A,1
        STA WRMODE
INIT    LXI D,MSGSTART
        CALL PRINT
        LHLD 0001H
        LXI D,36H
        DAD D
        MOV A,M
        CPI 0C3H
        JNZ FAIL
        SHLD APIENTRY+1
        MVI A,0BH
        CALL APIENTRY
        ORA A
        JNZ FAIL
        LDA 0FBF9H
        CPI 3
        JNC FAIL
        STA CPUTYPE
        LXI D,MSGCPU
        CALL PRINT
        LDA CPUTYPE
        ADI 30H
        MOV E,A
        MVI C,2
        CALL 5
        LXI D,MSGNL
        CALL PRINT
        MVI A,0CH
        CALL APIENTRY
        ORA A
        JZ FAIL
        MVI A,9
        STA 0FBF8H
        MVI A,7
        CALL APIENTRY
        ORA A
        JZ FAIL
        LXI D,MSGREJECT
        CALL PRINT
        LXI H,0
        SHLD TRK
        MVI A,1
        STA SECNO
        CALL GEOMETRY
        CALL CHECKGEOM
        LXI D,MSGFIRST
        CALL PRINT
        CALL READCHECK
        LDA WRMODE
        ORA A
        JZ LASTTRK
        LDA TARGET
        CPI 8
        JZ LASTTRK
        LXI D,MSGFMT0
        CALL PRINT
        CALL FORMATONE
LASTTRK LHLD TOTAL
        DCX H
        SHLD TRK
        CALL GEOMETRY
        CALL CHECKGEOM
        LDA NVAL
        CPI 1
        JNZ FAIL
        LXI D,MSGLAST
        CALL PRINT
        LDA SPT
        STA SECNO
        CALL READCHECK
        LDA WRMODE
        ORA A
        JZ COMPLETE
        LDA TARGET
        CPI 8
        JZ WRLAST
        LXI D,MSGFMTEND
        CALL PRINT
        CALL FORMATONE
WRLAST  LXI D,MSGWRITE
        CALL PRINT
        LDA SPT
        STA SECNO
        LXI H,BUFFER
        LXI B,256
        MVI D,0A5H
        CALL FILL
        MVI A,9
        CALL PHYS
        ORA A
        JNZ FAIL
        LXI H,BUFFER
        LXI B,256
        MVI D,5AH
        CALL FILL
        MVI A,8
        CALL PHYS
        ORA A
        JNZ FAIL
        LXI H,BUFFER
        LXI B,256
        MVI D,0A5H
        CALL MATCH
COMPLETE LXI D,MSGOK
        CALL PRINT
        JMP 0
USAGE   LXI D,MSGUSAGE
        CALL PRINT
        JMP 0
UNSAFE  LXI D,MSGUNSAFE
        CALL PRINT
        JMP 0
FAIL    LXI D,MSGFAIL
        CALL PRINT
        JMP 0
PRINT   MVI C,9
        JMP 5
APIENTRY CALL 0
        RET
PHYS    PUSH PSW
        LDA TARGET
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
        JNZ FAIL
        LDA 0FBFAH
        MOV H,A
        LDA 0FBFBH
        MOV L,A
        SHLD TOTAL
        MOV A,H
        ORA L
        JZ FAIL
        LDA 0FBF9H
        STA HEADS
        LDA 0FBFCH
        STA SPT
        LDA 0FBFDH
        STA NVAL
        CPI 2
        JNC FAIL
        LXI H,128
        ORA A
        JZ SETSIZE
        DAD H
SETSIZE SHLD SIZE
        RET
CHECKGEOM LDA TARGET
        CPI 8
        JZ GEOHDD
        LDA HEADS
        CPI 2
        JNZ FAIL
        LDA TARGET
        CPI 4
        JNC GEOHD
        LDA SPT
        CPI 16
        JNZ FAIL
        LDA NVAL
        CPI 1
        JNZ FAIL
        LHLD TOTAL
        LXI D,80
        JMP GEOCMP
GEOHD   LDA SPT
        CPI 26
        JNZ FAIL
        LHLD TRK
        MOV A,H
        ORA L
        JNZ GEOHDN1
        LDA NVAL
        ORA A
        JNZ FAIL
        JMP GEONORMAL
GEOHDN1 LDA NVAL
        CPI 1
        JNZ FAIL
GEONORMAL LHLD TOTAL
        LXI D,154
GEOCMP  MOV A,H
        CMP D
        JNZ FAIL
        MOV A,L
        CMP E
        JNZ FAIL
        RET
GEOHDD  LDA SPT
        CPI 32
        JNZ FAIL
        LDA NVAL
        CPI 1
        JNZ FAIL
        LDA HEADS
        CPI 2
        JC FAIL
        RET
; Two reads with different initial buffer contents must match.
READCHECK LXI H,BUFFER
        LXI B,256
        MVI D,55H
        CALL FILL
        MVI A,8
        CALL PHYS
        ORA A
        JNZ FAIL
        LHLD SIZE
        MOV B,H
        MOV C,L
        LXI H,BUFFER
        LXI D,SAVED
COPYLOOP MOV A,M
        STAX D
        INX H
        INX D
        DCX B
        MOV A,B
        ORA C
        JNZ COPYLOOP
        LXI H,BUFFER
        LXI B,256
        MVI D,0AAH
        CALL FILL
        MVI A,8
        CALL PHYS
        ORA A
        JNZ FAIL
        LXI D,SAVED
        LHLD SIZE
        MOV B,H
        MOV C,L
        LXI H,BUFFER
CMPLOOP LDAX D
        CMP M
        JNZ FAIL
        INX H
        INX D
        DCX B
        MOV A,B
        ORA C
        JNZ CMPLOOP
        LDA NVAL
        ORA A
        RNZ
        LXI H,BUFFER+128
        LXI B,128
        MVI D,0AAH
        JMP MATCH
; WD17xx stream: sync, FE/CHRN/F7, sync, FB/data/F7.
FORMATONE LXI H,BUFFER
        LXI B,6400
        LDA TARGET
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
FMTISSUE MVI A,0AH
        CALL PHYS
        ORA A
        JNZ FAIL
        MVI A,1
        STA SECNO
FMTVERIFY LXI H,BUFFER
        LXI B,256
        MVI D,0
        CALL FILL
        MVI A,8
        CALL PHYS
        ORA A
        JNZ FAIL
        LHLD SIZE
        MOV B,H
        MOV C,L
        LXI H,BUFFER
        MVI D,0E5H
        CALL MATCH
        LDA SECNO
        LXI H,SPT
        CMP M
        RZ
        INR A
        STA SECNO
        JMP FMTVERIFY
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
MSGSTART DB 'FM-11 physical disk API test',13,10,24H
MSGCPU DB 'CPU type: ',24H
MSGREJECT DB 'PASS: invalid operation and drive rejected',13,10,24H
MSGFIRST DB 'Reading first side-track',13,10,24H
MSGLAST DB 'Reading last side-track',13,10,24H
MSGFMT0 DB 'Formatting and verifying first side-track',13,10,24H
MSGFMTEND DB 'Formatting and verifying last side-track',13,10,24H
MSGWRITE DB 'Writing and verifying final physical sector',13,10,24H
MSGOK DB 'PASS: physical disk API test',13,10,24H
MSGFAIL DB 'FAIL: physical disk API test',13,10,24H
MSGUSAGE DB 'Usage: RAWTEST X: [W]',13,10
        DB 'W destroys data on the specified scratch disk',13,10,24H
MSGUNSAFE DB 'W refused on current or boot drive',13,10,24H
MSGNL DB 13,10,24H
TARGET DB 0
WRMODE DB 0
CPUTYPE DB 0
TRK DW 0
TOTAL DW 0
SIZE DW 0
HEADS DB 0
SPT DB 0
NVAL DB 0
SECNO DB 0
SAVED DS 256
BUFFER DS 10900
        DS 128
STKTOP EQU $
