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
    call cache_init
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

; Convert mailbox cylinder/record into CP/M-86 cache coordinates.
; Validate all fields before touching the cache or the FDC.
; cur_track = cylinder*2 + side; cur_sector = record within one side.
; Mailbox and DPBs retain their existing cylinder-based geometry.
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
    mov [cur_disk],al
    mov dx,32             ; logical records per 2D side
    cmp al,4
    jae .hd
    cmp bx,40
    jae .bad
    jmp .geometry
.hd:
    mov dx,52             ; logical records per 2HD side
    cmp bx,77
    jae .bad
.geometry:
    shl bx,1              ; cylinder -> even side-track
    mov ax,[es:MBOX_SECTOR]
    xchg al,ah
    cmp ax,dx
    jb .first_side
    sub ax,dx
    cmp ax,dx
    jae .bad
    inc bx
.first_side:
    mov [cur_track],bx
    mov [cur_sector],ax
    clc
    ret
.bad:
    stc
    ret

; CP/M-86-compatible cache transport adapter. FDC needs CH=cylinder,
; CL=1-based physical sector, DH=head, AL=logical drive.
; Preserve registers so eviction restores the original request.
sector_physical_read:
    push ax
    push bx
    push cx
    push dx
    call sector_floppy_chs
    call fdc2d_read
    pop dx
    pop cx
    pop bx
    pop ax
    ret

sector_physical_write:
    push ax
    push bx
    push cx
    push dx
    call sector_floppy_chs
    call fdc2d_write
    pop dx
    pop cx
    pop bx
    pop ax
    ret

sector_floppy_chs:
    mov bx,[cur_track]
    mov dx,bx
    and dl,1
    mov dh,dl
    shr bx,1
    mov ch,bl
    mov bx,[cur_sector]
    mov cl,bl
    shr cl,1
    inc cl
    mov al,[cur_disk]
    ret

; Translate current record to cache offset and segment.
; Validated cur_sector is at most 51 (2HD).
cache_record_address:
    mov bx,[cur_sector]
    mov cl,7
    shl bx,cl
    mov si,[cache_slot]
    shl si,1
    mov ax,[cache_segments+si]
    ret

read_record:
    call decode_request
    jc .done
    call cache_ensure
    jc .done
    call cache_record_address
    mov di,[request_dma]
    push ds
    mov ds,ax
    mov si,bx
    mov cx,64
    rep movsw
    pop ds
    clc
.done:
    ret

write_record:
    call decode_request
    jc .done
    mov al,[es:MBOX_DATA]  ; CP/M WRITE type in mailbox FLAGS/DATA
    mov [cache_write_type],al
    ; Directory metadata must never precede pending file data.
    cmp al,1
    jne .ensure
    call cache_flush_all
    jc .done
.ensure:
    call cache_ensure
    jc .done
    call cache_record_address
    mov di,bx
    mov si,[request_dma]
    push ds
    push es
    push es
    pop ds               ; source = CP/M memory
    mov es,ax            ; destination = selected cache window
    mov cx,64
    rep movsw
    pop es
    pop ds
    call cache_mark_dirty
    cmp byte [cache_write_type],1
    jne .ok
    call cache_flush_all
    ret
.ok:
    clc
.done:
    ret

%include "i8086/track_cache.inc"

boot_drive db 0
load_position dw 0
load_head db 0
request_dma dw 0
cur_disk db 0
cur_track dw 0
cur_sector dw 0
%include "i8086/floppy.inc"
%include "i8086/local_console.inc"
%include "i8086/ansi_console.inc"
times NATIVE_SLOT-($-$$) db 0
