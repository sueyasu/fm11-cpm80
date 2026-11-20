; Adapted from fm11-cpm86 src/hdd_boot_io.inc at f72336a (MIT).
; FM-11 8088 MDC HDD read-only first-stage helpers.
; Both the HDD reset ROM and disk IPL use binary LBA and DMA channel 2.
; Input hdd_read_sector: SI=physical sector LBA (0..63), BX=physical RAM
; destination (below 64 KiB). Preserves general registers, returns CF.
hdd_set_binary:
    mov dx,0xfdc2
    mov al,0x20              ; HDD0, DMA2
    out dx,al
    mov dx,0xfdc0
    mov al,0x11
    out dx,al                ; SET CMASK
    mov dx,0xfdc1
    mov al,0x70              ; binary LBA
    out dx,al
    xor al,al
    out dx,al
    call hdd_result_wait
    ret

hdd_read_sector:
    push ax
    push bx
    push cx
    push dx
    push si
    mov dx,0x1a
    mov al,6
    out dx,al                ; mask DMA2
    mov dx,0x1c
    xor al,al
    out dx,al                ; reset 8237 flip-flop
    mov dx,0x14
    mov ax,bx
    out dx,al
    mov al,ah
    out dx,al                ; physical destination low 16 bits
    mov dx,0x15
    mov al,0xff
    out dx,al
    xor al,al
    out dx,al                ; 0x00ff count = 256 bytes
    mov dx,0x22
    out dx,al                ; DMA bank 0
    mov dx,0x1b
    mov al,0x46              ; single, IO-to-memory, DMA2
    out dx,al
    mov dx,0x18
    in al,dx                 ; clear terminal-count latch
    mov dx,0xfdc2
    mov al,0x20
    out dx,al
    mov dx,0x1a
    mov al,2
    out dx,al                ; unmask DMA2
    mov dx,0xfdc0
    mov al,0x22
    out dx,al                ; MDC READ
    mov dx,0xfdc1
    xor al,al
    out dx,al                ; drive 0
    out dx,al                ; reserved
    out dx,al                ; LBA bits 31..24
    out dx,al                ; LBA bits 23..16
    mov ax,si
    mov al,ah
    out dx,al                ; bits 15..8
    mov ax,si
    out dx,al                ; bits 7..0
    mov al,1
    out dx,al                ; transfer length 0100h
    xor al,al
    out dx,al
    call hdd_result_wait
    jc .bad
    mov dx,0x18
    in al,dx
    test al,4
    jz .bad
    clc
    jmp .done
.bad:
    stc
.done:
    pushf
    mov dx,0x1a
    mov al,6
    out dx,al
    popf
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hdd_result_wait:
    push bx
    push cx
    push dx
    mov dx,0xfdc0
    mov cx,0xffff
.poll:
    in al,dx
    test al,0x40            ; MDC result ready
    jnz .ready
    loop .poll
    jmp .fail
.ready:
    mov dx,0xfdc1
    in al,dx                ; result[0]
    mov bl,al
    mov cx,9
.drain:
    in al,dx
    loop .drain
    test bl,0x80
    jnz .fail
    clc
    jmp .done
.fail:
    stc
.done:
    pop dx
    pop cx
    pop bx
    ret
