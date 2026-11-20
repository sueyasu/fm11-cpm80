; Adapted from fm11-cpm86 8f094f9 (MIT).
; FM-11 8088 native display/keyboard console.
; Hardware protocol from NitrOS-9 fm11console.asm and CP/M-80 ioserver.asm.
; CONSOLE_LOCAL is an 8086 build-time choice; the serial paths remain in
; cbios.asm for the diagnostic image and for explicit serial builds.
;
; FD05: bit 7 HALT display CPU request, bit 0 CPU-card selection (keep 0).
; FC80/FC81 = leading zeroes, FC82 = sub command, FC83 = parameter/result
; FC84 = INKEY 2 returned keycode low byte.
; Command 12h = CHARACTER OUT, 2Dh = INKEY 2.
SUB_CPU_CTRL equ 0xFD05
SUB_MAILBOX  equ 0xFC80
SUB_CHAROUT  equ 0x12
SUB_INKEY2   equ 0x2D

; AL=command, AH=parameter. On success CF=0, AH=status/result FC83,
; AL=data/result FC84. On failure CF=1.
; Never touches DS/ES/SS, SI/DI/BP or the caller's other registers.
local_subcall:
    push bx
    push cx
    push dx
    mov bx,ax
    mov dx,SUB_CPU_CTRL
    mov cx,0xffff
.wait_ready:
    in al,dx
    test al,0x80
    jz .halt
    loop .wait_ready
    jmp short .failed
.halt:
    mov al,0x80
    out dx,al
    mov cx,0xffff
.wait_halt:
    in al,dx
    test al,0x80
    jnz .install
    loop .wait_halt
    xor al,al
    out dx,al
    jmp short .failed
.install:
    mov dx,SUB_MAILBOX
    xor al,al
    out dx,al
    inc dx
    out dx,al
    inc dx
    mov al,bl
    out dx,al
    inc dx
    mov al,bh
    out dx,al
    inc dx
    xor al,al
    out dx,al
    mov dx,SUB_CPU_CTRL
    out dx,al
    mov cx,0xffff
.wait_complete:
    in al,dx
    test al,0x80
    jz .completed
    loop .wait_complete
    jmp short .failed
.completed:
    mov dx,SUB_MAILBOX+3
    in al,dx
    mov ah,al
    inc dx
    in al,dx
    clc
    jmp short .return
.failed:
    stc
.return:
    pop dx
    pop cx
    pop bx
    ret

; Byte to native FM-11 CHARACTER OUT, not ANSI/VT100 passthrough.
; Input AL=byte; preserves AX and all other caller registers.
local_putc:
    jmp ansi_putc

; Uninterpreted native character/command byte for the ANSI translator.
local_native_putc:
    push ax
    mov ah,al
    mov al,SUB_CHAROUT
    call local_subcall
    pop ax
    ret

local_puts:
.next:
    lodsb
    or al,al
    jz .end
    call local_putc
    jmp short .next
.end:
    ret

; Store locally fetched bytes to make CONST non-destructive.
; Arrow keys are delivered as ESC [ A/B/C/D.
; 0114h is the FM-11 DEL key; INKEY2 other extended codes ignored.
local_poll:
    cmp byte [local_key_valid],0
    jne .done
    cmp byte [local_seq_count],0
    je .fetch
    mov al,[local_seq_first]
    mov [local_key_byte],al
    mov al,[local_seq_second]
    mov [local_seq_first],al
    mov byte [local_seq_second],0
    dec byte [local_seq_count]
    mov byte [local_key_valid],1
    ret
.fetch:
    xor ah,ah
    mov al,SUB_INKEY2
    call local_subcall
    jc .done
    cmp ah,0
    jne .extended
    or al,al               ; 0 means no key from INKEY2
    jz .done
    jmp short .store
.extended:
    cmp ah,1
    jne .done
    cmp al,0x14
    je .delete
    cmp al,0x16
    je .up
    cmp al,0x17
    je .down
    cmp al,0x18
    je .left
    cmp al,0x19
    je .right
    ret
.delete:
    mov al,0x7f
    jmp short .store
.up:
    mov ah,'A'
    jmp short .arrow
.down:
    mov ah,'B'
    jmp short .arrow
.left:
    mov ah,'D'
    jmp short .arrow
.right:
    mov ah,'C'
.arrow:
    mov byte [local_seq_first],'['
    mov [local_seq_second],ah
    mov byte [local_seq_count],2
    mov al,0x1b
.store:
    mov [local_key_byte],al
    mov byte [local_key_valid],1
.done:
    ret

local_const:
    call local_poll
    xor al,al
    cmp byte [local_key_valid],0
    je .done
    dec al                 ; CP/M-86 CONST expects 0xFF for ready
.done:
    ret

local_conin:
.wait:
    call local_poll
    cmp byte [local_key_valid],0
    je .wait
    mov al,[local_key_byte]
    mov byte [local_key_valid],0
    ret

local_key_valid   db 0
local_key_byte    db 0
local_seq_count   db 0
local_seq_first   db 0
local_seq_second  db 0
