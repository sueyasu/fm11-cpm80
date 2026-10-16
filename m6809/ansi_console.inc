********************************************************************
* ANSI/VT100 parser for the FM-11 local console.
*
* Ported from fm11-nitros9 level2/fm11/modules/fm11console.asm.
* LocalPutC must send one native byte to the Display Sub System.
*
* Supported output sequences:
*   ESC [ n A/B/C/D/E/F   cursor relative movement
*   ESC [ row ; col H/f   cursor position
*   ESC [ n G / ESC [ n d absolute column / row
*   ESC [ n J/K/X         erase display / line / characters
*   ESC [ ... m           SGR: bold, blink, reverse, 8 colors, bright
*   ESC [ s / ESC [ u     save / restore cursor
*   ESC 7 / ESC 8         VT100 save / restore cursor
*   ESC c                 reset (clear + home)
*   ESC D/M/E             index / reverse index / next line
*   ESC [ ? 25 h/l        cursor visibility accepted as no-op
*   ESC T/Y/*             FM-11 native erase controls passed through
********************************************************************

ANSI_ESC        equ     $1B
ANSI_NORMAL     equ     0
ANSI_ESCSTATE   equ     1
ANSI_CSI        equ     2
SCR_COLS        equ     80
SCR_ROWS        equ     25

C_BSP           equ     $08
C_LF            equ     $0A
C_HOME          equ     $0B
C_FORM          equ     $0C
C_CR            equ     $0D
C_CLSALL        equ     $16
C_RGT           equ     $1C
C_LFT           equ     $1D
C_UP            equ     $1E
C_DWN           equ     $1F
C_SPACE         equ     $20

AnsiPutC
        ldb     AnsiState
        beq     APNormal
        cmpb    #ANSI_ESCSTATE
        beq     APEsc
        lbra    APCsi

APNormal
        cmpa    #ANSI_ESC
        bne     APOrdinary
        lda     #ANSI_ESCSTATE
        sta     AnsiState
        andcc   #$FE
        rts

APOrdinary
        lbsr    RawPutCTracked
        rts

APEscapeReset
        clr     AnsiState
        andcc   #$FE
        rts

APEsc
        cmpa    #'[
        beq     APStartCsi
        cmpa    #'7
        beq     APSave
        cmpa    #'8
        beq     APRestore
        cmpa    #'c
        beq     APResetTerm
        cmpa    #'D
        beq     APIndex
        cmpa    #'M
        beq     APReverseIndex
        cmpa    #'E
        beq     APNextLine
        cmpa    #'T
        beq     APNativeEsc
        cmpa    #'Y
        beq     APNativeEsc
        cmpa    #'*
        beq     APNativeEsc
        bra     APEscapeReset

APNativeEsc
        pshs    a
        lda     #ANSI_ESC
        lbsr    LocalPutC
        puls    a
        lbsr    LocalPutC
        clr     AnsiState
        andcc   #$FE
        rts

APStartCsi
        lda     #ANSI_CSI
        sta     AnsiState
        clr     AnsiParam
        clr     AnsiPrivate
        clr     AnsiP1
        clr     AnsiP2
        andcc   #$FE
        rts

APSave
        lda     CurRow
        sta     SaveRow
        lda     CurCol
        sta     SaveCol
        bra     APEscapeReset

APRestore
        lda     SaveRow
        ldb     SaveCol
        lbsr    AnsiGoto
        clr     AnsiState
        rts

APResetTerm
        lbsr    AnsiClearHome
        clr     AnsiState
        rts

APIndex
        lda     #C_DWN
        lbsr    RawPutCTracked
        clr     AnsiState
        rts

APReverseIndex
        lda     #C_UP
        lbsr    RawPutCTracked
        clr     AnsiState
        rts

APNextLine
        lda     #C_DWN
        lbsr    RawPutCTracked
        lda     #C_CR
        lbsr    RawPutCTracked
        clr     AnsiState
        rts

APCsi
        cmpa    #'0
        blo     APCsiNotDigit
        cmpa    #'9
        bhi     APCsiNotDigit
        suba    #'0
        pshs    a
        tst     AnsiParam
        bne     APCsiDigit2
        lda     #10
        ldb     AnsiP1
        mul
        addb    ,s+
        stb     AnsiP1
        andcc   #$FE
        rts
APCsiDigit2
        lda     #10
        ldb     AnsiP2
        mul
        addb    ,s+
        stb     AnsiP2
        andcc   #$FE
        rts

APCsiNotDigit
        cmpa    #';
        bne     APCsiPrivate
        lda     #1
        sta     AnsiParam
        andcc   #$FE
        rts

APCsiPrivate
        cmpa    #'?
        bne     APCsiFinal
        lda     #1
        sta     AnsiPrivate
        andcc   #$FE
        rts

APCsiFinal
        pshs    a
        clr     AnsiState
        puls    a
        cmpa    #'A
        lbeq    APCursorUp
        cmpa    #'B
        lbeq    APCursorDown
        cmpa    #'C
        lbeq    APCursorRight
        cmpa    #'D
        lbeq    APCursorLeft
        cmpa    #'E
        lbeq    APCursorNextLine
        cmpa    #'F
        lbeq    APCursorPrevLine
        cmpa    #'H
        lbeq    APCursorPos
        cmpa    #'f
        lbeq    APCursorPos
        cmpa    #'G
        lbeq    APAbsCol
        cmpa    #'d
        lbeq    APAbsRow
        cmpa    #'J
        lbeq    APEraseDisplay
        cmpa    #'K
        lbeq    APEraseLine
        cmpa    #'X
        lbeq    APEraseChars
        cmpa    #'m
        lbeq    APSgr
        cmpa    #'s
        lbeq    APCsiSave
        cmpa    #'u
        lbeq    APCsiRestore
        cmpa    #'h
        lbeq    APCsiMode
        cmpa    #'l
        lbeq    APCsiMode
        andcc   #$FE
        rts

APGetCount
        ldb     AnsiP1
        bne     APCountOk
        ldb     #1
APCountOk
        rts

APCursorUp
        lbsr    APGetCount
APCUlp
        cmpb    #0
        beq     APCUDone
        lda     #C_UP
        lbsr    RawPutCTracked
        decb
        bra     APCUlp
APCUDone
        andcc   #$FE
        rts

APCursorDown
        lbsr    APGetCount
APCDlp
        cmpb    #0
        beq     APCUDone
        lda     #C_DWN
        lbsr    RawPutCTracked
        decb
        bra     APCDlp

APCursorRight
        lbsr    APGetCount
APCRlp
        cmpb    #0
        beq     APCUDone
        lda     #C_RGT
        lbsr    RawPutCTracked
        decb
        bra     APCRlp

APCursorLeft
        lbsr    APGetCount
APCLlp
        cmpb    #0
        beq     APCUDone
        lda     #C_LFT
        lbsr    RawPutCTracked
        decb
        bra     APCLlp

APCursorNextLine
        lbsr    APGetCount
APCNLoop
        cmpb    #0
        beq     APCNCR
        lda     #C_DWN
        lbsr    RawPutCTracked
        decb
        bra     APCNLoop
APCNCR
        lda     #C_CR
        lbsr    RawPutCTracked
        rts

APCursorPrevLine
        lbsr    APGetCount
APCPLoop
        cmpb    #0
        beq     APCPCR
        lda     #C_UP
        lbsr    RawPutCTracked
        decb
        bra     APCPLoop
APCPCR
        lda     #C_CR
        lbsr    RawPutCTracked
        rts

APCursorPos
        lda     AnsiP1
        bne     APCPRowOk
        lda     #1
APCPRowOk
        ldb     AnsiP2
        bne     APCPColOk
        ldb     #1
APCPColOk
        lbsr    AnsiGoto
        rts

APAbsCol
        lda     CurRow
        ldb     AnsiP1
        bne     APACOk
        ldb     #1
APACOk
        lbsr    AnsiGoto
        rts

APAbsRow
        lda     AnsiP1
        bne     APAROk
        lda     #1
APAROk
        ldb     CurCol
        lbsr    AnsiGoto
        rts

APEraseDisplay
        ldb     AnsiP1
        cmpb    #2
        beq     APEDAll
        cmpb    #1
        beq     APEDStart
        lbsr    AnsiEraseToEnd
        rts
APEDStart
        lbsr    AnsiEraseFromStart
        rts
APEDAll
        lda     CurRow
        sta     WorkRow
        lda     CurCol
        sta     WorkCol
        lbsr    NativeEraseAll
        lda     WorkRow
        ldb     WorkCol
        lbsr    AnsiGoto
        rts

APEraseLine
        ldb     AnsiP1
        lbsr    AnsiEraseLine
        rts

APEraseChars
        lbsr    APGetCount
        lbsr    AnsiEraseChars
        rts

APSgr
        lda     AnsiP1
        lbsr    ApplySgrParam
        tst     AnsiParam
        beq     APSgrApply
        lda     AnsiP2
        lbsr    ApplySgrParam
APSgrApply
        lbsr    ApplyNativeAttr
        andcc   #$FE
        rts

ApplySgrParam
        cmpa    #0
        beq     ASPReset
        cmpa    #1
        beq     ASPBold
        cmpa    #5
        beq     ASPBlink
        cmpa    #7
        beq     ASPReverse
        cmpa    #22
        beq     ASPBoldOff
        cmpa    #25
        beq     ASPBlinkOff
        cmpa    #27
        beq     ASPReverseOff
        cmpa    #39
        beq     ASPDefaultColor
        cmpa    #30
        blo     ASPBrightCheck
        cmpa    #37
        bhi     ASPBrightCheck
        suba    #30
        lbsr    ASPSetColor
        rts
ASPBrightCheck
        cmpa    #90
        blo     ASPDone
        cmpa    #97
        bhi     ASPDone
        suba    #90
        lbsr    ASPSetColor
        ldb     NativeAttr
        orb     #$20
        stb     NativeAttr
ASPDone
        rts

ASPReset
        lda     #$07
        sta     NativeAttr
        rts
ASPBold
        ldb     NativeAttr
        orb     #$20
        stb     NativeAttr
        rts
ASPBlink
        ldb     NativeAttr
        orb     #$10
        stb     NativeAttr
        rts
ASPReverse
        ldb     NativeAttr
        orb     #$08
        stb     NativeAttr
        rts
ASPBoldOff
        ldb     NativeAttr
        andb    #$DF
        stb     NativeAttr
        rts
ASPBlinkOff
        ldb     NativeAttr
        andb    #$EF
        stb     NativeAttr
        rts
ASPReverseOff
        ldb     NativeAttr
        andb    #$F7
        stb     NativeAttr
        rts
ASPDefaultColor
        lda     #7
        lbsr    ASPSetColor
        rts

ASPSetColor
        ldx     #AnsiColorMap
        lda     a,x
        pshs    a
        ldb     NativeAttr
        andb    #$F8
        orb     ,s+
        stb     NativeAttr
        rts

ApplyNativeAttr
        lda     #ANSI_ESC
        lbsr    LocalPutC
        lda     #'G
        lbsr    LocalPutC
        lda     NativeAttr
        lbsr    LocalPutC
        rts

AnsiColorMap
        fcb     0,2,4,6,1,3,5,7

APCsiSave
        lda     CurRow
        sta     SaveRow
        lda     CurCol
        sta     SaveCol
        andcc   #$FE
        rts

APCsiRestore
        lda     SaveRow
        ldb     SaveCol
        lbsr    AnsiGoto
        rts

* NitrOS-9 accepts CSI ? 25 h/l as a no-op because cursor visibility is not
* directly controllable through the FM-11 native interface.  Keep the same
* behavior here; unknown h/l mode requests are harmlessly ignored as well.
APCsiMode
        andcc   #$FE
        rts

AnsiGoto
        cmpa    #1
        bhs     AGRowLowOk
        lda     #1
AGRowLowOk
        cmpa    #SCR_ROWS
        bls     AGRowOk
        lda     #SCR_ROWS
AGRowOk
        cmpb    #1
        bhs     AGColLowOk
        ldb     #1
AGColLowOk
        cmpb    #SCR_COLS
        bls     AGColOk
        ldb     #SCR_COLS
AGColOk
        sta     TmpRow
        stb     TmpCol
        lda     #$12
        lbsr    LocalPutC
        lda     TmpCol
        deca
        lbsr    LocalPutC
        lda     TmpRow
        deca
        lbsr    LocalPutC
        lda     TmpRow
        sta     CurRow
        lda     TmpCol
        sta     CurCol
        andcc   #$FE
        rts

AnsiClearHome
        lda     #C_CLSALL
        lbsr    LocalPutC
        lda     #C_HOME
        lbsr    LocalPutC
        lda     #1
        sta     CurRow
        sta     CurCol
        andcc   #$FE
        rts

AnsiEraseLine
        lda     CurRow
        sta     LineRow
        lda     CurCol
        sta     LineCol
        cmpb    #1
        beq     AELStart
        cmpb    #2
        beq     AELAll
        lbsr    NativeEraseEOL
        rts
AELStart
        lda     LineRow
        ldb     #1
        lbsr    AnsiGoto
        ldb     LineCol
        lbsr    EraseCells
        bra     AELRestore
AELAll
        lda     LineRow
        ldb     #1
        lbsr    AnsiGoto
        lbsr    NativeEraseEOL
AELRestore
        lda     LineRow
        ldb     LineCol
        lbsr    AnsiGoto
        rts

AnsiEraseChars
        lda     CurRow
        sta     LineRow
        lda     CurCol
        sta     LineCol
        lbsr    EraseCells
        lda     LineRow
        ldb     LineCol
        lbsr    AnsiGoto
        rts

EraseCells
        cmpb    #0
        beq     ECDone
        lda     #SCR_COLS+1
        suba    CurCol
        sta     TmpCol
        cmpb    TmpCol
        bhs     ECToEOL
ECSpaces
        cmpb    #0
        beq     ECDone
        pshs    b
        lda     #C_SPACE
        lbsr    LocalPutC
        puls    b
        decb
        bra     ECSpaces
ECToEOL
        lbsr    NativeEraseEOL
ECDone
        rts

AnsiEraseToEnd
        lbsr    NativeEraseEOS
        rts

AnsiEraseFromStart
        lda     CurRow
        sta     WorkRow
        lda     CurCol
        sta     WorkCol
        lda     #1
AEFSRow
        cmpa    WorkRow
        bhs     AEFSCurrent
        sta     TmpRow
        ldb     #1
        lbsr    AnsiGoto
        ldb     #2
        lbsr    AnsiEraseLine
        lda     TmpRow
        inca
        bra     AEFSRow
AEFSCurrent
        lda     WorkRow
        ldb     WorkCol
        lbsr    AnsiGoto
        ldb     #1
        lbsr    AnsiEraseLine
        lda     WorkRow
        ldb     WorkCol
        lbsr    AnsiGoto
        rts

NativeEraseEOL
        lda     #ANSI_ESC
        lbsr    LocalPutC
        lda     #'T
        lbsr    LocalPutC
        rts

NativeEraseEOS
        lda     #ANSI_ESC
        lbsr    LocalPutC
        lda     #'Y
        lbsr    LocalPutC
        rts

NativeEraseAll
        lda     #ANSI_ESC
        lbsr    LocalPutC
        lda     #'*
        lbsr    LocalPutC
        rts

RawPutCTracked
        pshs    a
        lbsr    LocalPutC
        puls    a
        cmpa    #C_CR
        beq     RPCR
        cmpa    #C_LF
        beq     RPLF
        cmpa    #C_BSP
        beq     RPLeft
        cmpa    #C_LFT
        beq     RPLeft
        cmpa    #C_RGT
        beq     RPRight
        cmpa    #C_UP
        beq     RPUp
        cmpa    #C_DWN
        beq     RPDown
        cmpa    #C_HOME
        beq     RPHome
        cmpa    #C_CLSALL
        beq     RPHome
        cmpa    #C_FORM
        beq     RPHome
        cmpa    #C_SPACE
        blo     RPDone
        lda     CurCol
        cmpa    #SCR_COLS
        blo     RPIncCol
        lda     #1
        sta     CurCol
        lda     CurRow
        cmpa    #SCR_ROWS
        bhs     RPDone
        inca
        sta     CurRow
        bra     RPDone
RPIncCol
        inca
        sta     CurCol
        bra     RPDone
RPCR
        lda     #1
        sta     CurCol
        bra     RPDone
RPLF
        lda     CurRow
        cmpa    #SCR_ROWS
        bhs     RPDone
        inca
        sta     CurRow
        bra     RPDone
RPLeft
        lda     CurCol
        cmpa    #1
        bls     RPDone
        deca
        sta     CurCol
        bra     RPDone
RPRight
        lda     CurCol
        cmpa    #SCR_COLS
        bhs     RPDone
        inca
        sta     CurCol
        bra     RPDone
RPUp
        lda     CurRow
        cmpa    #1
        bls     RPDone
        deca
        sta     CurRow
        bra     RPDone
RPDown
        lda     CurRow
        cmpa    #SCR_ROWS
        bhs     RPDone
        inca
        sta     CurRow
        bra     RPDone
RPHome
        lda     #1
        sta     CurRow
        sta     CurCol
RPDone
        andcc   #$FE
        rts
