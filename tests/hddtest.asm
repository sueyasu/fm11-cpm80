; HDDTEST.COM -- disposable M2243B fixture only, standard 8080.
; Sequential read of all 128 records at DSM=4102, random overwrite
; of last record, then random readback. Host verifies persistence.
        ORG 0100H
START   LXI SP,STACKTOP
        LXI H,FCB+12
        MVI B,24
        XRA A
INITFCB MOV M,A
        INX H
        DCR B
        JNZ INITFCB
        LXI D,MSGSTART
        CALL PRINT
        MVI C,25
        CALL 5
        CPI 8
        JNZ FAILDRV
        MVI C,31
        CALL 5
        LXI D,5
        DAD D
        MOV A,M
        STA DSMLO
        INX H
        MOV A,M
        STA DSMHI
        CPI 10H
        JNZ FAILGEO
        LDA DSMLO
        CPI 06H
        JNZ FAILGEO
        LXI D,MSGGEO
        CALL PRINT
        LXI D,FCB
        MVI C,15
        CALL 5
        CPI 0FFH
        JZ FAILOPEN
        LXI D,MSGOPEN
        CALL PRINT
        MVI C,26
        LXI D,BUF
        CALL 5
        XRA A
        STA RECNO
READLOOP LXI D,FCB
        MVI C,20
        CALL 5
        ORA A
        JNZ FAILREAD
        LDA RECNO
        MOV B,A
        LXI H,BUF
        MVI C,128
CHECK   MOV A,B
        CMP M
        JNZ FAILDATA
        INR B
        INX H
        DCR C
        JNZ CHECK
        LXI H,RECNO
        INR M
        MOV A,M
        CPI 128
        JNZ READLOOP
        LXI D,MSGREAD
        CALL PRINT
        ; Set random record 127, overwrite with distinct pattern.
        MVI A,127
        STA FCB+33
        XRA A
        STA FCB+34
        STA FCB+35
        LXI H,BUF
        MVI B,128
        MVI A,0A5H
FILL    MOV M,A
        INX H
        DCR B
        JNZ FILL
        LXI D,FCB
        MVI C,34
        CALL 5
        ORA A
        JNZ FAILWRITE
        LXI D,FCB
        MVI C,16
        CALL 5
        CPI 0FFH
        JZ FAILCLOSE
        ; Re-open from clean FCB; random read verifies written record.
        LXI H,FCB+12
        MVI B,24
        XRA A
CLEAR   MOV M,A
        INX H
        DCR B
        JNZ CLEAR
        LXI D,FCB
        MVI C,15
        CALL 5
        CPI 0FFH
        JZ FAILREOPEN
        MVI A,127
        STA FCB+33
        LXI D,FCB
        MVI C,33
        CALL 5
        ORA A
        JNZ FAILRANDOM
        LXI H,BUF
        MVI B,128
VERIFY  MOV A,M
        CPI 0A5H
        JNZ FAILVERIFY
        INX H
        DCR B
        JNZ VERIFY
        LXI D,MSGOK
        CALL PRINT
        JMP 0
FAILDRV LXI D,MSGDRV
        JMP FAILSTATUS
FAILGEO LXI D,MSGGEOBAD
        CALL PRINT
        LDA DSMHI
        CALL HEXBYTE
        LDA DSMLO
        CALL HEXBYTE
        JMP FAILEND
FAILOPEN LXI D,MSGOPENBAD
        JMP FAILSTATUS
FAILREAD STA ACTUAL
        LXI D,MSGREADBAD
        CALL PRINT
        JMP FAILREC
FAILDATA MOV A,M
        STA ACTUAL
        MOV A,B
        STA EXPECTED
        MOV A,C
        STA REMAIN
        LXI D,MSGDATA
        CALL PRINT
        LDA RECNO
        CALL HEXBYTE
        LXI D,MSGOFF
        CALL PRINT
        MVI A,128
        LXI H,REMAIN
        SUB M
        CALL HEXBYTE
        LXI D,MSGEXP
        CALL PRINT
        LDA EXPECTED
        CALL HEXBYTE
        JMP FAILACT
FAILREC LDA RECNO
        CALL HEXBYTE
FAILACT LXI D,MSGACT
        CALL PRINT
        LDA ACTUAL
        CALL HEXBYTE
        JMP FAILEND
FAILWRITE LXI D,MSGWRITE
        JMP FAILSTATUS
FAILCLOSE LXI D,MSGCLOSE
        JMP FAILSTATUS
FAILREOPEN LXI D,MSGREOPEN
        JMP FAILSTATUS
FAILRANDOM LXI D,MSGRANDOM
        JMP FAILSTATUS
FAILVERIFY LXI D,MSGVERIFY
FAILSTATUS STA ACTUAL
        CALL PRINT
        LDA ACTUAL
        CALL HEXBYTE
FAILEND LXI D,MSGNL
        CALL PRINT
        JMP 0
HEXBYTE PUSH PSW
        RRC
        RRC
        RRC
        RRC
        CALL HEXDIG
        POP PSW
HEXDIG ANI 0FH
        ADI 30H
        CPI 3AH
        JC HEXOUT
        ADI 7
HEXOUT MOV E,A
        MVI C,2
        JMP 5
PRINT   MVI C,9
        JMP 5
MSGSTART DB 'M2243B last-block test',13,10,'$'
MSGREAD DB 'PASS: all 128 records read',13,10,'$'
MSGOK   DB 'PASS: random write/readback; verify image on host',13,10,'$'
MSGGEO DB 'PASS: DSM=1006h',13,10,'
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DB 0,0,0,0,0,0,0,0,0,0,0,0
        DB 0,0,0,0,0,0,0,0,0,0,0,0
BUF     DS 128
        DS 128
STACKTOP EQU $

MSGOPEN DB 'PASS: TAIL.DAT opened',13,10,'
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $

MSGDRV DB 'FAIL: current drive=
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $

MSGGEOBAD DB 'FAIL: DSM=
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $

MSGOPENBAD DB 'FAIL: open status=
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $

MSGREADBAD DB 'FAIL: sequential read record=
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $

MSGDATA DB 'FAIL: data record=
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $

MSGOFF DB ' offset=
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $

MSGEXP DB ' expected=
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $

MSGACT DB ' actual/status=
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $

MSGWRITE DB 'FAIL: random write status=
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $

MSGCLOSE DB 'FAIL: close status=
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $

MSGREOPEN DB 'FAIL: reopen status=
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $

MSGRANDOM DB 'FAIL: random read status=
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $

MSGVERIFY DB 'FAIL: random readback byte=
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $

MSGNL DB 13,10,'
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $

DSMLO DB 0
DSMHI DB 0
ACTUAL DB 0
EXPECTED DB 0
REMAIN DB 0
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $
