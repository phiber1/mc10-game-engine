; sprites.asm: sprite throughput benchmark.
;
; NSPR bouncing sprites on a black screen.  Every frame each sprite is
; erased, moved and redrawn.
;   ART=0   16x16 mono sprite ("ball", 256x192 mode)
;   ART=1   8x8 artifact-colour sprite ("orb", 128x192 four-colour mode)
;   MODE=0  OR draw, clear-to-black erase (fastest; overlaps damage each other)
;   MODE=1  XOR draw, XOR erase           (overlaps are safe)
;
; Debug port: $AA when the sprite pass starts, $BB when it ends.  The dt on
; the $BB line is the cycle cost of the whole pass; one frame is 14934.
;
;   make -B log-sprites CPPDEFS="-DNSPR=12 -DMODE=0 -DART=0"

#include "layout.inc"

#ifndef NSPR
#define NSPR 8
#endif
#ifndef MODE
#define MODE 0
#endif
#ifndef ART
#define ART 0
#endif

#if ART
#define SPR_CALL spr_art
#define XMAX (128-orb_W)
#define YMAX (192-orb_H)
#if MODE
#define SPR_DRAW orb_xr
#define SPR_ERASE orb_xr
#else
#define SPR_DRAW orb_or
#define SPR_ERASE orb_er
#endif
#else
#define SPR_CALL spr_mono
#define XMAX (256-ball_W)
#define YMAX (192-ball_H)
#if MODE
#define SPR_DRAW ball_xr
#define SPR_ERASE ball_xr
#else
#define SPR_DRAW ball_or
#define SPR_ERASE ball_er
#endif
#endif

                org     $00A0
obj             rmb     2               ; current object record

                org     CODE
start:
                sei
                lds     #STACK_TOP
                ldaa    #VDG_RG6|VDG_CSS
                staa    VDG
                jsr     cls
                jsr     frame_init
                jsr     draw_all        ; first draw, so the erase has work to undo
loop:
                jsr     frame_wait
                ldaa    #$AA
                DBGA
                ldx     #objs
oloop:
                stx     obj
                ldaa    0,x             ; erase at the old position
                ldab    1,x
                ldx     #SPR_ERASE
                jsr     SPR_CALL
                ldx     obj
                ldaa    0,x             ; x += dx, bounce at the edges
                adda    2,x
                cmpa    #XMAX
                bcs     +
                neg     2,x
                ldaa    0,x
                adda    2,x
+               staa    0,x
                ldab    1,x             ; y += dy
                addb    3,x
                cmpb    #YMAX
                bcs     +
                neg     3,x
                ldab    1,x
                addb    3,x
+               stab    1,x
                ldx     #SPR_DRAW
                jsr     SPR_CALL        ; draw at the new position
                ldx     obj
                ldab    #4
                abx
                cpx     #objs_end
                bne     oloop
                ldaa    #$BB
                DBGA
                bra     loop

draw_all:
                ldx     #objs
-               stx     obj
                ldaa    0,x
                ldab    1,x
                ldx     #SPR_DRAW
                jsr     SPR_CALL
                ldx     obj
                ldab    #4
                abx
                cpx     #objs_end
                bne     -
                rts

cls:
                ldx     #SCREEN
                clra
                clrb
-               std     0,x
                std     2,x
                inx
                inx
                inx
                inx
                cpx     #SCREEN_END
                bne     -
                rts

; object records: x, y, dx, dy (scattered starting positions and speeds)
objs:
i               set     0
                rept    NSPR
                fcb     (i*67+13)#XMAX, (i*41+7)#YMAX, ((i#3)+1)*((i&1)*2-1), ((i#2)+1)*((i&2)-1)
i               set     i+1
                endm
objs_end:

#include "frame.asm"
#include "sprite.asm"
#include "bench_spr.inc"
