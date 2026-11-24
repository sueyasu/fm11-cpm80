; 8237/FDC transport adapted from fm11-cpm86 8f094f9 (MIT).
fdc2d_read:
    mov byte [fdc_raw],0
    mov ah,0x44              ; CH0, single, I/O -> memory
    jmp fdc2d_transfer

fdc2d_write:
    mov byte [fdc_raw],0
    mov ah,0x48              ; CH0, single, memory -> I/O

fdc2d_transfer:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    mov bp,dx                ; preserve head in DH before DX becomes I/O port

    mov bx,ax                ; BL=logical drive, BH=8237 CH0 mode
    mov byte [fdc_channel],0
    cmp bl,8
    jae .invalid
    cmp dh,1
    ja .invalid
    cmp cl,1
    jb .invalid
    cmp bl,4
    jb .validate_2d
    sub bl,4                 ; E:..H: -> standard FDC units 0..3
    mov byte [fdc_channel],1
    inc bh                   ; CH0 mode 44/48 -> CH1 45/49
    cmp ch,77
    jae .invalid
    cmp cl,26
    ja .invalid
    jmp .validated
.validate_2d:
    cmp ch,40
    jae .invalid
    cmp cl,16
    ja .invalid
    jmp .validated
.invalid:
    jmp .bad               ; 8086 conditional branches have 8-bit reach
.validated:
    mov byte [fdc_attempts],10
    cmp byte [fdc_raw],0
    je .retry
    mov byte [fdc_attempts],1 ; no retry of destructive raw operations
.retry:
    ; The polling loop consumes CX; keep the original cylinder/sector.
    push cx
    call .attempt
    pop cx
    jc .retry_failed
    jmp .restore
.retry_failed:
    call fdc_position_index
    mov byte [fdc_cylinder+si],0xff ; re-home after any failed attempt
    dec byte [fdc_attempts]
    jz .give_up
    ; Do not issue another command while the controller is transferring.
    mov dx,0xfd18
    cmp byte [fdc_channel],0
    je .retry_status
    mov dl,0x30
.retry_status:
    in al,dx
    test al,0x03            ; BUSY or DRQ: do not interrupt a live transfer
    jz .retry
.give_up:
    jmp .bad

.attempt:
    ; Type I commands must never run with the selected DMA channel enabled.
    mov dx,0x1a
    mov al,4
    add al,[fdc_channel]
    out dx,al
    call fdc_seek
    jnc .positioned
    ret
.positioned:
    cmp byte [fdc_raw],0
    je .private_dma
    mov si,[raw_dma]
    mov di,CPM_SEG/0x1000
    mov ax,[raw_length]
    dec ax
    jmp .dma_count_ready
.private_dma:
    ; Convert the real-mode CS:offset into an 8237 bank:offset address.
    ; 256-byte transfer must not cross a 64 KiB DMA page boundary.
    mov ax,cs
    mov si,16
    mul si                   ; DX:AX = CS * 16
    add ax,fdc2d_buffer
    adc dx,0
    cmp ax,0xff00
    jbe .dma_ok
    stc
    ret
.dma_ok:
    mov si,ax                ; 16-bit DMA address
    mov di,dx                ; DMA bank (bits 16..19)
    mov ax,255
.dma_count_ready:
    push ax

    mov dx,0x1c             ; reset 8237 address/count flip-flop
    xor al,al
    out dx,al

    mov dx,0x10             ; CH0 address=10h, CH1 address=12h
    cmp byte [fdc_channel],0
    je .address_port
    mov dl,0x12
.address_port:
    mov ax,si
    out dx,al
    mov al,ah
    out dx,al

    mov dx,0x11             ; CH0 count=11h, CH1 count=13h
    cmp byte [fdc_channel],0
    je .count_port
    mov dl,0x13
.count_port:
    pop ax
    out dx,al
    mov al,ah
    out dx,al

    mov dx,0x20             ; CH0 bank=20h, CH1 bank=21h
    cmp byte [fdc_channel],0
    je .bank_port
    mov dl,0x21
.bank_port:
    mov ax,di
    out dx,al
    mov dx,0x1b             ; transfer direction, selected single mode
    mov al,bh
    out dx,al
    mov dx,0x18             ; discard any previous terminal-count latch
    in al,dx

    mov dx,0xfd1a           ; sector register; track set by fdc_seek
    cmp byte [fdc_channel],0
    je .sector_port
    mov dl,0x32
.sector_port:
    mov al,cl
    out dx,al
    mov dx,0xfd1c           ; FD1C or FD34: side
    cmp byte [fdc_channel],0
    je .side_port
    mov dl,0x34
.side_port:
    mov ax,bp                ; original caller DH, not port high byte FDh
    mov al,ah
    out dx,al
    inc dx                  ; FD1D: physical drive
    mov al,bl
    cmp byte [fdc_channel],0
    jne .drive_ready
    or al,0x80
