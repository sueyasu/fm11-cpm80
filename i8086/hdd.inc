; Adapted from fm11-cpm86 src/cbios_hdd.inc (f72336a, MIT).
; FM-11 whole-HDD MDC transport for CP/M-80 I:.
; The MDC uses 256-byte records and the 8237 DMA2 channel.
; Logical sector = side-track * 32 + (CP/M record / 2).
; Binary-sector addressing avoids a 16-bit CHS cylinder limitation.

hdd_sense:
    push ax
    push bx
    push cx
    push dx
    mov dx,0xfdc2
    mov al,0x20               ; physical drive 0, DMA channel 2
    out dx,al
    mov dx,0xfdc0
    mov al,0x14               ; SENSE (2-byte parameters)
    out dx,al
    mov dx,0xfdc1
    xor al,al
    out dx,al
    out dx,al
    call hdd_wait
    jnc .sense_ok
    jmp .bad
.sense_ok:
    mov al,[hdd_result+4]     ; model type code
    mov word [hdd_cylinders],315
    mov byte [hdd_heads],4
    cmp al,0x04
    jne .t08
    mov word [hdd_cylinders],157
    jmp .geometry
.t08:
    cmp al,0x08
    jne .t05
    mov byte [hdd_heads],2
    jmp .geometry
.t05:
    cmp al,0x05
    jne .t09
    mov word [hdd_cylinders],157
    mov byte [hdd_heads],6
    jmp .geometry
.t09:
    cmp al,0x09
    je .geometry
    cmp al,0x0a
    jne .t0c
    mov byte [hdd_heads],6
    jmp .geometry
.t0c:
    cmp al,0x0c
    jne .t14
    mov byte [hdd_heads],8
    jmp .geometry
.t14:
    cmp al,0x14
    jne .t15
    mov word [hdd_cylinders],747
    jmp .geometry
.t15:
    cmp al,0x15
    jne .t16
    mov word [hdd_cylinders],747
    mov byte [hdd_heads],7
    jmp .geometry
.t16:
    cmp al,0x16
    jne .bad
    mov word [hdd_cylinders],747
    mov byte [hdd_heads],11
.geometry:
    mov ax,[hdd_cylinders]
    xor bx,bx
    mov bl,[hdd_heads]
    mul bx
    mov [hdd_total_tracks],ax
    sub ax,bx                 ; remove reserved cylinder
    shr ax,1                  ; two head-tracks per 16-KiB block
    dec ax
    mov [hdd_dsm],ax         ; DSM
    ; hdd_heads is OFF in physical side-tracks.
    ; Enter binary LBA mode, avoiding CHS arithmetic in I/O path.
    mov dx,0xfdc0
    mov al,0x11              ; SET CMASK
    out dx,al
    mov dx,0xfdc1
    mov al,0x70              ; binary sector addressing
    out dx,al
    xor al,al
    out dx,al
    call hdd_wait
    jmp .done
.bad:
    stc
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Wait until result phase, fetch all ten result bytes.
hdd_wait:
    push bx
    push cx
    push dx
    mov dx,0xfdc0
    mov cx,0xffff
.poll:
    in al,dx
    test al,0x40
    jnz .ready
    loop .poll
    jmp .fail
.ready:
    mov dx,0xfdc1
    mov bx,hdd_result
    mov cx,10
.fetch:
    in al,dx
    mov [bx],al
    inc bx
    loop .fetch
    test byte [hdd_result],0x80
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

hdd_read:
    mov byte [hdd_rw],0
    jmp hdd_transfer
hdd_write:
    mov byte [hdd_rw],1

; AL, BX, CX, DX, SI, DI and BP preserved. DS=CS on entry.
; The sector bounce buffer is fdc2d_buffer (256 bytes), DMA-safe at
; the resident 0400h segment. CF indicates success/failure.
hdd_transfer:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    ; DWORD LBA = track * 32 + (record >> 1)
    mov ax,[cur_track]
    mov bx,32
    mul bx                  ; DX:AX = track * 32
    mov si,[cur_sector]
    shr si,1
    add ax,si
    adc dx,0
    mov [hdd_lba_lo],ax
    mov [hdd_lba_hi],dx

    mov ax,cs
    mov bx,16
    mul bx
    add ax,fdc2d_buffer
    adc dx,0
    cmp ax,0xff00
    jbe .dma_low_ok
    jmp .bad
