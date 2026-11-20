; V20 native backend. IPL enters CS:0000 with AL=boot drive.
; All ordinary I/O is shared with the 8088+Z80 backend.
V20_BOOT_VECTOR equ 0x40
V20_IO_VECTOR equ 0x41

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
    ; Polling drivers do not need hardware IRQs. Mask the 8259 so
    ; guest EI cannot dispatch into leftover boot-ROM interrupt vectors.
    mov al,0xff
    out 0x01,al
    ; Install IVT entries in physical bank zero, not CP/M page zero.
    xor ax,ax
    mov ds,ax
    mov word [V20_BOOT_VECTOR*4],0xf200
    mov word [V20_BOOT_VECTOR*4+2],CPM_SEG
    mov word [V20_IO_VECTOR*4],v20_io_gateway
    mov [V20_IO_VECTOR*4+2],cs
    ; CS:IP comes from BRKEM vector; DS supplies 8080 data and stack.
    mov ax,CPM_SEG
    mov ds,ax
    mov bp,0xf960
    db 0x0f,0xff,V20_BOOT_VECTOR  ; BRKEM 40h
    ; CP/M never normally executes RETEM. Stop if it does.
    cli
    jmp .stop

; CALLN pushes native FLAGS, CS, IP on SS:SP, not the 8080 stack.
; Preserve all guest registers including BP (8080 SP) and DS.
; IRET restores guest flags and emulation mode; results use the mailbox.
v20_io_gateway:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    push cs
    pop ds
    mov ax,CPM_SEG
    mov es,ax
    call server_dispatch
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    iret
