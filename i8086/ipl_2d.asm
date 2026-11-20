; FM-11 8088+Z80 IPL, adapted from fm11-cpm86 8f094f9 (MIT).
; ROM enters 07C0:0000. Load native server at physical 10000h.
cpu 8086
bits 16
org 0

SER_STATUS equ 0xFD07
SER_DATA   equ 0xFD06
DMA_ADDR   equ 0x10
DMA_COUNT  equ 0x11
DMA_TC     equ 0x18
DMA_MASK   equ 0x1A
DMA_MODE   equ 0x1B
DMA_FF     equ 0x1C
DMA_BANK   equ 0x20
FDC_CMD    equ 0xFD18
FDC_TRACK  equ 0xFD19
FDC_SIDE   equ 0xFD1C

start:
    jmp short relocate
    times 13 db 0

relocate:
    cli
    xor ax,ax
    mov ss,ax
    mov sp,0x9000             ; establish stack BEFORE calling putc
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
    mov al,'I'
    call putc
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
    mov al,'R'
    call putc
    xor bx,bx                ; DMA offset within physical bank 1
    xor bp,bp                 ; cylinder
    xor di,di                 ; head
    mov si,3                  ; physical sector 3, after 512-byte IPL
.loop:
    call read256
    jnc .read_ok
    mov al,'E'
    call putc
    jmp halt
.read_ok:
    mov al,'.'
    call putc
    add bx,256
    cmp bx,0x1800             ; 24 sectors, server slot
    je loaded
    inc si
    cmp si,17
    jb .loop
    mov si,1
    inc di
    cmp di,2
    jb .loop
    xor di,di
    inc bp
    jmp .loop

loaded:
    mov al,'J'
    call putc
    mov al,0                 ; fixed CP/M boot drive
    jmp 0x1000:0x0000

halt:
    cli
.again:
    hlt
    jmp .again

; Serial output does not disturb the load loop's registers.
putc:
    push ax
    push cx
    push dx
    mov ah,al
    mov dx,SER_STATUS
    mov cx,0xFFFF              ; no indefinite loop if TXRDY stays low
.wait:
    in al,dx
    test al,1
    jnz .ready
    loop .wait
    jmp .done                  ; no serial connection or USART failure
.ready:
    mov dx,SER_DATA
    mov al,ah
    out dx,al
.done:
    pop dx
    pop cx
    pop ax
    ret

; BX=DMA destination (bank 1); BP=cylinder; DI=head; SI=sector.
; Preserves BX/BP/DI/SI, clobbers AX/CX/DX.
; Return CF=0 only when FDC succeeded and DMA terminal count asserted.
read256:
    mov dx,DMA_MASK
    mov al,4
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
    mov al,0xFF
    out dx,al
    xor al,al
    out dx,al
    mov dx,DMA_BANK
    mov al,1
    out dx,al
    mov dx,DMA_MODE
    mov al,0x44
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
    xor al,al
    out dx,al                 ; unmask DMA CH0
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
    test al,1
    jz .bad
    clc
    jmp .finish
.bad:
    stc
.finish:
    pushf
    mov dx,DMA_MASK
    mov al,4
    out dx,al
    popf
    ret

; The boot ROM loads two 256-byte sectors as one first-stage image.
position_head:
    ; Drive 0 is the boot unit. The relocated IPL owns its position byte.
    mov dx,FDC_SIDE+1
    mov al,0x80
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
