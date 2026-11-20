; FM-11 CP/M-80 HDD IPL, adapted from fm11-cpm86 f72336a (MIT).
; ROM loads LBA 0..1 at 07C0:0000. Relocate and load the native server.
cpu 8086
bits 16
org 0
%include "i8086/memory.inc"

start:
    cli
    xor ax,ax
    mov ss,ax
    mov sp,0x9000
    push cs
    pop ds
    mov ax,0x0100
    mov es,ax
    xor si,si
    xor di,di
    mov cx,256
    cld
    rep movsw
    jmp 0x0100:relocated

relocated:
    push cs
    pop ds
    call hdd_set_binary
    jc halt
    mov bx,NATIVE_PHYS
    mov si,HDD_SERVER_LBA
.load:
    call hdd_read_sector
    jc halt
    add bx,256
    inc si
    cmp si,HDD_SYSTEM_LBA
    jb .load
    mov al,HDD_BOOT_DRIVE
    jmp NATIVE_SEG:0

halt:
    cli
.wait:
    hlt
    jmp .wait

%include "i8086/hdd_boot_io.inc"
times 512-($-$$) db 0
