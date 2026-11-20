; Z80 fixed RAM windows are in physical bank 0 with a 6809 main CPU.
CPU_INIT  XRA     A
        STA     FM11_BANK
        RET

