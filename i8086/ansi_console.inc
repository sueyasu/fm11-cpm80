; Adapted from fm11-cpm86 8f094f9 (MIT).
; CP/M-86 ANSI/VT100 to FM-11 CHARACTER OUT translator.
; Mirrors the Level-1 NitrOS-9 fm11console supported sequences.
; All parser state belongs to the resident CBIOS, not to the serial side.
; Entry AL=character. Preserves all general registers and FLAGS.
ANSI_ESC equ 27
ANSI_COLS equ 80
ANSI_ROWS equ 25

ansi_putc:
    pushf
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    cmp byte [ansi_state],0
    je .normal
    cmp byte [ansi_state],1
    je .escape
    jmp .csi
.normal:
    cmp al,ANSI_ESC
    jne .ordinary
    mov byte [ansi_state],1
    jmp .done
.ordinary:
    call ansi_raw_tracked
    jmp .done
.escape:
    mov byte [ansi_state],0
    cmp al,'['
    je .start_csi
    cmp al,'7'
    je .save
    cmp al,'8'
    je .restore
    cmp al,'c'
    je .reset
    cmp al,'D'
    je .index
    cmp al,'M'
    je .reverse_index
    cmp al,'E'
    je .next_line
    cmp al,'T'
    je .native_esc
    cmp al,'Y'
    je .native_esc
    cmp al,'*'
    je .native_esc
    jmp .done
.native_esc:
    mov bl,al
    mov al,ANSI_ESC
    call ansi_raw
    mov al,bl
    call ansi_raw
    jmp .done
.start_csi:
    mov byte [ansi_state],2
    mov byte [ansi_p1],0
    mov byte [ansi_p2],0
    mov byte [ansi_second],0
    mov byte [ansi_private],0
    jmp .done
.save:
    mov al,[ansi_row]
    mov [ansi_save_row],al
    mov al,[ansi_col]
    mov [ansi_save_col],al
    jmp .done
.restore:
    mov al,[ansi_save_row]
    mov ah,[ansi_save_col]
    call ansi_goto
    jmp .done
.reset:
    call ansi_clear_home
    mov byte [ansi_attr],7
    call ansi_apply_attr
    jmp .done
.index:
    mov al,0x1f
    call ansi_raw_tracked
    jmp .done
.reverse_index:
    mov al,0x1e
    call ansi_raw_tracked
    jmp .done
.next_line:
    mov al,0x1f
    call ansi_raw_tracked
    mov al,13
    call ansi_raw_tracked
    jmp .done
.csi:
    cmp al,'0'
    jb .not_digit
    cmp al,'9'
    ja .not_digit
    sub al,'0'
    mov bl,al
    cmp byte [ansi_second],0
    jne .digit2
    mov al,[ansi_p1]
    mov cl,10
    mul cl
    add al,bl
    mov [ansi_p1],al
    jmp .done
.digit2:
    mov al,[ansi_p2]
    mov cl,10
    mul cl
    add al,bl
    mov [ansi_p2],al
    jmp .done
.not_digit:
    cmp al,';'
    jne .not_sep
    mov byte [ansi_second],1
    jmp .done
.not_sep:
    cmp al,'?'
    jne .final
    mov byte [ansi_private],1
    jmp .done
.final:
    mov byte [ansi_state],0
    cmp byte [ansi_private],0
    jne .done                 ; CSI ?25h/l accepted as no-op
    cmp al,'A'
    je .up
    cmp al,'B'
    je .down
    cmp al,'C'
    je .right
    cmp al,'D'
    je .left
    cmp al,'E'
    je .nextn
    cmp al,'F'
    je .prevn
    cmp al,'H'
    je .position
    cmp al,'f'
    je .position
    cmp al,'G'
    je .column
    cmp al,'d'
    je .row
    cmp al,'J'
    je .erase_display
    cmp al,'K'
    je .erase_line
    cmp al,'X'
    je .erase_chars
    cmp al,'m'
    je .sgr
    cmp al,'s'
    je .save
    cmp al,'u'
    je .restore
    jmp .done
.up:
    mov dl,0x1e
    jmp .move
.down:
    mov dl,0x1f
    jmp .move
.right:
    mov dl,0x1c
    jmp .move
.left:
    mov dl,0x1d
.move:
    call ansi_count
.moveloop:
    mov al,dl
    call ansi_raw_tracked
    dec cl
    jnz .moveloop
    jmp .done
.nextn:
    mov dl,0x1f
    jmp .moveln