.drive_ready:
    out dx,al

    mov dx,0x1a             ; unmask selected channel
    mov al,[fdc_channel]
    out dx,al
    mov dx,0xfd18
    cmp byte [fdc_channel],0
    je .command_port
    mov dl,0x30
.command_port:
    mov al,0x80
    cmp bh,0x44
    je .start
    cmp bh,0x45
    je .start
    mov al,0xa0
.start:
    cmp byte [fdc_raw],0
    je .issue
    mov al,[raw_fdc_command]
.issue:
    out dx,al

    ; Poll until FDC no longer indicates a transfer in progress.
    ; Fail closed on controller error and on a bounded poll timeout.
    mov cx,0xffff
.poll:
    in al,dx
    test al,0x10            ; Mini FDC error
    jnz .fail
    test al,0x03            ; BUSY (bit 0) or DRQ (bit 1)
    jz .status_done
    loop .poll
    jmp .fail

.status_done:
    or al,al                ; success requires status = 0
    jnz .fail
    mov dx,0x18
    in al,dx                ; 8237 terminal count (CH0=bit0, CH1=bit1)
    cmp byte [fdc_channel],0
    je .check_tc0
    test al,2
    jz .fail
    jmp .tc_ok
.check_tc0:
    test al,1
    jz .fail
.tc_ok:
    clc
    jmp .finish
.fail:
    stc
.finish:
    pushf
    mov dx,0x1a             ; leave selected DMA channel masked
    mov al,4
    add al,[fdc_channel]
    out dx,al
    popf
    ret
.bad:
    stc
.restore:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; BL = physical unit, BH = 8237 mode (bit 0 is controller channel).
; SI = position-table index, independent of the requested CP/M drive.
fdc_position_index:
    mov si,bx
    and si,3
    test bh,1
    jz .done
    add si,4
.done:
    ret

; CH = desired cylinder, BL = unit, BH = DMA mode.
; Preserve BX/CX/BP; only AX/DX/SI are scratch. DMA is masked by caller.
; Each controller has one TRACK register shared by its four drives;
; restore the selected drive's saved position BEFORE issuing SEEK.
fdc_seek:
    call fdc_position_index
    mov dx,0xfd1d
    cmp byte [fdc_channel],0
    je .select
    mov dl,0x35
.select:
    mov al,bl
    cmp byte [fdc_channel],0
    jne .motor_ready
    or al,0x80
.motor_ready:
    out dx,al
    sub dx,5                 ; FD18/FD30 command/status
    call fdc_wait_idle
    jc .done
    mov al,[fdc_cylinder+si]
    cmp al,0xff
    jne .known
    mov al,0x0b              ; RESTORE, no verify
    call fdc_type1
    jc .done
    xor al,al
    mov [fdc_cylinder+si],al
.known:
    inc dx                   ; restore controller TRACK register
    out dx,al
    dec dx
    cmp al,ch
    je .success
    add dx,3                 ; DATA = requested SEEK destination
    mov al,ch
    out dx,al
    sub dx,3
    mov al,0x1b              ; SEEK, no verify
    call fdc_type1
    jc .done
    mov [fdc_cylinder+si],ch
.success:
    clc
.done:
    ret

; Wait for Type I completion. Bit 1 is INDEX, not DRQ in Type I status.
; Allow BUSY to assert before polling; keep the requested CH/CL intact.
fdc_type1:
    out dx,al
    push cx
    mov cx,16
.delay:
    loop .delay
    pop cx
    call fdc_wait_idle
    jc .done
    test al,0x90             ; not ready or seek error
    jz .done                 ; TEST clears CF
    stc
.done:
    ret

fdc_wait_idle:
    ; Timed FDC SEEK can exceed two seconds across 76 tracks.
    ; Use a bounded outer timeout instead of a single 16-bit poll.
    push bx
    push cx
    mov bx,64
.retry:
    mov cx,0xffff
.poll:
    in al,dx
    test al,1
    jz .done                 ; TEST clears CF
    loop .poll
    dec bx
    jnz .retry
    stc
.done:
    pop cx
    pop bx
    ret

; Cold init and cache reset/media login must forget hardware positions.
; Keep registers and FLAGS unchanged (also used after direct-I/O utility).
fdc_forget_all:
    mov word [fdc_cylinder],0xffff
    mov word [fdc_cylinder+2],0xffff
    mov word [fdc_cylinder+4],0xffff
    mov word [fdc_cylinder+6],0xffff
    ret


fdc_raw db 0
fdc_channel db 0
fdc_attempts db 0
fdc_cylinder: times 8 db 0xff
fdc2d_buffer: times 256 db 0
