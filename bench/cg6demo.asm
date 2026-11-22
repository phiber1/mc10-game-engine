; cg6demo.asm: the graphics mode API in CG6 (128x192, four real colors,
; NTSC and PAL alike) on a blue background: halo sprites from
; sprites/cg6demo.spr (spritec "cg6 ... bg B") bounce under a line of text.
; SPACE switches to the other color set (CSS=1: buff, cyan, magenta,
; orange) and back.
;
;   make run-cg6demo

#define GFX_MODE GFX_CG6
#define GFX_BG CG_BLUE
#include "layout.inc"

NOBJ            equ     12
YMIN            equ     16              ; below the text
YMAX_GEM        equ     192-gem_H
XMAX            equ     128-thief_W

                org     BSS
dm_css          rmb     1               ; the color set shown
dm_key          rmb     1               ; SPACE was down last frame

                org     CODE
start:
                sei
                lds     #STACK_TOP
                jsr     gfx_init        ; CG6, the screen filled with blue
                ldaa    #COLOR_BYTE(CG_YELLOW)
                staa    txt_col
                ldx     #TXT_AT(4,1)
                ldd     #s_title
                jsr     txt_str
                clr     dm_css
                clr     dm_key
                ldx     #objs
                stx     obj_first
                ldx     #objs_end
                stx     obj_end
                jsr     frame_init
loop:
                jsr     frame_wait
                jsr     bounce
                jsr     spr_update_all
                jsr     kbd_read        ; SPACE: the other color set
                ldaa    joy
                anda    #J_FIRE
                tab
                eora    dm_key          ; (on the press, not while held)
                stab    dm_key
                anda    dm_key
                beq     loop
                ldaa    dm_css
                eora    #1
                staa    dm_css
                jsr     gfx_css
                bra     loop

; reverse an object's velocity when its next position would leave the area
bounce:
                ldx     #objs
bn_b1:          ldd     O_X,x
                addd    O_DX,x
                cmpa    #XMAX
                bcs     bn_f1
                ldd     #0
                subd    O_DX,x
                std     O_DX,x
bn_f1:          ldd     O_Y,x
                addd    O_DY,x
                cmpa    #YMIN
                bcs     bn_f2
                cmpa    #YMAX_GEM-6
                bcs     bn_f3
bn_f2:          ldd     #0
                subd    O_DY,x
                std     O_DY,x
bn_f3:          ldab    #OBJ_SIZE
                abx
                cpx     #objs_end
                bne     bn_b1
                rts

s_title:        fcc     "CG6 ON BLUE  SPACE: COLOR SET"
                fcb     0

; objects: x.frac, y.frac, dx, dy (8.8), descriptor: gems first (lowest
; priority), then thieves, the hero in front
objs:
i               set     0
                rept    NOBJ
                fcb     (i*37+5)#XMAX, 0, YMIN+2+(i*29)#(YMAX_GEM-YMIN-12), 0
                fdb     ((i#3)+1)*$50*((i&1)*2-1)
                fdb     (((i/3)#3)+1)*$40*((i&2)-1)
                if      i<6
                fdb     gem_dsc
                elseif  i<NOBJ-1
                fdb     thief_dsc
                else
                fdb     hero_dsc
                endif
i               set     i+1
                endm
objs_end:

#include "gfx.asm"
#include "frame.asm"
#include "input.asm"
#include "text.asm"
#include "sprite.asm"
#include "sprman.asm"
#include "cg6demo_spr.inc"