.prevn:
    mov dl,0x1e
.moveln:
    call ansi_count
.movelnloop:
    mov al,dl
    call ansi_raw_tracked
    dec cl
    jnz .movelnloop
    mov al,13
    call ansi_raw_tracked
    jmp .done
.position:
    mov al,[ansi_p1]
    or al,al
    jnz .pos_row
    mov al,1
.pos_row:
    mov ah,[ansi_p2]
    or ah,ah
    jnz .pos_col
    mov ah,1
.pos_col:
    call ansi_goto
    jmp .done
.column:
    mov al,[ansi_row]
    mov ah,[ansi_p1]
    call ansi_goto
    jmp .done
.row:
    mov al,[ansi_p1]
    mov ah,[ansi_col]
    call ansi_goto
    jmp .done
.erase_display:
    mov bl,[ansi_p1]
    cmp bl,2
    je .clear2
    cmp bl,1
    je .clear1
    mov al,ANSI_ESC
    call ansi_raw
    mov al,'Y'
    call ansi_raw
    jmp .done
.clear2:
    mov al,[ansi_row]
    mov [ansi_work_row],al
    mov al,[ansi_col]
    mov [ansi_work_col],al
    mov al,ANSI_ESC
    call ansi_raw
    mov al,'*'
    call ansi_raw
    mov al,[ansi_work_row]
    mov ah,[ansi_work_col]
    call ansi_goto
    jmp .done
.clear1:
    mov al,[ansi_row]
    mov [ansi_work_row],al
    mov al,[ansi_col]
    mov [ansi_work_col],al
    mov byte [ansi_iter],1
.clear1loop:
    mov al,[ansi_iter]
    cmp al,[ansi_work_row]
    jae .clear1current
    mov ah,1
    call ansi_goto
    mov al,ANSI_ESC
    call ansi_raw
    mov al,'T'
    call ansi_raw
    inc byte [ansi_iter]
    jmp .clear1loop
.clear1current:
    mov al,[ansi_work_row]
    mov ah,1
    call ansi_goto
    mov cl,[ansi_work_col]
    call ansi_spaces
    mov al,[ansi_work_row]
    mov ah,[ansi_work_col]
    call ansi_goto
    jmp .done
.erase_line:
    mov bl,[ansi_p1]
    cmp bl,2
    je .line_all
    cmp bl,1
    je .line_start
    call ansi_eol
    jmp .done
.line_all:
    mov al,[ansi_col]
    mov [ansi_work_col],al
    mov al,[ansi_row]
    mov ah,1
    call ansi_goto
    call ansi_eol
    mov al,[ansi_row]
    mov ah,[ansi_work_col]
    call ansi_goto
    jmp .done
.line_start:
    mov al,[ansi_col]
    mov [ansi_work_col],al
    mov al,[ansi_row]
    mov ah,1
    call ansi_goto
    mov cl,[ansi_work_col]
    call ansi_spaces
    mov al,[ansi_row]
    mov ah,[ansi_work_col]
    call ansi_goto
    jmp .done
.erase_chars:
    call ansi_count
    mov al,[ansi_col]
    mov [ansi_work_col],al
    call ansi_spaces
    mov al,[ansi_row]
    mov ah,[ansi_work_col]
    call ansi_goto
    jmp .done
.sgr:
    mov al,[ansi_p1]
    call ansi_sgr_param
    cmp byte [ansi_second],0
    je .sgr_finish
    mov al,[ansi_p2]
    call ansi_sgr_param
.sgr_finish:
    call ansi_apply_attr
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    ret

; Raw native output: no parser recursion.
ansi_raw:
    call local_native_putc
    ret

ansi_count:
    mov cl,[ansi_p1]
    or cl,cl
    jnz .ok
    mov cl,1
.ok:
    ret

; FM-11 native direct positioning: 12h, X-1, Y-1.
; Input AL=row, AH=col, both 1-based; clamped to 80x25.
ansi_goto:
    cmp al,1
    jae .minrow
    mov al,1
.minrow:
    cmp al,ANSI_ROWS
    jbe .maxrow
    mov al,ANSI_ROWS
.maxrow:
    cmp ah,1
    jae .mincol
    mov ah,1
.mincol:
    cmp ah,ANSI_COLS
    jbe .maxcol
    mov ah,ANSI_COLS
