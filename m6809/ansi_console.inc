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
ANSI_MAX_PARAMS equ     8
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
        lbeq     APNormal
        cmpb    #ANSI_ESCSTATE
        lbeq     APEsc
        lbra    APCsi

APNormal
        cmpa    #ANSI_ESC
        lbne     APOrdinary
        lda     #ANSI_ESCSTATE
        sta     AnsiState
        andcc   #$FE
        rts

APOrdinary
        lbsr    RawPutCTracked
        lbcs    AnsiReturnError
        rts

APEscapeReset
        clr     AnsiState
        andcc   #$FE
        rts

APEsc
        cmpa    #'[
        lbeq     APStartCsi
        cmpa    #'7
        lbeq     APSave
        cmpa    #'8
        lbeq     APRestore
        cmpa    #'c
        lbeq     APResetTerm
        cmpa    #'D
        lbeq     APIndex
        cmpa    #'M
        lbeq     APReverseIndex
        cmpa    #'E
        lbeq     APNextLine
        cmpa    #'T
        lbeq     APNativeEsc
        cmpa    #'Y
        lbeq     APNativeEsc
        cmpa    #'*
        lbeq     APNativeEsc
        lbra     APEscapeReset

APNativeEsc
        pshs    a
        lda     #ANSI_ESC
        lbsr    LocalPutC
        puls    a
        lbcs    AnsiReturnError
        lbsr    LocalPutC
        lbcs    AnsiReturnError
        clr     AnsiState
        andcc   #$FE
        rts

APStartCsi
        lda     #ANSI_CSI
        sta     AnsiState
        clr     AnsiParam
        clr     AnsiPrivate
        ldx     #AnsiP1
        ldb     #ANSI_MAX_PARAMS
APClearParams
        clr     ,x+
        decb
        lbne     APClearParams
        andcc   #$FE
        rts

APSave
        lda     CurRow
        sta     SaveRow
        lda     CurCol
        sta     SaveCol
        lbra     APEscapeReset

APRestore
        lda     SaveRow
        ldb     SaveCol
        lbsr    AnsiGoto
        lbcs    AnsiReturnError
        clr     AnsiState
        rts

APResetTerm
        clr     AnsiState
        lda     #7
        sta     NativeAttr
        lbsr    ApplyNativeAttr
        lbcs    AnsiReturnError
        lbsr    AnsiClearHome
        lbcs    AnsiReturnError
        lda     #1
        sta     SaveRow
        sta     SaveCol
        andcc   #$FE
        rts

APIndex
        lda     #C_DWN
        lbsr    RawPutCTracked
        lbcs    AnsiReturnError
        clr     AnsiState
        rts

APReverseIndex
        lda     #C_UP
        lbsr    RawPutCTracked
        lbcs    AnsiReturnError
        clr     AnsiState
        rts

APNextLine
        lda     #C_DWN
        lbsr    RawPutCTracked
        lbcs    AnsiReturnError
        lda     #C_CR
        lbsr    RawPutCTracked
        lbcs    AnsiReturnError
        clr     AnsiState
        rts

APCsi
        cmpa    #'0
        lblo     APCsiNotDigit
        cmpa    #'9
        lbhi     APCsiNotDigit
        ldb     AnsiParam
        cmpb    #ANSI_MAX_PARAMS
        lbhs     APCsiIgnore
        suba    #'0
        pshs    a
        ldx     #AnsiP1
        abx
        lda     #10
        ldb     ,x
        mul
        addb    ,s+
        adca    #0
        tsta
        lbeq     APCsiStore
        ldb     #255
APCsiStore
        stb     ,x
APCsiIgnore
        andcc   #$FE
        rts

APCsiNotDigit
        cmpa    #';
        lbne     APCsiPrivate
        lda     AnsiParam
        cmpa    #ANSI_MAX_PARAMS
        lbhs     APCsiIgnore
        inc     AnsiParam
        lbra     APCsiIgnore
APCsiPrivate
        cmpa    #'?
        lbne     APCsiDispatch
        inc     AnsiPrivate
        lbra     APCsiIgnore
