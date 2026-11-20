; HDDTEST.COM -- disposable M2243B fixture only, standard 8080.
; Sequential read of all 128 records at DSM=4102, random overwrite
; of last record, then random readback. Host verifies persistence.
        ORG 0100H
START   LXI SP,STACKTOP
        LXI D,MSGSTART
        CALL PRINT
        MVI C,25
        CALL 5
        CPI 8
        JNZ FAIL
        MVI C,31
        CALL 5
        LXI D,5
        DAD D
        MOV A,M
        CPI 06H
        JNZ FAIL
        INX H
        MOV A,M
        CPI 10H
        JNZ FAIL
        LXI D,FCB
        MVI C,15
        CALL 5
        CPI 0FFH
        JZ FAIL
        MVI C,26
        LXI D,BUF
        CALL 5
        XRA A
        STA RECNO
READLOOP LXI D,FCB
        MVI C,20
        CALL 5
        ORA A
        JNZ FAIL
        LDA RECNO
        MOV B,A
        LXI H,BUF
        MVI C,128
CHECK   MOV A,B
        CMP M
        JNZ FAIL
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
        JNZ FAIL
        LXI D,FCB
        MVI C,16
        CALL 5
        CPI 0FFH
        JZ FAIL
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
        JZ FAIL
        MVI A,127
        STA FCB+33
        LXI D,FCB
        MVI C,33
        CALL 5
        ORA A
        JNZ FAIL
        LXI H,BUF
        MVI B,128
VERIFY  MOV A,M
        CPI 0A5H
        JNZ FAIL
        INX H
        DCR B
        JNZ VERIFY
        LXI D,MSGOK
        CALL PRINT
        JMP 0
FAIL    LXI D,MSGFAIL
        CALL PRINT
        JMP 0
PRINT   MVI C,9
        JMP 5
MSGSTART DB 'M2243B last-block test',13,10,'$'
MSGREAD DB 'PASS: all 128 records read',13,10,'$'
MSGOK   DB 'PASS: random write/readback; verify image on host',13,10,'$'
MSGFAIL DB 'FAIL: geometry, BDOS status or data mismatch',13,10,'$'
RECNO   DB 0
FCB     DB 9,'TAIL    DAT'
        DS 24
BUF     DS 128
        DS 128
STACKTOP EQU $
