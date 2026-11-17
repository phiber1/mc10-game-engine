; shooter.asm: a playable test of the sprite engine (not a game yet).
;
; Alien craft fly curving paths at up to 2 pixels a frame and re-enter
; from the top when they leave at the bottom.  The ship (W A S Z or the
; arrow keys, SPACE to fire) moves 2 pixels a frame; shots fly at 4.
; Shots destroy aliens.  Everything is drawn with halo sprites through the
; sprite manager, so nothing flickers: table order puts the aliens at the
; back, then the shots, with the ship in front.
;
;   Sound: a zap per shot, an explosion per hit (engine/sound.asm).
;   METER=1     CPU meter        NALIEN=n     number of aliens (default 10)

#define OBJ_EXTRA 4
#include "layout.inc"

#ifndef NALIEN
#define NALIEN 10
#endif
#define NSHOT 3

; per-alien game data (after the sprite manager's fields)
A_ANG           equ     O_USER          ; heading, 0-255 (64 = straight down)
A_TURN          equ     O_USER+1        ; heading change per frame (signed)
A_TMR           equ     O_USER+2        ; frames until the next new turn
A_SLOW          equ     O_USER+3        ; nonzero: half speed

SHIP_SPEED      equ     $0200           ; 2 pixels a frame
SHOT_SPEED      equ     $0400           ; 4 pixels a frame
SHIP_XMAX       equ     256-ship_W
SHIP_YMIN       equ     120
SHIP_YMAX       equ     192-ship_H
AL_XMAX         equ     256-alien_W
AL_YMAX         equ     192-alien_H
FIRE_DELAY      equ     8               ; frames between shots

                org     PROG_DP
cooldown        rmb     1
seed            rmb     2               ; random number generator state
sl_ptr          rmb     2
al_obj          rmb     2               ; alien being processed
sh_obj          rmb     2               ; shot being processed
score           rmb     2               ; aliens destroyed

                org     CODE
start:
                sei
                lds     #STACK_TOP
                ldaa    #$FF
                staa    P1DDR           ; keyboard column strobes are outputs
                ldaa    #VDG_RG6|VDG_CSS
                staa    VDG
                staa    vdg_shadow
                jsr     cls
                ldd     FRC             ; seed the generator (never zero)
                orab    #1
                std     seed
                clr     cooldown
                ldd     #0
                std     score
                ldx     #objs
                stx     obj_first
                ldx     #objs_end
                stx     obj_end
                ldx     #aliens         ; launch every alien from the top
-               stx     al_obj
                jsr     al_spawn
                ldx     al_obj
                ldab    #OBJ_SIZE
                abx
                cpx     #aliens_end
                bne     -
                jsr     frame_init
loop:
                jsr     frame_wait
                METER_ON
                ldaa    #$AA
                DBGA
                jsr     snd_frame
                jsr     kbd_read
                jsr     ship_logic
                jsr     fire_logic
                jsr     shots_logic
                jsr     aliens_logic
                jsr     collide
                jsr     spr_update_all
                ldaa    #$BB
                DBGA
                METER_OFF
                bra     loop

; ---------------------------------------------------------------- ship
ship_logic:
                ldx     #ship
                ldd     #0
                std     O_DX,x
                std     O_DY,x
                ldaa    joy
                bita    #J_LEFT
                beq     +
                ldd     #-SHIP_SPEED
                std     O_DX,x
                ldaa    joy
+               bita    #J_RIGHT
                beq     +
                ldd     #SHIP_SPEED
                std     O_DX,x
                ldaa    joy
+               bita    #J_UP
                beq     +
                ldd     #-SHIP_SPEED
                std     O_DY,x
                ldaa    joy
+               bita    #J_DOWN
                beq     +
                ldd     #SHIP_SPEED
                std     O_DY,x
+               ldd     O_X,x           ; stop at the screen edges
                addd    O_DX,x
                cmpa    #SHIP_XMAX
                bcs     +
                ldd     #0
                std     O_DX,x
+               ldd     O_Y,x           ; and inside the lower area
                addd    O_DY,x
                cmpa    #SHIP_YMIN
                bcs     sl_stop
                cmpa    #SHIP_YMAX
                bcs     sl_done
sl_stop:        ldd     #0
                std     O_DY,x
sl_done:        rts

; ---------------------------------------------------------------- shots
fire_logic:
                ldaa    cooldown
                beq     +
                dec     cooldown
                rts
+               ldaa    joy
                bita    #J_FIRE
                beq     fl_done
                ldx     #shots          ; find a free shot
-               ldd     O_SPR,x
                beq     +
                ldab    #OBJ_SIZE
                abx
                cpx     #shots_end
                bne     -
                rts                     ; all in flight
+               ldaa    ship+O_X        ; centre of the ship's nose
                adda    #ship_PAD+6-shot_PAD
                staa    O_X,x
                ldaa    ship+O_Y
                adda    #ship_PAD-shot_H+shot_PAD
                staa    O_Y,x
                clr     O_XF,x
                clr     O_YF,x
                ldd     #0
                std     O_DX,x
                ldd     #-SHOT_SPEED
                std     O_DY,x
                ldd     #shot_desc
                std     O_SPR,x
                ldaa    #FIRE_DELAY
                staa    cooldown
                ldx     #fx_zap
                ldaa    #1
                jsr     snd_play
fl_done:        rts

shots_logic:
                ldx     #shots
-               stx     sh_obj
                ldd     O_SPR,x
                beq     +
                ldd     O_Y,x           ; leaving the top?
                addd    O_DY,x
                cmpa    #192
                bcs     +
                jsr     obj_erase
                ldx     sh_obj
                ldd     #0
                std     O_SPR,x
+               ldx     sh_obj
                ldab    #OBJ_SIZE
                abx
                cpx     #shots_end
                bne     -
                rts

; ---------------------------------------------------------------- aliens
aliens_logic:
                ldx     #aliens
al_loop:
                stx     al_obj
                dec     A_TMR,x         ; time for a new turn rate?
                bne     +
                jsr     rnd
                ldx     al_obj
                andb    #7              ; -3 .. +3 (and 4 = -4)
                subb    #3
                stab    A_TURN,x
                jsr     rnd
                ldx     al_obj
                andb    #63
                orab    #16
                stab    A_TMR,x
+               ldaa    A_ANG,x         ; heading += turn
                adda    A_TURN,x
                staa    A_ANG,x
                bsr     al_velocity
                ldx     al_obj
                ldd     O_X,x           ; bounce off the sides
                addd    O_DX,x
                cmpa    #AL_XMAX
                bcs     +
                ldaa    #128            ; mirror the heading: 128 - angle
                suba    A_ANG,x
                staa    A_ANG,x
                bsr     al_velocity
                ldx     al_obj
+               ldd     O_Y,x
                addd    O_DY,x
                cmpa    #192            ; above the top (wrapped)?
                bcs     +
                neg     A_ANG,x         ; mirror: -angle
                bsr     al_velocity
                ldx     al_obj
                bra     al_next
+               cmpa    #AL_YMAX        ; past the bottom: back to the top
                bcs     al_next
                jsr     obj_erase
                ldx     al_obj
                jsr     al_spawn
al_next:        ldx     al_obj
                ldab    #OBJ_SIZE
                abx
                cpx     #aliens_end
                bne     al_loop
                rts

; velocity from heading: dx = 2 cos, dy = 2 sin (halved if slow)
al_velocity:
                ldx     al_obj
                ldab    A_ANG,x
                addb    #64             ; cos(a) = sin(a + 64)
                bsr     sin_lookup
                ldx     al_obj
                tst     A_SLOW,x
                beq     +
                asra
                rorb
+               std     O_DX,x
                ldab    A_ANG,x
                bsr     sin_lookup
                ldx     al_obj
                tst     A_SLOW,x
                beq     +
                asra
                rorb
+               std     O_DY,x
                rts

; B = angle -> D = 2 sin(angle), 8.8
sin_lookup:
                clra
                aslb
                rola
                addd    #sintab
                std     sl_ptr
                ldx     sl_ptr
                ldd     0,x
                rts

; launch the alien at al_obj from the top at a random place and heading
al_spawn:
                jsr     rnd
                cmpb    #AL_XMAX
                bcs     +
                subb    #AL_XMAX
+               ldx     al_obj
                stab    O_X,x
                clr     O_XF,x
                clr     O_Y,x
                clr     O_YF,x
                jsr     rnd             ; heading 40-87: downwards
                ldx     al_obj
                andb    #47
                addb    #40
                stab    A_ANG,x
                clr     A_TURN,x
                jsr     rnd
                ldx     al_obj
                andb    #31
                orab    #8
                stab    A_TMR,x
                jsr     rnd
                ldx     al_obj
                andb    #1
                stab    A_SLOW,x
                jsr     al_velocity
                ldx     al_obj
                ldd     #alien_desc
                std     O_SPR,x
                rts

; ---------------------------------------------------------------- hits
; A shot hits an alien when their visible pixels' boxes overlap.  With
; unsigned compares: (shot - alien + offset) < span on each axis.
; (NAME_W and NAME_H include the halo padding, so subtract it.)
SHOT_VW         equ     shot_W-2*shot_PAD               ; visible sizes
SHOT_VH         equ     shot_H-2*shot_PAD
ALIEN_VW        equ     alien_W-2*alien_PAD
ALIEN_VH        equ     alien_H-2*alien_PAD
HIT_X           equ     shot_PAD-alien_PAD+SHOT_VW-1
HIT_XS          equ     ALIEN_VW+SHOT_VW-1
HIT_Y           equ     shot_PAD-alien_PAD+SHOT_VH-1
HIT_YS          equ     ALIEN_VH+SHOT_VH-1

collide:
                ldx     #shots
cs_loop:
                stx     sh_obj
                ldd     O_SPR,x
                beq     cs_next
                ldx     #aliens
ca_loop:
                stx     al_obj
                ldx     sh_obj
                ldaa    O_X,x
                ldab    O_Y,x
                ldx     al_obj
                suba    O_X,x
                adda    #HIT_X
                cmpa    #HIT_XS
                bcc     ca_next
                subb    O_Y,x
                addb    #HIT_Y
                cmpb    #HIT_YS
                bcc     ca_next
                ldx     sh_obj          ; hit: remove the shot
                jsr     obj_erase
                ldx     sh_obj
                ldd     #0
                std     O_SPR,x
                ldx     al_obj          ; and send the alien back to the top
                jsr     obj_erase
                jsr     al_spawn
                ldd     score
                addd    #1
                std     score
                ldx     #fx_boom        ; explosions beat zaps (priority 2)
                ldaa    #2
                jsr     snd_play
                bra     cs_next
ca_next:
                ldx     al_obj
                ldab    #OBJ_SIZE
                abx
                cpx     #aliens_end
                bne     ca_loop
cs_next:
                ldx     sh_obj
                ldab    #OBJ_SIZE
                abx
                cpx     #shots_end
                bne     cs_loop
                rts

; ---------------------------------------------------------------- misc
; 16-bit Galois LFSR: B = a new random byte
rnd:
                ldd     seed
                lsrd
                bcc     +
                eora    #$B4
+               std     seed
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

; 2 sin(angle) in 8.8 for angle 0-255 (64 = 90 degrees, down the screen)
sintab:
i               set     0
                rept    256
                fdb     int(512.0*sin(i*3.14159265358979/128.0))
i               set     i+1
                endm

; sound effects (see engine/sound.asm)
fx_zap:         fcb     8, SND_TONE     ; ~1 kHz sliding down to ~450 Hz
                fdb     450, 70
                fcb     0
fx_boom:        fcb     4, SND_NOISE    ; a crack, then a deepening rumble
                fdb     400, 0
                fcb     24, SND_NOISE
                fdb     600, 30
                fcb     0

; sprite descriptors
alien_desc:     fdb     alien_hr, alien_er, spr_mono
shot_desc:      fdb     shot_hr, shot_er, spr_mono
ship_desc:      fdb     ship_hr, ship_er, spr_mono

; Object table, in priority order: aliens, shots, ship
objs:
aliens:
                rept    NALIEN
                fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                endm
aliens_end:
shots:
                rept    NSHOT
                fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                endm
shots_end:
ship:
                fcb     (256-ship_W)/2&$FE, 0, 160, 0
                fdb     0, 0, ship_desc
                fcb     0, 0, 0, 0
objs_end:

#include "frame.asm"
#include "sprite.asm"
#include "sprman.asm"
#include "input.asm"
#include "sound.asm"
#include "shooter_spr.inc"