APCsiDispatch
        cmpa    #$40
        lblo     APCsiIgnore
        cmpa    #$7E
        lbhi    APEscapeReset
        ldb     AnsiParam
        cmpb    #ANSI_MAX_PARAMS
        lbhs    APEscapeReset
        tst     AnsiPrivate
        lbne    APEscapeReset

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
        lbne     APCountOk
        ldb     #1
APCountOk
        rts

APCursorUp
        lbsr    APGetCount
APCUlp
        cmpb    #0
        lbeq     APCUDone
        lda     #C_UP
        lbsr    RawPutCTracked
        lbcs    AnsiReturnError
        decb
        lbra     APCUlp
APCUDone
        andcc   #$FE
        rts

APCursorDown
        lbsr    APGetCount
APCDlp
        cmpb    #0
        lbeq     APCUDone
        lda     #C_DWN
        lbsr    RawPutCTracked
        lbcs    AnsiReturnError
        decb
        lbra     APCDlp

APCursorRight
        lbsr    APGetCount
APCRlp
        cmpb    #0
        lbeq     APCUDone
        lda     #C_RGT
        lbsr    RawPutCTracked
        lbcs    AnsiReturnError
        decb
        lbra     APCRlp

APCursorLeft
        lbsr    APGetCount
APCLlp
        cmpb    #0
        lbeq     APCUDone
        lda     #C_LFT
        lbsr    RawPutCTracked
        lbcs    AnsiReturnError
        decb
        lbra     APCLlp

APCursorNextLine
        lbsr    APGetCount
APCNLoop
        cmpb    #0
        lbeq     APCNCR
        lda     #C_DWN
        lbsr    RawPutCTracked
        lbcs    AnsiReturnError
        decb
        lbra     APCNLoop
APCNCR
        lda     #C_CR
        lbsr    RawPutCTracked
        lbcs    AnsiReturnError
        rts

APCursorPrevLine
        lbsr    APGetCount
APCPLoop
        cmpb    #0
        lbeq     APCPCR
        lda     #C_UP
        lbsr    RawPutCTracked
        lbcs    AnsiReturnError
        decb
        lbra     APCPLoop
APCPCR
        lda     #C_CR
        lbsr    RawPutCTracked
        lbcs    AnsiReturnError
        rts

APCursorPos
        lda     AnsiP1
        lbne     APCPRowOk
        lda     #1
APCPRowOk
        ldb     AnsiP2
        lbne     APCPColOk
        ldb     #1
APCPColOk
        lbsr    AnsiGoto
        lbcs    AnsiReturnError
        rts

APAbsCol
        lda     CurRow
        ldb     AnsiP1
        lbne     APACOk
        ldb     #1
APACOk
        lbsr    AnsiGoto
        lbcs    AnsiReturnError
        rts

APAbsRow
        lda     AnsiP1
        lbne     APAROk
        lda     #1
APAROk
        ldb     CurCol
        lbsr    AnsiGoto
        lbcs    AnsiReturnError
        rts

APEraseDisplay
        ldb     AnsiP1
        cmpb    #2
        lbeq     APEDAll
        cmpb    #1
        lbeq     APEDStart
        lbsr    AnsiEraseToEnd
        lbcs    AnsiReturnError
        rts
APEDStart
        lbsr    AnsiEraseFromStart
        lbcs    AnsiReturnError
        rts
APEDAll
        lda     CurRow
        sta     WorkRow
        lda     CurCol
        sta     WorkCol
        lbsr    NativeEraseAll
        lbcs    AnsiReturnError
        lda     WorkRow
        ldb     WorkCol
        lbsr    AnsiGoto
        lbcs    AnsiReturnError
        rts

APEraseLine
        ldb     AnsiP1
        lbsr    AnsiEraseLine
        lbcs    AnsiReturnError
        rts

APEraseChars
        lbsr    APGetCount
        lbsr    AnsiEraseChars
        lbcs    AnsiReturnError
        rts

APSgr
        ldy     #AnsiP1
        ldb     AnsiParam
        incb
        pshs    b
APSgrNext
        lda     ,y+
        lbsr    ApplySgrParam
        dec     ,s
        lbne     APSgrNext
        leas    1,s
        lbra    ApplyNativeAttr

