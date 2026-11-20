; Native entry and execution loop for the FM-11 8088 + Z80 card.
; IPL enters CS:0000 with AL=physical boot drive (0, 4 or 8).
; This include is emitted first, so start remains at offset zero.
; Only this backend installs the Z80 reset jump and switches CPU ownership.
start:
    cli
    mov dx,cs
    mov ss,dx
    mov sp,NATIVE_STACK_TOP
    mov ds,dx
    mov dx,CPM_SEG
    mov es,dx
    cld
    call server_cold_init
    jnc .loaded
.stop:
    hlt
    jmp .stop
.loaded:
    ; Z80 starts at logical 0000h in the fixed low window (bank 1).
    mov byte [es:0],0xc3
    mov word [es:1],0xf200
    mov word [es:3],0

; The OUT suspends the 8088 until the Z80 posts a request and yields.
; Keep the suspended native stack independent of CP/M's Z80 stack.
cpu_service_loop:
    mov dx,0xfd05
    mov al,1
    out dx,al
    nop
    call server_dispatch
    jmp cpu_service_loop
