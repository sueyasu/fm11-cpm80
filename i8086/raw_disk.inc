; Public RAW_DISK_API, all mailbox words big-endian.
; FDD raw DMA is directly to/from guest bank 1; HDD uses existing bounce.
raw_service:
    cmp al,MBCMD_CPU_TYPE
    jne .disk
%ifdef FM11_V20
    mov byte [es:MBOX_DATA],2
%else
    mov byte [es:MBOX_DATA],1
%endif
    clc
    ret
.disk:
    mov [raw_op],al
    call raw_decode
    jnc .raw_skip1
    jmp .done
.raw_skip1:
    cmp byte [raw_op],MBCMD_RAW_GEOM
    jne .transfer
    mov ax,[raw_tracks]
    xchg al,ah
    mov [es:MBOX_TRACK],ax
    mov al,[raw_n]
    mov ah,[raw_spt]
    mov [es:MBOX_SECTOR],ax
    mov al,[raw_heads]
    mov [es:MBOX_DATA],al
    clc
    ret
.transfer:
    ; Only TPA buffers; no wrapping, page-zero or resident overwrite.
    mov ax,[es:MBOX_DMA]
    xchg al,ah
    cmp ax,0x100
    jae .raw_skip2
    jmp .bad
.raw_skip2:
    mov [raw_dma],ax
    add ax,[raw_length]
    jnc .raw_skip3
    jmp .bad
.raw_skip3:
    cmp ax,0xdc00
    jbe .raw_skip4
    jmp .bad
.raw_skip4:
    call cache_reset
    jnc .raw_skip5
    jmp .done
.raw_skip5:
    ; cache reset can invalidate geometry and change physical coordinates.
    call raw_decode
    jnc .raw_skip6
    jmp .done
.raw_skip6:
    cmp byte [cur_disk],8
    je .hdd
    call sector_floppy_chs
    mov ah,0x44
    mov byte [raw_fdc_command],0x80
    cmp byte [raw_op],MBCMD_RAW_READ
    je .issue
    mov ah,0x48
    mov byte [raw_fdc_command],0xa0
    cmp byte [raw_op],MBCMD_RAW_FORMAT
    jne .issue
    mov byte [raw_fdc_command],0xf0
.issue:
    mov byte [fdc_raw],1
    call fdc2d_transfer
    mov byte [fdc_raw],0
    ret
.hdd:
    cmp byte [raw_op],MBCMD_RAW_READ
    je .hread
    push ds
    push es
    push es
    pop ds
    push cs
    pop es
    mov si,[cs:raw_dma]
    mov di,fdc2d_buffer
    mov cx,128
    rep movsw
    pop es
    pop ds
    jmp hdd_write
.hread:
    call hdd_read
    jnc .raw_skip7
    jmp .done
.raw_skip7:
    mov si,fdc2d_buffer
    mov di,[raw_dma]
    mov cx,128
    rep movsw
    clc
.done:
    ret
.bad:
    stc
    ret

; Decode side-track + one-based physical sector; reject malformed requests.
raw_decode:
    mov al,[es:MBOX_DRIVE]
    cmp al,8
    jbe .raw_skip8
    jmp .bad
.raw_skip8:
    mov [cur_disk],al
    mov bx,[es:MBOX_TRACK]
    xchg bl,bh
    mov [cur_track],bx
    mov byte [raw_n],1
    mov byte [raw_heads],2
    mov word [raw_tracks],80
    mov byte [raw_spt],16
    mov word [raw_length],256
    cmp al,4
    jb .geometry
    je .hd
    cmp al,8
    je .hdd
.hd:
    mov word [raw_tracks],154
    mov byte [raw_spt],26
    test bx,bx
    jnz .geometry
    mov byte [raw_n],0
    mov word [raw_length],128
    jmp .geometry
.hdd:
    call hdd_ensure_ready
    jnc .raw_skip9
    jmp .bad
.raw_skip9:
    mov ax,[hdd_total_tracks]
    mov [raw_tracks],ax
    mov al,[hdd_heads]
    mov [raw_heads],al
    mov byte [raw_spt],32
.geometry:
    cmp bx,[raw_tracks]
    jb .raw_skip10
    jmp .bad
.raw_skip10:
    cmp byte [raw_op],MBCMD_RAW_GEOM
    je .ok
    cmp byte [raw_op],MBCMD_RAW_FORMAT
    jne .sector
    cmp byte [cur_disk],8
    jne .raw_skip11
    jmp .bad
.raw_skip11:
    mov word [raw_length],6400
    cmp byte [cur_disk],4
    jb .format
    mov word [raw_length],10900
.format:
    mov word [cur_sector],0
    jmp .ok
.sector:
    mov ax,[es:MBOX_SECTOR]
    xchg al,ah
    cmp ah,0
    je .raw_skip12
    jmp .bad
.raw_skip12:
    cmp al,1
    jae .raw_skip13
    jmp .bad
.raw_skip13:
    cmp al,[raw_spt]
    jbe .raw_skip14
    jmp .bad
.raw_skip14:
    dec ax
    shl ax,1
    mov [cur_sector],ax
.ok:
    clc
    ret
.bad:
    stc
    ret

raw_op db 0
raw_n db 0
raw_heads db 0
raw_spt db 0
raw_tracks dw 0
raw_length dw 0
raw_dma dw 0
raw_fdc_command db 0
