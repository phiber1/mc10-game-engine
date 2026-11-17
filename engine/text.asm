; text.asm: text in artifact mode, with the 3x5 font in font.asm.
;
; One character = one byte across (three artifact pixels and a gap) by 5
; rows, so a line holds 32 characters.  txt_col masks the white font into
; a colour: TXT_WHITE, TXT_ORANGE or TXT_BLUE (orange/blue as at colour
; phase 0; after a colour swap the program uses the other one).  Text is
; drawn with plain stores, so it replaces what was under it.
;
; txt_char      A = character (ASCII 32-90), X = screen address: draw it.
;               Returns X = the next cell.  ~130 cycles.
; txt_str       X = screen address, D = string (0 = end): draw it.
;               Returns X = the next cell.
; txt_char2, txt_str2   the same in double height (10 rows)
; txt_bcd       X = screen address, D = BCD bytes, tx_n = how many: draw
;               2 digits per byte.  Returns X = the next cell.
; TXT_AT row, col   assemble the screen address of a text cell (row in
;               pixel rows, col 0-31)
;
; Uses A, B, X.

TXT_WHITE       equ     $FF
TXT_ORANGE      equ     $AA             ; bit pairs 10
TXT_BLUE        equ     $55             ; bit pairs 01

txt_char:
                stx     tx_scr
                suba    #32
                ldab    #5
                mul                     ; D = glyph offset
                addd    #font
                std     tx_g
                ldx     tx_g
                ldaa    0,x             ; the glyph's five rows ...
                ldab    1,x
                std     tx_r
                ldaa    2,x
                ldab    3,x
                std     tx_r+2
                ldaa    4,x
                staa    tx_r+4
                ldx     tx_scr          ; ... coloured onto the screen
                ldaa    tx_r
                anda    txt_col
                staa    0,x
                ldaa    tx_r+1
                anda    txt_col
                staa    ROW_BYTES,x
                ldaa    tx_r+2
                anda    txt_col
                staa    2*ROW_BYTES,x
                ldaa    tx_r+3
                anda    txt_col
                staa    3*ROW_BYTES,x
                ldaa    tx_r+4
                anda    txt_col
                staa    4*ROW_BYTES,x
                inx
                rts

; txt_char2: the same, double height (each row twice: 10 rows)
txt_char2:
                stx     tx_scr
                suba    #32
                ldab    #5
                mul
                addd    #font
                std     tx_g
                ldx     tx_g
                ldaa    0,x
                ldab    1,x
                std     tx_r
                ldaa    2,x
                ldab    3,x
                std     tx_r+2
                ldaa    4,x
                staa    tx_r+4
                ldx     tx_scr
                ldaa    tx_r
                anda    txt_col
                staa    0,x
                staa    ROW_BYTES,x
                ldaa    tx_r+1
                anda    txt_col
                staa    2*ROW_BYTES,x
                staa    3*ROW_BYTES,x
                ldaa    tx_r+2
                anda    txt_col
                staa    4*ROW_BYTES,x
                staa    5*ROW_BYTES,x
                ldaa    tx_r+3
                anda    txt_col
                staa    6*ROW_BYTES,x
                staa    7*ROW_BYTES,x
                ldab    #4*ROW_BYTES    ; rows 8-9 are past the 8-bit offset
                abx
                abx
                ldaa    tx_r+4
                anda    txt_col
                staa    0,x
                staa    ROW_BYTES,x
                ldx     tx_scr
                inx
                rts

; txt_str2: txt_str in double height
txt_str2:
                std     tx_s
-               stx     tx_scr2
                ldx     tx_s
                ldaa    0,x
                beq     +
                inx
                stx     tx_s
                ldx     tx_scr2
                bsr     txt_char2
                bra     -
+               ldx     tx_scr2
                rts

txt_str:
                std     tx_s
-               stx     tx_scr2
                ldx     tx_s
                ldaa    0,x
                beq     +
                inx
                stx     tx_s
                ldx     tx_scr2
                jsr     txt_char
                bra     -
+               ldx     tx_scr2
                rts

; txt_bcd: X = screen address, D = address of the first BCD byte,
; tx_n = number of bytes: draw 2 digits per byte.  Returns X = next cell.
txt_bcd:
                std     tx_s
-               stx     tx_scr2
                ldx     tx_s
                ldaa    0,x
                inx
                stx     tx_s
                psha
                lsra                    ; high digit
                lsra
                lsra
                lsra
                adda    #'0'
                ldx     tx_scr2
                jsr     txt_char
                pula
                anda    #$0F            ; low digit
                adda    #'0'
                jsr     txt_char
                dec     tx_n
                bne     -
                rts

#include "font.asm"