.maxcol:
    mov [ansi_row],al
    mov [ansi_col],ah
    mov al,0x12
    call ansi_raw
    mov al,[ansi_col]
    dec al
    call ansi_raw
    mov al,[ansi_row]
    dec al
    call ansi_raw
    ret

ansi_clear_home:
    mov al,0x16
    call ansi_raw
    mov al,0x0b
    call ansi_raw
    mov byte [ansi_row],1
    mov byte [ansi_col],1
    ret

ansi_eol:
    mov al,ANSI_ESC
    call ansi_raw
    mov al,'T'
    call ansi_raw
    ret

; CL=number of cells to blank, never move caller's cursor permanently.
ansi_spaces:
    mov bl,ANSI_COLS+1
    sub bl,[ansi_col]
    cmp cl,bl
    jbe .limited
    mov cl,bl
.limited:
    or cl,cl
    jz .end
.space:
    mov al,' '
    call ansi_raw
    inc byte [ansi_col]
    dec cl
    jnz .space
.end:
    ret

; Native control and ordinary printable character position tracking.
ansi_raw_tracked:
    mov dl,al
    call ansi_raw
    cmp dl,13
    je .cr
    cmp dl,10
    je .down
    cmp dl,8
    je .left
    cmp dl,0x1d
    je .left
    cmp dl,0x1c
    je .right
    cmp dl,0x1e
    je .up
    cmp dl,0x1f
    je .down
    cmp dl,0x0b
    je .home
    cmp dl,0x16
    je .home
    cmp dl,' '
    jb .end
    cmp byte [ansi_col],ANSI_COLS
    jb .inc_col
    mov byte [ansi_col],1
    cmp byte [ansi_row],ANSI_ROWS
    jae .end
    inc byte [ansi_row]
    jmp .end
.inc_col:
    inc byte [ansi_col]
    jmp .end
.cr:
    mov byte [ansi_col],1
    jmp .end
.down:
    cmp byte [ansi_row],ANSI_ROWS
    jae .end
    inc byte [ansi_row]
    jmp .end
.up:
    cmp byte [ansi_row],1
    jbe .end
    dec byte [ansi_row]
    jmp .end
.left:
    cmp byte [ansi_col],1
    jbe .end
    dec byte [ansi_col]
    jmp .end
.right:
    cmp byte [ansi_col],ANSI_COLS
    jae .end
    inc byte [ansi_col]
    jmp .end
.home:
    mov byte [ansi_row],1
    mov byte [ansi_col],1
.end:
    ret

; ANSI SGR subset matches NitrOS-9 fm11console.
ansi_sgr_param:
    cmp al,0
    jne .nonzero
    mov byte [ansi_attr],7
    ret
.nonzero:
    cmp al,1
    jne .not_bold
    or byte [ansi_attr],0x20
    ret
.not_bold:
    cmp al,5
    jne .not_blink
    or byte [ansi_attr],0x10
    ret
.not_blink:
    cmp al,7
    jne .not_reverse
    or byte [ansi_attr],8
    ret
.not_reverse:
    cmp al,22
    jne .not_boldoff
    and byte [ansi_attr],0xdf
    ret
.not_boldoff:
    cmp al,25
    jne .not_blinkoff
    and byte [ansi_attr],0xef
    ret
.not_blinkoff:
    cmp al,27
    jne .not_reverseoff
    and byte [ansi_attr],0xf7
    ret
.not_reverseoff:
    cmp al,39
    jne .color
    mov al,7
    jmp .setcolor
.color:
    cmp al,30
    jb .bright
    cmp al,37
    ja .bright
    sub al,30
    jmp .setcolor
.bright:
    cmp al,90
    jb .end
    cmp al,97
    ja .end
    sub al,90
    or byte [ansi_attr],0x20
.setcolor:
    xor ah,ah
    mov si,ansi_color_map
    add si,ax
    mov al,[si]
    and byte [ansi_attr],0xf8
    or [ansi_attr],al
.end:
    ret

ansi_apply_attr:
    mov al,ANSI_ESC
    call ansi_raw
    mov al,'G'
    call ansi_raw
    mov al,[ansi_attr]
    call ansi_raw
    ret

ansi_color_map db 0,2,4,6,1,3,5,7
ansi_state db 0
ansi_second db 0
ansi_private db 0
ansi_p1 db 0
ansi_p2 db 0
ansi_row db 1
ansi_col db 1
ansi_save_row db 1
ansi_save_col db 1
ansi_work_row db 1
ansi_work_col db 1
ansi_iter db 1
ansi_attr db 7
