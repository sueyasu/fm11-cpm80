; FM-11 Z80 card backend (6809+Z80 and 8088+Z80).
; Appended to the common BIOS; no ORG or independent image.
;
; CPU_INIT is supplied by the target-specific bank initialization file.
; CPU_IOCALL: execute the posted mailbox request synchronously.
; Preserve BC/DE/HL/SP; A and flags are scratch. Interrupt policy is
; target-specific. Keep the mailbox result in shared memory.

CPU_IOCALL  DI
        XRA     A
        STA     FM11_CPUCTL     ; stop Z80, resume native main CPU
        NOP                    ; Z80 resumes here
        EI
        RET
