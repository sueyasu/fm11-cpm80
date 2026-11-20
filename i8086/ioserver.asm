; FM-11 common native mailbox server. 8086 instruction set only.
; Target backend supplies the entry point and CP/M execution mechanism.
cpu 8086
bits 16
org 0
%include "i8086/memory.inc"
%include "i8086/mailbox.inc"

%include "i8086/cpu_z80.inc"

; Common cold initialization.
; IN: AL=boot drive (0 or 4), DS=CS=native segment, ES=CPM_SEG,
;     private native stack, maskable interrupts disabled.
; OUT: CF=0 system loaded and workspace initialized, CF=1 disk failure.
; Preserves segment registers and stack balance; general registers scratch.
; No CP/M entry instructions or CPU switching here.
server_cold_init:
    cld
    mov [boot_drive],al
    mov [es:BOOTDRV],al
    mov cl,2
    shr al,cl
    mov [es:BOOTTYPE],al
    call fdc_forget_all
    mov cx,26
    call reload_system
    jc .done
    xor ax,ax
    mov di,0xf970
    mov cx,0x278
    rep stosb
    mov byte [es:MBOX_CMD],0
    mov byte [es:MBOX_STATUS],0
    clc
.done:
    ret

; Execute exactly one posted mailbox request, then return to the backend.
; IN: DS=CS=native segment, ES=CPM_SEG, private native stack,
;     maskable interrupts disabled; complete mailbox request posted.
; OUT: STATUS=0/1, CMD=0, DATA as applicable, CF=0/1 matching STATUS.
; DS/ES/SS/SP restored, DF=0; general registers and other flags scratch.
; May block for input/output as specified by the existing mailbox ABI.
; No CPU hand-off here. Backend owns any interrupted/emulated CPU context.
server_dispatch:
    cld
    mov al,[es:MBOX_CMD]
    cmp al,1
    jne .not_read
    call read_record
    jmp finish
.not_read:
    cmp al,2
    jne .not_write
    call write_record
    jmp finish
.not_write:
    cmp al,3
    jne .not_boot
    call cache_reset
    jc failure
    mov byte [ansi_state],0
    mov cx,22
    call reload_system
    jmp finish
.not_boot:
    cmp al,MBCMD_CACHE_SYNC
    jne .not_cache_sync
    call cache_flush_all
    jmp finish
.not_cache_sync:
    cmp al,MBCMD_CACHE_RESET
    jne .not_cache_reset
    call cache_reset
    jmp finish
.not_cache_reset:
    cmp al,0x10
    jne .not_lconst
    call local_const
    jc failure
    jmp store_data
.not_lconst:
    cmp al,0x11
    jne .not_lin
    call local_conin
    jc failure
    jmp store_data
.not_lin:
    cmp al,0x12
    jne .not_lout
    mov al,[es:MBOX_DATA]
    call local_putc
    jmp finish
.not_lout:
    cmp al,0x13
    jne .not_sconst
    mov dx,0xfd07
    in al,dx
    and al,2
    jmp serial_status
.not_sconst:
    cmp al,0x14
    jne .not_sin
    mov dx,0xfd07
.wait_rx:
    in al,dx
    test al,2
    jz .wait_rx
    dec dx
    in al,dx
    jmp store_data
.not_sin:
    cmp al,0x15
    jne .not_sout
    mov dx,0xfd07
.wait_tx:
    in al,dx
    test al,1
    jz .wait_tx
    jmp serial_send
.not_sout:
    cmp al,0x16
    jne .not_listst
    mov dx,0xfd07
    in al,dx
    and al,1
    jmp serial_status
.not_listst:
    cmp al,0x17
    jne failure
    mov cx,0xffff
    mov dx,0xfd07
.mirror:
    in al,dx
    test al,1
    jnz serial_send
    loop .mirror
    jmp failure
serial_send:
    dec dx
    mov al,[es:MBOX_DATA]
    out dx,al
    jmp success
serial_status:
    or al,al
    jz store_data
    mov al,0xff
store_data:
    mov [es:MBOX_DATA],al
success:
    clc
finish:
    jnc finish_ok
failure:
    mov byte [es:MBOX_STATUS],1
    mov byte [es:MBOX_CMD],0
    stc
    ret
finish_ok:
    mov byte [es:MBOX_STATUS],0
    mov byte [es:MBOX_CMD],0
    clc
    ret

; Read CYL 1, sequential sectors, split at side boundary on 2D.
; CX = 26 cold / 22 warm. Copy 256 bytes to shared CP/M bank 1 per transfer.
reload_system:
    mov di,0xdc00
    mov word [load_position],0x0101
    mov byte [load_head],0
.next:
    push cx
    mov al,[boot_drive]
    mov cx,[load_position]
    mov dh,[load_head]
    call fdc2d_read
    pop cx
    jc .bad
    push cx
    mov si,fdc2d_buffer
    mov cx,128
    rep movsw
    pop cx
    inc byte [load_position]
    cmp byte [boot_drive],4
    jae .advance_hd
    cmp byte [load_position],17
    jb .advance_hd
    mov byte [load_position],1
    inc byte [load_head]