ApplySgrParam
        cmpa    #0
        lbeq     ASPReset
        cmpa    #1
        lbeq     ASPBold
        cmpa    #5
        lbeq     ASPBlink
        cmpa    #7
        lbeq     ASPReverse
        cmpa    #22
        lbeq     ASPBoldOff
        cmpa    #25
        lbeq     ASPBlinkOff
        cmpa    #27
        lbeq     ASPReverseOff
        cmpa    #39
        lbeq     ASPDefaultColor
        cmpa    #30
        lblo     ASPBrightCheck
        cmpa    #37
        lbhi     ASPBrightCheck
        suba    #30
        lbsr    ASPSetColor
        rts
ASPBrightCheck
        cmpa    #90
        lblo     ASPDone
        cmpa    #97
        lbhi     ASPDone
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
        lbcs    AnsiReturnError
        lda     #'G
        lbsr    LocalPutC
        lbcs    AnsiReturnError
        lda     NativeAttr
        lbsr    LocalPutC
        lbcs    AnsiReturnError
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
        lbcs    AnsiReturnError
        rts

* NitrOS-9 accepts CSI ? 25 h/l as a no-op because cursor visibility is not
* directly controllable through the FM-11 native interface.  Keep the same
* behavior here; unknown h/l mode requests are harmlessly ignored as well.
APCsiMode
        andcc   #$FE
        rts

AnsiGoto
        cmpa    #1
        lbhs     AGRowLowOk
        lda     #1
AGRowLowOk
        cmpa    #SCR_ROWS
        lbls     AGRowOk
        lda     #SCR_ROWS
AGRowOk
        cmpb    #1
        lbhs     AGColLowOk
        ldb     #1
AGColLowOk
        cmpb    #SCR_COLS
        lbls     AGColOk
        ldb     #SCR_COLS
AGColOk
        sta     TmpRow
        stb     TmpCol
        lda     #$12
        lbsr    LocalPutC
        lbcs    AnsiReturnError
        lda     TmpCol
        deca
        lbsr    LocalPutC
        lbcs    AnsiReturnError
        lda     TmpRow
        deca
        lbsr    LocalPutC
        lbcs    AnsiReturnError
        lda     TmpRow
        sta     CurRow
        lda     TmpCol
        sta     CurCol
        andcc   #$FE
        rts

AnsiClearHome
        lda     #C_CLSALL
        lbsr    LocalPutC
        lbcs    AnsiReturnError
        lda     #C_HOME
        lbsr    LocalPutC
        lbcs    AnsiReturnError
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
        lbeq     AELStart
        cmpb    #2
        lbeq     AELAll
        lbsr    NativeEraseEOL
        lbcs    AnsiReturnError
        rts
AELStart
        lda     LineRow
        ldb     #1
        lbsr    AnsiGoto
        lbcs    AnsiReturnError
        ldb     LineCol
        lbsr    EraseCells
        lbcs    AnsiReturnError
        lbra     AELRestore
AELAll
        lda     LineRow
        ldb     #1
        lbsr    AnsiGoto
        lbcs    AnsiReturnError
        lbsr    NativeEraseEOL
        lbcs    AnsiReturnError
AELRestore
        lda     LineRow
        ldb     LineCol
        lbsr    AnsiGoto
        lbcs    AnsiReturnError
        rts

AnsiEraseChars
        lda     CurRow
        sta     LineRow
        lda     CurCol
        sta     LineCol
        lbsr    EraseCells
        lbcs    AnsiReturnError
        lda     LineRow
        ldb     LineCol
        lbsr    AnsiGoto
        lbcs    AnsiReturnError
        rts

EraseCells
        cmpb    #0
        lbeq     ECDone
        lda     #SCR_COLS+1
        suba    CurCol
        sta     TmpCol
        cmpb    TmpCol
        lbhs     ECToEOL
ECSpaces
        cmpb    #0
        lbeq     ECDone
        pshs    b
        lda     #C_SPACE
        lbsr    LocalPutC
        puls    b
        lbcs    AnsiReturnError
        decb
        lbra     ECSpaces
ECToEOL
        lbsr    NativeEraseEOL
        lbcs    AnsiReturnError
ECDone
        rts

