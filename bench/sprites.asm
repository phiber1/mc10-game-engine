; sprites.asm: sprite throughput benchmark.
;
; NSPR bouncing sprites on a black screen.  Every frame each sprite is
; erased, moved and redrawn.
;   ART=0   16x16 mono sprite ("ball", 256x192 mode)
;   ART=1   8x8 artifact-colour sprite ("orb", 128x192 four-colour mode)
;   MODE=0  OR draw, clear-to-black erase (fastest; overlaps damage each other)
;   MODE=1  XOR draw, XOR erase           (overlaps are safe)
;   SLOW=1  every sprite moves 1 pixel per frame (default: 1-3 x, 1-2 y)
;   TRACE=1 log each sprite's y to the debug port before its erase and after
;           its redraw, to measure how often the beam catches a sprite
;   MODE=2  self-erasing: the sprite has a 3-pixel blank border and is
;           drawn in store mode, so no erase pass (never disappears)
;   MODE=4  halo: like MODE=2 but the cleared border follows the sprite's
;           shape (grown by 3 pixels), so later sprites cover earlier
;           ones in shape: priority by object order (last = in front)
;   MODE=5  halo with a 1-pixel halo, every sprite at 1 pixel per frame
;   METER=1 CPU meter: the border is green while the sprites are processed
;   MODE=3  XOR delta: drawn once with XOR, then moved one pixel at a time,
;           each step one XOR(old, new) pass (never missing; round overlaps)
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
#ifndef TRACE
#define TRACE 0
#endif
#ifndef ART
#define ART 0
#endif
#if MODE == 5
#define SLOW 1                          /* a 1-pixel halo needs speed 1 */
#endif
#ifndef SLOW
#define SLOW 0                          /* 1: every sprite moves 1 pixel a frame */
#endif

#if ART
#define SPR_CALL spr_art
#define SPR_CALL_D spr_art_d
#if MODE == 2
#define SPR_NAME(s) porb_##s
#elif MODE == 3
#define SPR_NAME(s) dorb_##s
#elif MODE == 4
#define SPR_NAME(s) horb_##s
#elif MODE == 5
#define SPR_NAME(s) horb1_##s
#else
#define SPR_NAME(s) orb_##s
#endif
#define XMAX (128-SPR_NAME(W))
#else
#define SPR_CALL spr_mono
#define SPR_CALL_D spr_mono_d
#if MODE == 2
#define SPR_NAME(s) pball_##s
#elif MODE == 3
#define SPR_NAME(s) dball_##s
#elif MODE == 4
#define SPR_NAME(s) hball_##s
#elif MODE == 5
#define SPR_NAME(s) hball1_##s
#else
#define SPR_NAME(s) ball_##s
#endif
#define XMAX (256-SPR_NAME(W))
#endif
#define YMAX (192-SPR_NAME(H))

#if MODE == 3
#define SPR_DRAW SPR_NAME(xr)           /* first draw only; then delta moves */
#elif MODE == 4 || MODE == 5
#define SPR_DRAW SPR_NAME(hr)
#elif MODE == 2
#define SPR_DRAW SPR_NAME(sr)
#elif MODE == 1
#define SPR_DRAW SPR_NAME(xr)
#define SPR_ERASE SPR_NAME(xr)
#else
#define SPR_DRAW SPR_NAME(or)
#define SPR_ERASE SPR_NAME(er)
#endif

                org     $00A0
obj             rmb     2               ; current object record
ux              rmb     1               ; MODE 3: sign of dx, dy
ax              rmb     1               ; MODE 3: |dx|, |dy|
ay              rmb     1
sx              rmb     1               ; MODE 3: this run of steps (-1, 0, 1)
sy              rmb     1
cnt             rmb     1               ; MODE 3: steps left in this run
uy              rmb     1
dtab            rmb     2               ; MODE 3: delta table for the step

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
                METER_ON
                ldaa    #$AA
                DBGA
                ldx     #objs
oloop:
                stx     obj
#if MODE == 3
                jsr     move_delta
