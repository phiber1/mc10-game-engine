; sprite.asm: calling compiled sprites (see tools/spritec.c).
;
; spr_mono      A = x (0-255), B = y (see rowtab), X = routine table
;               (NAME_or, NAME_xr or NAME_er of a mono sprite)
; spr_art       the same for artifact sprites, x = 0-127
;
; Both pick the routine for the sub-byte shift, point X at the sprite's
; top-left screen byte, and jump to it.  About 60 cycles plus the routine.
; Uses A, B, X.  The routine address is patched into the JMP, so this code
; must run from RAM.
;
; spr_mono_d, spr_art_d   XOR delta moves; see below.

spr_mono:
                pshb                    ; y
                tab
                lsra                    ; column = x / 8
                lsra
                lsra
                staa    spr_col
                andb    #7              ; shift = x & 7
spr_go:
                aslb
                abx
                ldx     0,x             ; routine for this shift
                stx     spr_jmp+1
                pulb
                ldx     #rowtab
                abx
                abx
                ldd     0,x             ; row address (low byte is a multiple
                addb    spr_col         ; of 32, so adding the column never carries)
                std     spr_scr
                ldx     spr_scr
spr_jmp:
                jmp     spr_jmp         ; patched

spr_art:
                pshb                    ; y
                tab
                lsra                    ; column = x / 4
                lsra
                staa    spr_col
                andb    #3              ; shift = x & 3
                bra     spr_go

; spr_mono_d / spr_art_d: XOR delta moves (spritec "delta").
; A = OLD x, B = OLD y, X = NAME_dt<d>, the table for the move direction.
; The delta routines expect X one row up and one byte left of the old
; position, so these subtract 33 from the screen address.
spr_mono_d:
                pshb
                tab
                lsra
                lsra
                lsra
                staa    spr_col
                andb    #7
spr_go_d:
                aslb
                abx
                ldx     0,x
                stx     spr_jmpd+1
                pulb
                ldx     #rowtab
                abx
                abx
                ldd     0,x
                addb    spr_col
                subd    #ROW_BYTES+1    ; one row up, one byte left
                std     spr_scr
                ldx     spr_scr
spr_jmpd:
                jmp     spr_jmpd        ; patched

spr_art_d:
                pshb
                tab
                lsra
                lsra
                staa    spr_col
                andb    #3
                bra     spr_go_d

; Screen address of each row, for every value of the y byte:
;   0-191    the screen
;   192-223  the bottom gutter, $5800-$5BFF: hidden memory below the
;            screen, so sprites can slide off the bottom whole
;   224-255  y = -32..-1, the top gutter, $3C00-$3FFF: on the MCX32-SD
;            this is flash, which ignores these writes (the flash only
;            programs after an unlock sequence at chip offsets $5555 and
;            $2AAA, which this window can never address), so sprites can
;            slide in from above the top whole
; A sprite must stay within 32 rows of the screen.  Nothing else may use
; $5800-$5BFF (the stack lives above it).
rowtab:
r               set     0
                rept    256
                if      r < 224
                fdb     SCREEN+r*ROW_BYTES
                else
                fdb     SCREEN-(256-r)*ROW_BYTES
                endif
r               set     r+1
                endm
