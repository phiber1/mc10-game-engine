; view.asm: a still display of every sprite in a sprite file, for
; checking new art (bosses and the like) without playing to it.
;
;   make run-view                         sprites/game.spr
;   make run-view VIEW=sprites/mine.spr   any other sprite file
;
; Each sprite is drawn once (artifact color, halo sprites with their
; halo routine, at shift 0 or its one shift), named underneath, left to
; right in rows.  tools/sprview.py makes the drawing code from the file.

#include "layout.inc"

                org     BSS
vw_rt           rmb     2               ; the sprite routine to call

                org     CODE
start:
                sei
                lds     #STACK_TOP
                ldaa    #VDG_RG6|VDG_CSS
                staa    VDG
                staa    vdg_shadow
                jsr     cls
                ldaa    #TXT_WHITE
                staa    txt_col
#include "view_list.inc"
                bra     *

; call the routine at vw_rt with X = its screen address
vw_call:
                ldd     vw_rt
                pshb
                psha
                rts

; cls: clear the RG6 screen
cls:
                ldx     #SCREEN
                clra
                clrb
cls_b1:         std     0,x
                std     2,x
                inx
                inx
                inx
                inx
                cpx     #SCREEN_END
                bne     cls_b1
                rts

#include "text.asm"
; the halo sprites' descriptors name the sprite engine's draw routines,
; which the viewer doesn't use
spr_art         equ     0
spr_mono        equ     0
#include "view_spr.inc"