.advance_hd:
    loop .next
    clc
.bad:
    ret

; Validate and decode the CP/M cylinder and 128-byte record number.
; Outputs AL=drive, CH=cylinder, CL=physical sector, DH=head.
; Store half offset, DMA address and physical index for cache/copy.
decode_request:
    mov ax,[es:MBOX_DMA]
    xchg al,ah
    cmp ax,0xfb80
    ja .bad
    mov [request_dma],ax
    mov ax,[es:MBOX_TRACK]
    xchg al,ah
    mov bx,ax
    mov al,[es:MBOX_DRIVE]
    cmp al,8
    jae .bad
    mov dl,16
    cmp al,4
    jae .hd
    cmp bx,40
    jae .bad
    jmp .geometry
.hd:
    mov dl,26
    cmp bx,77
    jae .bad
.geometry:
    mov ch,bl
    mov ax,[es:MBOX_SECTOR]
    xchg al,ah
    xor dh,dh
    mov bx,dx
    shl bx,1
    shl bx,1
    cmp ax,bx
    jae .bad
    mov bx,ax
    and bx,1
    mov cl,7
    shl bx,cl
    mov [half_offset],bx
    shr ax,1
    mov [request_index],al
    xor dh,dh
    cmp al,dl
    jb .head
    sub al,dl
    inc dh
.head:
    inc al
    mov cl,al
    mov al,[es:MBOX_DRIVE]
    clc
    ret
.bad:
    stc
    ret

; Write-through: all successful writes are already on disk.
; Write-back will replace this routine without changing its CF contract.
cache_flush_all:
    clc
    ret

; Flush before invalidating data or hardware position state.
cache_reset:
    call cache_flush_all
    jc .done
    mov byte [cache_valid],0
    call fdc_forget_all
    clc
.done:
    ret

; Single-cylinder write-through cache: 52 sectors at physical 06000h.
; DS=NATIVE_SEG, temporarily select CACHE_SEG while copying cache data.
; A miss fills just the requested sector. Never cache failed transfers.
read_physical:
    call decode_request
    jc .bad
    cmp byte [cache_valid],0
    je .new
    cmp al,[cache_drive]
    jne .new
    cmp ch,[cache_track]
    je .lookup
.new:
    mov [cache_drive],al
    mov [cache_track],ch
    mov byte [cache_valid],1
    push ax
    push cx
    push di
    push es
    push ds
    pop es
    xor ax,ax
    mov di,cache_map
    mov cx,52
    rep stosb
    pop es
    pop di
    pop cx
    pop ax
.lookup:
    xor bx,bx
    mov bl,[request_index]
    cmp byte [cache_map+bx],0
    je .miss
    push ds
    push es
    push cs
    pop es
    mov ax,CACHE_SEG
    mov ds,ax
    mov si,bx
    mov cl,8
    shl si,cl
    mov di,fdc2d_buffer
    mov cx,128
    rep movsw
    pop es
    pop ds
    clc
    ret
.miss:
    call fdc2d_read
    jc .bad
    call cache_store
    clc
    ret
.bad:
    mov byte [cache_valid],0
    stc
    ret

cache_store:
    push es
    mov ax,CACHE_SEG
    mov es,ax
    xor bx,bx
    mov bl,[request_index]
    mov byte [cache_map+bx],1
    mov di,bx
    mov cl,8
    shl di,cl
    mov si,fdc2d_buffer
    mov cx,128
    rep movsw
    pop es
    ret

read_record:
    call read_physical
    jc .done
    mov si,fdc2d_buffer
    add si,[half_offset]
    mov di,[request_dma]
    mov cx,64
    rep movsw
    clc
.done:
    ret

write_record:
    call read_physical
    jc .done
    push ds
    push es
    ; Source is CP/M RAM in bank 1; destination is the native bounce buffer.
    push es
    pop ds
    push cs
    pop es
    mov si,[es:request_dma]
    mov di,[es:half_offset]
    add di,fdc2d_buffer
    mov cx,64
    rep movsw
    pop es
    pop ds
    call decode_request
    jc .done
    call fdc2d_write
    jc .failed
    call cache_store
    clc
.done:
    ret
.failed:
    mov byte [cache_valid],0
    stc
    ret

diagnostic:
    push ax
    mov ah,al
    mov dx,0xfd07
    mov cx,0xffff
.wait:
    in al,dx
    test al,1
    jnz .send
    loop .wait
    jmp .done
.send:
    dec dx
    mov al,ah
    out dx,al
.done:
    pop ax
    ret

boot_drive db 0
load_position dw 0
load_head db 0
request_dma dw 0
half_offset dw 0
request_index db 0
cache_valid db 0
cache_drive db 0
cache_track db 0
cache_map times 52 db 0
%include "i8086/floppy.inc"
%include "i8086/local_console.inc"
%include "i8086/ansi_console.inc"
times NATIVE_SLOT-($-$$) db 0