#else
#if TRACE
                ldab    1,x             ; trace: old y, beam before erase
                DBGB
                ldx     obj
#endif
#if MODE != 2 && MODE != 4 && MODE != 5
                ldaa    0,x             ; erase at the old position
                ldab    1,x
                ldx     #SPR_ERASE
                jsr     SPR_CALL
#endif
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
#if TRACE
                ldx     obj             ; trace: new y, beam after draw
                ldab    1,x
                DBGB
#endif
#endif
                ldx     obj
                ldab    #4
                abx
                cpx     #objs_end
                bne     oloop
                ldaa    #$BB
                DBGA
                METER_OFF
                bra     loop

;
; MODE 3: bounce, then move the object at obj one pixel at a time toward
; x+dx, y+dy, each step one XOR delta pass (the sprite is never missing).
#if MODE == 3
sign:                                   ; A = -1, 0 or 1 by the sign of A
                tsta
                beq     +
                bmi     ++
                ldaa    #1
+               rts
+               ldaa    #$FF
                rts

move_delta:
                ldx     obj
                ldaa    0,x             ; bounce: reverse dx if x+dx leaves 0..XMAX-1
                adda    2,x
                cmpa    #XMAX
                bcs     +
                neg     2,x
+               ldab    1,x
                addb    3,x
                cmpb    #YMAX
                bcs     +
                neg     3,x
+               ldaa    2,x             ; plan: ux = sign(dx), ax = |dx|
                bsr     sign
                staa    ux
                ldaa    2,x
                bpl     +
                nega
+               staa    ax
                ldaa    3,x             ; uy = sign(dy), ay = |dy|
                bsr     sign
                staa    uy
                ldaa    3,x
                bpl     +
                nega
+               staa    ay
                ; diagonal steps first: min(ax, ay) of direction (ux, uy)
                ldaa    ax
                cmpa    ay
                bls     +
                ldaa    ay
+               tsta
                beq     mstraight
                staa    cnt
                ldab    uy              ; direction = uy*3 + ux + 4
                aslb
                addb    uy
                addb    ux
                addb    #4
                ldaa    ux
                staa    sx
                ldaa    uy
                staa    sy
                bsr     msteps
mstraight:      ; then |ax - ay| straight steps
                ldaa    ax
                suba    ay
                beq     mdone
                bcs     mvert
                staa    cnt             ; horizontal: direction = ux + 4
                ldab    ux
                addb    #4
                ldaa    ux
                staa    sx
                clr     sy
                bra     msteps          ; tail call
mvert:
                nega                    ; vertical: direction = uy*3 + 4
                staa    cnt
                ldab    uy
                aslb
                addb    uy
                addb    #4
                clr     sx
                ldaa    uy
                staa    sy
                ; fall through
msteps:         ; B = direction; take cnt steps of (sx, sy)
                aslb
                ldx     #SPR_NAME(dt)
                abx
                ldx     0,x
                stx     dtab
-               ldx     obj
                ldaa    0,x             ; old x, y
                ldab    1,x
                ldx     dtab
                jsr     SPR_CALL_D
                ldx     obj
                ldaa    0,x
                adda    sx
                staa    0,x
                ldaa    1,x
                adda    sy
                staa    1,x
                dec     cnt
                bne     -
mdone:
                rts

#endif

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
#if SLOW
                fcb     (i*67+13)#XMAX, (i*41+7)#YMAX, (i&1)*2-1, (i&2)-1
#else
                fcb     (i*67+13)#XMAX, (i*41+7)#YMAX, ((i#3)+1)*((i&1)*2-1), ((i#2)+1)*((i&2)-1)
#endif
i               set     i+1
                endm
objs_end:

#include "frame.asm"
#include "sprite.asm"
#if MODE == 5
#include "halo1_spr.inc"
#elif MODE == 4
#include "halo_spr.inc"
#elif MODE == 3
#if ART
#include "dorb_spr.inc"
#else
#include "dball_spr.inc"
#endif
#else
#include "bench_spr.inc"
#endif
