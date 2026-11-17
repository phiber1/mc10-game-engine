; smdemo.asm: sprite manager demo and benchmark.
;
; NSPR objects with 1-pixel halo sprites and mixed fixed-point speeds
; (0.25 to 1 pixel per frame on each axis) bounce around the screen.
; Table order is priority: later objects pass in front of earlier ones.
;   ART=0   16x16 mono ball      ART=1   8x16 artifact orb
;   METER=1 CPU meter (green while the frame's work runs)
;
; Debug port: $AA when the frame's work starts, $BB when it ends.
;
;   make -B log-smdemo CPPDEFS="-DNSPR=20 -DART=0"

#include "layout.inc"

#ifndef NSPR
#define NSPR 20
#endif
#ifndef ART
#define ART 0
#endif

#if ART
#define SPR_HR horb1_hr
#define SPR_ER horb1_er
#define XMAX (128-horb1_W)
#define YMAX (192-horb1_H)
#else
#define SPR_HR hball1_hr
#define SPR_ER hball1_er
#define XMAX (256-hball1_W)
#define YMAX (192-hball1_H)
#endif

                org     CODE
start:
                sei
                lds     #STACK_TOP
                ldaa    #VDG_RG6|VDG_CSS
                staa    VDG
                jsr     cls
                ldx     #objs
                stx     obj_first
                ldx     #objs_end
                stx     obj_end
                jsr     frame_init
loop:
                jsr     frame_wait
                METER_ON
                ldaa    #$AA
                DBGA
                jsr     bounce          ; game logic
                jsr     spr_update_all  ; move and draw everything
                ldaa    #$BB
                DBGA
                METER_OFF
                bra     loop

; Reverse an object's velocity when its next position would leave the
; screen (a negative position wraps to $FF.., which is >= the limit too).
bounce:
                ldx     #objs
-               ldd     O_X,x
                addd    O_DX,x
                cmpa    #XMAX
                bcs     +
                ldd     #0
                subd    O_DX,x
                std     O_DX,x
+               ldd     O_Y,x
                addd    O_DY,x
                cmpa    #YMAX
                bcs     +
                ldd     #0
                subd    O_DY,x
                std     O_DY,x
+               ldab    #OBJ_SIZE
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

; The sprite descriptor
desc:
                fdb     SPR_HR, SPR_ER
#if ART
                fdb     spr_art
#else
                fdb     spr_mono
#endif

; Objects: x.frac, y.frac, dx, dy (8.8), descriptor.  Speeds cycle through
; 0.25, 0.5, 0.75 and 1 pixel per frame, with mixed directions.
objs:
i               set     0
                rept    NSPR
                fcb     (i*67+13)#XMAX, 0, (i*41+7)#YMAX, 0
                fdb     ((i#4)+1)*$40*((i&1)*2-1)
                fdb     (((i/4)#4)+1)*$40*((i&2)-1)
                fdb     desc
i               set     i+1
                endm
objs_end:

#include "frame.asm"
#include "sprite.asm"
#include "sprman.asm"
#include "halo1_spr.inc"
