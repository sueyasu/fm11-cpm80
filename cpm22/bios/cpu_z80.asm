; FM-11 Z80 card backend (6809+Z80 and future 8088+Z80).
; Appended to the common BIOS; no ORG or independent image.
;
; CPU_INIT: cold boot only, after SP is established. Preserve BC/DE/HL/SP.
; CPU_IOCALL: execute the posted mailbox request synchronously.
; Preserve BC/DE/HL/SP; A and flags are scratch. Interrupt policy is
; target-specific. Keep the mailbox result in shared memory.

CPU_INIT  XRA     A
        STA     FM11_BANK       ; CP/M always uses Z80 bank zero
        RET

CPU_IOCALL  DI
        XRA     A
        STA     FM11_CPUCTL     ; stop Z80, resume native main CPU
        NOP                    ; Z80 resumes here
        EI
        RET
