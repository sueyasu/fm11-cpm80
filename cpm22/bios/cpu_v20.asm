; V20 8080 mode: flat 64 KiB at native segment CPM_SEG.
; No external Z80 bank selection or FD05 CPU handoff.
CPU_INIT  RET

; Native gateway preserves guest registers and returns with IRET.
; The shared mailbox carries the service status and data.
CPU_IOCALL DB    0EDH,0EDH,041H  ; CALLN 41h
        RET
