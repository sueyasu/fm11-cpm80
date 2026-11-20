; Shared FM-11 ANSI/VT100 to CHARACTER OUT translator (8086).
; Behavioral reference: fm11-cpm80 m6809/ansi_console.inc at 93bfb04.
; Keep this file byte-identical in CP/M-80 and CP/M-86.
; Public entry ansi_putc: AL=character, DS=resident data.
; Preserves all general/segment registers and flags except CF.
; CF=1 on native output failure, CF=0 otherwise.
; local_native_putc must preserve registers and return CF for transport.
; All other ansi_* routines are private to ansi_putc.
ANSI_ESC equ 27
ANSI_COLS equ 80
ANSI_ROWS equ 25
ANSI_MAX_PARAMS equ 8

ansi_putc:
    pushf
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    mov bp,sp             ; private frame for aborting a failed output
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
    xor ax,ax
    mov [ansi_p1],ax
    mov [ansi_p1+2],ax
    mov [ansi_p1+4],ax
    mov [ansi_p1+6],ax
    mov [ansi_param],al
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
    mov byte [ansi_attr],7
    call ansi_apply_attr
    call ansi_clear_home
    mov word [ansi_save_row],0x0101
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
    xor bh,bh
    mov bl,[ansi_param]
    cmp bl,ANSI_MAX_PARAMS
    jae .done
    mov dl,al
    xor dh,dh
    mov al,[ansi_p1+bx]
    mov cl,10
    mul cl
    add ax,dx
    or ah,ah
    jz .store_digit
    mov al,255
.store_digit:
    mov [ansi_p1+bx],al
    jmp .done
.not_digit:
    cmp al,';'
    jne .not_sep
    cmp byte [ansi_param],ANSI_MAX_PARAMS
    jae .done
    inc byte [ansi_param]
    jmp .done
.not_sep:
    cmp al,'?'
    jne .final
    mov byte [ansi_private],1
    jmp .done
.final:
    cmp al,0x40
    jb .done               ; ignore intermediate bytes, retain CSI state
    mov byte [ansi_state],0
    cmp al,0x7e
    ja .done
    cmp byte [ansi_param],ANSI_MAX_PARAMS
    jae .done              ; reject the entire overlong sequence
    cmp byte [ansi_private],0
    jne .done              ; CSI ?25h/l accepted as no-op
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
    mov ax,[ansi_p1]
    jmp .goto_done
.column:
    mov al,[ansi_row]
    mov ah,[ansi_p1]
    jmp .goto_done
.row:
    mov al,[ansi_p1]
    mov ah,[ansi_col]
.goto_done:
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
    mov di,ansi_p1
    xor ch,ch
    mov cl,[ansi_param]
    inc cx
.sgr_loop:
    mov al,[di]
    inc di
    call ansi_sgr_param
    loop .sgr_loop
    call ansi_apply_attr
.done:
    and word [bp+14],0xfffe ; saved FLAGS (7 saved registers)
    jmp short .restore_frame
.failed:
    ; BP is the saved-register frame established by ansi_putc.
    ; Discard only private helper return addresses. No helper changes
    ; BP/SS or owns resources outside this frame. The transport has
    ; already returned and restored its own registers before we get here.
    mov sp,bp
    mov byte [ansi_state],0
    or word [bp+14],1     ; report the failure in the saved CF
.restore_frame:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    ret

; Raw native output: private to ansi_putc; no parser recursion.
ansi_raw:
    call local_native_putc
    jc ansi_putc.failed
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
    mov bx,ax
    mov al,0x12
    call ansi_raw
    mov al,bh
    dec al
    call ansi_raw
    mov al,bl
    dec al
    call ansi_raw
    mov [ansi_row],bx       ; commit tracked row/column only on success
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
    jmp ansi_raw

; CL=number of cells to blank, never move caller's cursor permanently.
ansi_spaces:
    mov bl,ANSI_COLS+1
    sub bl,[ansi_col]
    or cl,cl
    jz .end
    cmp cl,bl
    jae ansi_eol           ; avoid wrap/scroll at the right margin
.space:
    mov al,' '
    call ansi_raw
    dec cl
    jnz .space
.end:
    ret

; Native control and ordinary printable character position tracking.
ansi_raw_tracked:
    mov dl,al
    call ansi_raw
    cmp dl,9
    je .tab
    cmp dl,12
    je .home
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
.tab:
    mov al,[ansi_col]
    dec al
    and al,0xf8
    add al,9
    cmp al,ANSI_COLS
    jbe .tab_store
    mov al,ANSI_COLS
.tab_store:
    mov [ansi_col],al
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
    jmp ansi_raw

ansi_color_map db 0,2,4,6,1,3,5,7
ansi_state db 0
ansi_param db 0
ansi_private db 0
ansi_p1 db 0
ansi_p2 db 0
    times ANSI_MAX_PARAMS-2 db 0
ansi_row db 1
ansi_col db 1
ansi_save_row db 1
ansi_save_col db 1
ansi_work_row db 1
ansi_work_col db 1
ansi_iter db 1
ansi_attr db 7
