; sprite.asm: calling compiled sprites (see tools/spritec.c).
;
; spr_mono      A = x (0-255), B = y (0-191), X = routine table
;               (NAME_or, NAME_xr or NAME_er of a mono sprite)
; spr_art       the same for artifact sprites, x = 0-127
;
; Both pick the routine for the sub-byte shift, point X at the sprite's
; top-left screen byte, and jump to it.  About 60 cycles plus the routine.
; Uses A, B, X.  The routine address is patched into the JMP, so this code
; must run from RAM.

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

; screen address of each row
rowtab:
r               set     0
                rept    192
                fdb     SCREEN+r*ROW_BYTES
r               set     r+1
                endm
