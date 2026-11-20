; FM-11 8088+Z80 IPL, adapted from fm11-cpm86 8f094f9 (MIT).
; ROM enters 07C0:0000. Load native server at physical 04000h.
cpu 8086
bits 16
org 0
%include "i8086/memory.inc"

SER_STATUS equ 0xFD07
DMA_ADDR   equ 0x12
DMA_COUNT  equ 0x13
DMA_TC     equ 0x18
DMA_MASK   equ 0x1A
DMA_MODE   equ 0x1B
DMA_FF     equ 0x1C
DMA_BANK   equ 0x21
FDC_CMD    equ 0xFD30
FDC_TRACK  equ 0xFD31
FDC_SIDE   equ 0xFD34

start:
    jmp short relocate
    times 13 db 0

relocate:
    cli
    xor ax,ax
    mov ss,ax
    mov sp,0x9000             ; private IPL stack
    push cs
    pop ds
    mov dx,SER_STATUS
    ; The original FM-11 boot ROM can leave USART0 initialized with
    ; DTR asserted and a named-pipe terminal connected. Resetting its
    ; 8251 then drives DTR low and CNamedPipe::DoClose() disconnects it.
    ; Reuse an already-enabled transmitter without touching command port.
    in al,dx
    test al,1                  ; TxRDY
    jnz .serial_ready
    ; On a cold, disabled USART use the proven 8251 reset sequence.
    ; No active transmitter is available in that case.
    xor al,al
    out dx,al
    out dx,al
    out dx,al
    mov al,0x40
    out dx,al
    mov al,0x4E
    out dx,al
    mov al,0x37               ; DTR and TxEN asserted
    out dx,al
.serial_ready:
    mov ax,0x0100
    mov es,ax
    xor si,si
    xor di,di
    mov cx,256
    cld
    rep movsw
    jmp 0x0100:boot

boot:
    xor ax,ax
    mov ds,ax
    mov bx,NATIVE_PHYS       ; DMA destination in physical bank zero
    xor bp,bp                 ; cylinder
    xor di,di                 ; C0/H0 128-byte sectors
    mov si,5                ; skip ROM-loaded IPL
.loop:
    call read256
    jc halt
    add bx,128
    or di,di
    jz .advanced
    add bx,128
.advanced:
    cmp bx,NATIVE_PHYS+NATIVE_SLOT
    je loaded
    inc si
    cmp si,27
    jb .loop
    mov si,1
    inc di
    cmp di,2
    jb .loop
    xor di,di
    inc bp
    jmp .loop

loaded:
    mov al,4                 ; fixed CP/M boot drive
    jmp NATIVE_SEG:0x0000

halt:
    cli
.again:
    hlt
    jmp .again

; BX=DMA destination (bank 0); BP=cylinder; DI=head; SI=sector.
; Preserves BX/BP/DI/SI, clobbers AX/CX/DX.
; Return CF=0 only when FDC succeeded and DMA terminal count asserted.
read256:
    mov dx,DMA_MASK
    mov al,5                 ; mask channel 1
    out dx,al
    call position_head
    jnc .positioned
    ret                       ; DMA remains masked on positioning error
.positioned:
    mov dx,DMA_FF
    xor al,al
    out dx,al
    mov dx,DMA_ADDR
    mov ax,bx
    out dx,al
    mov al,ah
    out dx,al
    mov dx,DMA_COUNT
    mov al,0x7F
    or di,di
    jz .count_ready
    mov al,0xFF
.count_ready:
    out dx,al
    xor al,al
    out dx,al
    mov dx,DMA_BANK
    xor al,al
    out dx,al
    mov dx,DMA_MODE
    mov al,0x45              ; channel 1, I/O to RAM
    out dx,al
    mov dx,DMA_TC
    in al,dx
    mov dx,FDC_TRACK+1        ; sector register
    mov ax,si
    out dx,al                 ; sector
    mov dx,FDC_SIDE
    mov ax,di
    out dx,al                 ; head
    mov dx,DMA_MASK
    mov al,1
    out dx,al                 ; unmask DMA CH1
    mov dx,FDC_CMD
    mov al,0x80
    out dx,al                 ; FDC READ
    mov cx,0xFFFF
.poll:
    in al,dx
    test al,0x10
    jnz .bad
    test al,3                 ; BUSY or DRQ
    jz .complete
    loop .poll
    jmp .bad
.complete:
    or al,al
    jnz .bad
    mov dx,DMA_TC
    in al,dx
    test al,2                ; DMA channel 1 terminal count
    jz .bad
    clc
    jmp .finish
.bad:
    stc
.finish:
    pushf
    mov dx,DMA_MASK
    mov al,5                 ; mask channel 1 on exit
    out dx,al
    popf
    ret

; The boot ROM loads four 128-byte FM sectors as a 512-byte first-stage image.
position_head:
    ; Drive 0 is the boot unit. The relocated IPL owns its position byte.
    mov dx,FDC_SIDE+1
    mov al,0
    out dx,al
    mov dx,FDC_CMD
    call wait_type1_idle
    jc .done
    cmp byte [cs:physical_cyl],0xff
    jne .known
    mov al,0x0b               ; RESTORE without verify
    call type1
    jc .done
    mov byte [cs:physical_cyl],0
.known:
    mov ax,bp
    cmp al,[cs:physical_cyl]
    je .ok
    mov dx,FDC_TRACK+2        ; DATA = destination cylinder
    out dx,al
    mov dx,FDC_CMD
    mov al,0x1b               ; SEEK without verify
    call type1
    jc .done
    mov ax,bp
    mov [cs:physical_cyl],al
.ok:
    clc
.done:
    ret

type1:
    out dx,al
    mov cx,16
.delay:
    loop .delay
    call wait_type1_idle
    jc .done
    test al,0x90              ; not ready / seek error
    jz .done
    stc
.done:
    ret

wait_type1_idle:
    mov cx,0xffff
.poll:
    in al,dx
    test al,1                 ; Type I bit 1 is INDEX, not DRQ
    jz .done
    loop .poll
    stc
.done:
    ret

physical_cyl db 0xff

times 0x200-($-$$) db 0
