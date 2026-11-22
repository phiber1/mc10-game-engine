; view.asm: a still display of every sprite in a sprite file, for
; checking new art (bosses and the like) without playing to it.
;
;   make run-view                         sprites/game.spr
;   make run-view VIEW=sprites/mine.spr   any other sprite file
;
; Each sprite is drawn once (in the file's mode: artifact color, or CG6 on
; its "bg" color; halo sprites with their halo routine, at shift 0 or its
; one shift), named underneath, left to right in rows.  tools/sprview.py
; makes the drawing code from the file.

#include "layout.inc"

                org     BSS
vw_rt           rmb     2               ; the sprite routine to call

                org     CODE
start:
                sei
                lds     #STACK_TOP
                ldaa    #GFX_VDG
                staa    VDG
                staa    vdg_shadow
                jsr     cls
                ldaa    #vw_text
                staa    txt_col
#include "view_list.inc"
                bra     *

; call the routine at vw_rt with X = its screen address
vw_call:
                ldd     vw_rt
                pshb
                psha
                rts

; cls: clear the screen to the background
cls:
                ldx     #SCREEN
                if      GFX_FILL
                ldaa    #GFX_FILL
                tab
                else
                clra
                clrb
                endif
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