AnsiEraseToEnd
        lbsr    NativeEraseEOS
        lbcs    AnsiReturnError
        rts

AnsiEraseFromStart
        lda     CurRow
        sta     WorkRow
        lda     CurCol
        sta     WorkCol
        lda     #1
AEFSRow
        cmpa    WorkRow
        lbhs     AEFSCurrent
        sta     TmpRow
        ldb     #1
        lbsr    AnsiGoto
        lbcs    AnsiReturnError
        ldb     #2
        lbsr    AnsiEraseLine
        lbcs    AnsiReturnError
        lda     TmpRow
        inca
        lbra     AEFSRow
AEFSCurrent
        lda     WorkRow
        ldb     WorkCol
        lbsr    AnsiGoto
        lbcs    AnsiReturnError
        ldb     #1
        lbsr    AnsiEraseLine
        lbcs    AnsiReturnError
        lda     WorkRow
        ldb     WorkCol
        lbsr    AnsiGoto
        lbcs    AnsiReturnError
        rts

NativeEraseEOL
        lda     #ANSI_ESC
        lbsr    LocalPutC
        lbcs    AnsiReturnError
        lda     #'T
        lbsr    LocalPutC
        lbcs    AnsiReturnError
        rts

NativeEraseEOS
        lda     #ANSI_ESC
        lbsr    LocalPutC
        lbcs    AnsiReturnError
        lda     #'Y
        lbsr    LocalPutC
        lbcs    AnsiReturnError
        rts

NativeEraseAll
        lda     #ANSI_ESC
        lbsr    LocalPutC
        lbcs    AnsiReturnError
        lda     #'*
        lbsr    LocalPutC
        lbcs    AnsiReturnError
        rts

RawPutCTracked
        pshs    a
        lbsr    LocalPutC
        puls    a
        lbcs    AnsiReturnError
        cmpa    #$09
        lbeq     RPTab
        cmpa    #C_CR
        lbeq     RPCR
        cmpa    #C_LF
        lbeq     RPLF
        cmpa    #C_BSP
        lbeq     RPLeft
        cmpa    #C_LFT
        lbeq     RPLeft
        cmpa    #C_RGT
        lbeq     RPRight
        cmpa    #C_UP
        lbeq     RPUp
        cmpa    #C_DWN
        lbeq     RPDown
        cmpa    #C_HOME
        lbeq     RPHome
        cmpa    #C_CLSALL
        lbeq     RPHome
        cmpa    #C_FORM
        lbeq     RPHome
        cmpa    #C_SPACE
        lblo     RPDone
        lda     CurCol
        cmpa    #SCR_COLS
        lblo     RPIncCol
        lda     #1
        sta     CurCol
        lda     CurRow
        cmpa    #SCR_ROWS
        lbhs     RPDone
        inca
        sta     CurRow
        lbra     RPDone
RPIncCol
        inca
        sta     CurCol
        lbra     RPDone
RPTab
        lda     CurCol
        deca
        anda    #$F8
        adda    #9
        cmpa    #SCR_COLS
        lbls     RPTabStore
        lda     #SCR_COLS
RPTabStore
        sta     CurCol
        lbra     RPDone
RPCR
        lda     #1
        sta     CurCol
        lbra     RPDone
RPLF
        lda     CurRow
        cmpa    #SCR_ROWS
        lbhs     RPDone
        inca
        sta     CurRow
        lbra     RPDone
RPLeft
        lda     CurCol
        cmpa    #1
        lbls     RPDone
        deca
        sta     CurCol
        lbra     RPDone
RPRight
        lda     CurCol
        cmpa    #SCR_COLS
        lbhs     RPDone
        inca
        sta     CurCol
        lbra     RPDone
RPUp
        lda     CurRow
        cmpa    #1
        lbls     RPDone
        deca
        sta     CurRow
        lbra     RPDone
RPDown
        lda     CurRow
        cmpa    #SCR_ROWS
        lbhs     RPDone
        inca
        sta     CurRow
        lbra     RPDone
RPHome
        lda     #1
        sta     CurRow
        sta     CurCol
RPDone
        andcc   #$FE
        rts

* Propagate carry from failed native output without losing the stack frame.
AnsiReturnError
        orcc    #$01
        rts