.dma_low_ok:
    cmp dx,15
    jbe .dma_bank_ok
    jmp .bad
.dma_bank_ok:
    mov si,ax
    mov di,dx
    mov byte [hdd_attempts],3
.retry:
    call .attempt
    jc .retry_failed
    jmp .return
.retry_failed:
    dec byte [hdd_attempts]
    jz .give_up
    ; A completed result is drained by hdd_wait. Never start a new
    ; command if the MDC has not returned to command-ready state.
    mov dx,0xfdc0
    in al,dx
    test al,0x80
    jnz .retry
.give_up:
    jmp .bad

.attempt:
    mov dx,0x1a
    mov al,6                ; mask DMA2
    out dx,al
    mov dx,0x1c
    xor al,al
    out dx,al
    mov dx,0x14             ; DMA2 address
    mov ax,si
    out dx,al
    mov al,ah
    out dx,al
    mov dx,0x15             ; DMA2 count
    mov al,0xff
    out dx,al
    xor al,al
    out dx,al
    mov dx,0x22             ; DMA2 bank
    mov ax,di
    out dx,al
    mov dx,0x1b
    mov al,0x46             ; I/O -> memory, CH2
    cmp byte [hdd_rw],0
    je .dma_mode
    mov al,0x4a             ; memory -> I/O, CH2
.dma_mode:
    out dx,al
    mov dx,0x18
    in al,dx                ; clear TC latch

    mov dx,0xfdc2
    mov al,0x20             ; one physical drive, DMA2
    out dx,al
    mov dx,0x1a
    mov al,2
    out dx,al               ; unmask DMA2

    mov dx,0xfdc0
    mov al,0x22             ; READ
    cmp byte [hdd_rw],0
    je .command
    mov al,0x23             ; WRITE
.command:
    out dx,al
    mov dx,0xfdc1
    xor al,al
    out dx,al               ; drive 0
    out dx,al               ; reserved
    mov ax,[hdd_lba_hi]
    mov al,ah
    out dx,al               ; LBA bits 31..24
    mov ax,[hdd_lba_hi]
    out dx,al               ; LBA bits 23..16
    mov ax,[hdd_lba_lo]
    mov al,ah
    out dx,al               ; LBA bits 15..8
    mov ax,[hdd_lba_lo]
    out dx,al               ; LBA bits 7..0
    mov al,1
    out dx,al               ; transfer 256 bytes
    xor al,al
    out dx,al

    call hdd_wait
    jc .transfer_fail
    mov dx,0x18
    in al,dx
    test al,4               ; DMA2 terminal count
    jz .transfer_fail
    clc
    jmp .finish
.transfer_fail:
    stc
.finish:
    pushf
    mov dx,0x1a
    mov al,6
    out dx,al               ; mask DMA2 again
    popf
    ret
.bad:
    stc
.return:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hdd_ready db 0
hdd_dsm dw 0
hdd_cylinders dw 0
hdd_total_tracks dw 0
hdd_heads db 0
hdd_rw db 0
hdd_attempts db 0
hdd_lba_lo dw 0
hdd_lba_hi dw 0
hdd_result: times 10 db 0

; Return geometry in the existing big-endian mailbox word fields.
; Cache successful SENSE until CACHE_RESET/WBOOT, not failures.
hdd_geometry:
    cmp byte [hdd_ready],0
    jne .publish
    call hdd_sense
    jc .done
    mov byte [hdd_ready],1
.publish:
    mov ax,[hdd_dsm]
    xchg al,ah
    mov [es:MBOX_TRACK],ax
    mov ah,[hdd_heads]
    xor al,al
    mov [es:MBOX_SECTOR],ax
    clc
.done:
    ret
