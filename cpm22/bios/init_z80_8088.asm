; With an 8088 main CPU the fixed windows are in physical bank 1.
; Set the central window to bank 1 before entering CCP or using the TPA.
; BOOT and its stack reside in the fixed upper window, so this is safe.
CPU_INIT  MVI     A,1
        STA     FM11_BANK
        RET

