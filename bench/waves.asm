; waves.asm: attack waves on scripted flight paths (a playable test).
;
; Waves of aliens enter one after another along the same scripted path,
; so each wave flies as a snake: loops, S-curves, slow circling, then
; dives through the bottom of the screen and back in at the top (the
; screen gutters let sprites slide off and on whole).  Three alien types;
; aliens drop bombs at points in their paths.  The ship (W A S Z / arrows,
; SPACE fires) shoots them; bombs hitting the ship only make a sound (no
; death yet).  A star field falls behind everything.
;
;   METER=1     CPU meter

#define OBJ_EXTRA 6                     /* = FL_BYTES (flight.asm checks) */
#include "layout.inc"

#define NALIEN 10
#define NBOMB 6
#define NSHOT 3

SHIP_SPEED      equ     $0200           ; 2 pixels a frame
SHOT_SPEED      equ     $0400
BOMB_SPEED      equ     $0300
SHIP_XMAX       equ     256-ship_W
SHIP_YMIN       equ     120
SHIP_YMAX       equ     192-ship_H
FIRE_DELAY      equ     8
WAVE_GAP        equ     90              ; frames between waves

                org     PROG_DP
cooldown        rmb     1
seed            rmb     2
obj             rmb     2               ; object being processed
obj2            rmb     2
wv_ptr          rmb     2               ; current wave
wv_left         rmb     1               ; aliens still to launch
wv_timer        rmb     1               ; frames to the next launch / wave
alive           rmb     1               ; aliens on screen
hits            rmb     2               ; aliens destroyed
ouch            rmb     1               ; bombs that hit the ship
cy              rmb     1               ; collide: the shot's row + 24

                org     CODE
start:
                sei
                lds     #STACK_TOP
                ldaa    #$FF
                staa    P1DDR
                ldaa    #VDG_RG6|VDG_CSS
                staa    VDG
                staa    vdg_shadow
                jsr     cls
                ldd     FRC
                orab    #1
                std     seed
                std     st_seed
                jsr     stars_init
                clr     cooldown
                clr     ouch
                ldd     #0
                std     hits
                ldx     #objs
                stx     obj_first
                ldx     #objs_end
                stx     obj_end
                ldx     #waves          ; first wave
                stx     wv_ptr
                jsr     wave_begin
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
                jsr     wave_logic
                jsr     aliens_logic
                jsr     bombs_logic
                jsr     shots_logic
                jsr     collide
                jsr     stars_update    ; stars first: sprites cover them
                jsr     spr_update_all
                ldaa    #$BB
                DBGA
                METER_OFF
                bra     loop

; ---------------------------------------------------------------- waves
; A wave: fdb descriptor, script; fcb count, launch interval, entry x.
; The table ends with fdb 0 (back to the start).
W_DESC          equ     0
W_PATH          equ     2
W_COUNT         equ     4
W_GAP           equ     5
W_X             equ     6
W_SIZE          equ     7

wave_begin:
                ldx     wv_ptr
                ldaa    W_COUNT,x
                staa    wv_left
                ldaa    #1
                staa    wv_timer
                rts

wave_logic:
                dec     wv_timer
                bne     wl_done
                ldaa    wv_left
                beq     wl_next         ; all launched: wait for the next wave
                ldx     #aliens         ; launch one into a free slot
-               ldd     O_SPR,x
                beq     +
                ldab    #OBJ_SIZE
                abx
                cpx     #aliens_end
                bne     -
                inc     wv_timer        ; none free: try next frame
                rts
+               stx     obj
                ldx     wv_ptr
                ldaa    W_X,x
                ldab    W_GAP,x
                stab    wv_timer
                ldx     obj
                staa    O_X,x           ; enter just above the top
                clr     O_XF,x
                ldab    #256-saucer_H
                stab    O_Y,x
                clr     O_YF,x
                ldx     wv_ptr
                ldd     W_PATH,x
                pshb
                psha
                ldd     W_DESC,x
                ldx     obj
                std     O_SPR,x
                pula
                pulb
                jsr     fl_start
                ldx     obj
                jsr     fl_step         ; first frame: sets the velocity
                dec     wv_left
                inc     alive
wl_done:        rts
wl_next:                                ; next wave when at most 2 remain
                ldaa    alive
                cmpa    #2
                bls     +
                inc     wv_timer
                rts
+               ldx     wv_ptr
                ldab    #W_SIZE
                abx
                ldd     0,x
                bne     +
                ldx     #waves          ; end of the table: start again
+               stx     wv_ptr
                ldaa    W_COUNT,x
                staa    wv_left
                ldaa    #WAVE_GAP
                staa    wv_timer
                rts

; ---------------------------------------------------------------- aliens
aliens_logic:
                ldaa    ship+O_X        ; the aim target: the ship
                staa    fl_tx
                ldaa    ship+O_Y
                staa    fl_ty
                ldx     #aliens
al_loop:
                stx     obj
                ldd     O_SPR,x
                beq     al_next
                jsr     fl_step
                ldaa    fl_event        ; event 1: drop a bomb
                cmpa    #1
                bne     +
                jsr     drop_bomb
+               ldx     obj             ; safety: mirror off the sides
                ldd     O_X,x
                addd    O_DX,x
                cmpa    #256-saucer_W
                bcs     +
                ldaa    #128
                suba    F_ANG,x
                staa    F_ANG,x
                jsr     fl_velocity
                ldx     obj
+               ldd     O_Y,x           ; through the bottom: back in at the top
                addd    O_DY,x
                cmpa    #192
                bcs     al_next
                cmpa    #224
                bcc     al_next
                ldaa    #256-saucer_H
                staa    O_Y,x
al_next:
                ldx     obj
                ldab    #OBJ_SIZE
                abx
                cpx     #aliens_end
                bne     al_loop
                rts

; drop a bomb from the alien at obj, if it's on screen above the ship
drop_bomb:
                ldx     obj
                ldaa    O_Y,x
                cmpa    #SHIP_YMIN-16
                bcc     db_done
                ldx     #bombs
-               ldd     O_SPR,x
                beq     +
                ldab    #OBJ_SIZE
                abx
                cpx     #bombs_end
                bne     -
db_done:        rts
+               stx     obj2
                ldx     obj
                ldaa    O_X,x
                adda    #saucer_PAD+5-bomb_PAD
                ldab    O_Y,x
                addb    #saucer_H-saucer_PAD-bomb_PAD
                ldx     obj2
                staa    O_X,x
                stab    O_Y,x
                clr     O_XF,x
                clr     O_YF,x
                ldd     #0
                std     O_DX,x
                ldd     #BOMB_SPEED
                std     O_DY,x
                ldd     #bomb_dsc
                std     O_SPR,x
                ldx     #fx_drop
                ldaa    #1
                jmp     snd_play

bombs_logic:
                ldx     #bombs
-               stx     obj2
                ldd     O_SPR,x
                beq     +
                ldd     O_Y,x           ; off the bottom?
                addd    O_DY,x
                cmpa    #192-bomb_H
                bcs     +
                jsr     obj_erase
                ldx     obj2
                ldd     #0
                std     O_SPR,x
+               ldx     obj2
                ldab    #OBJ_SIZE
                abx
                cpx     #bombs_end
                bne     -
                rts

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
+               ldd     O_X,x
                addd    O_DX,x
                cmpa    #SHIP_XMAX
                bcs     +
                ldd     #0
                std     O_DX,x
+               ldd     O_Y,x
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
                ldx     #shots
-               ldd     O_SPR,x
                beq     +
                ldab    #OBJ_SIZE
                abx
                cpx     #shots_end
                bne     -
                rts
+               ldaa    ship+O_X
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
                ldd     #shot_dsc
                std     O_SPR,x
                ldaa    #FIRE_DELAY
                staa    cooldown
                ldx     #fx_zap
                ldaa    #1
                jsr     snd_play
fl_done:        rts

shots_logic:
                ldx     #shots
-               stx     obj2
                ldd     O_SPR,x
                beq     +
                ldd     O_Y,x
                addd    O_DY,x
                cmpa    #192
                bcs     +
                jsr     obj_erase
                ldx     obj2
                ldd     #0
                std     O_SPR,x
+               ldx     obj2
                ldab    #OBJ_SIZE
                abx
                cpx     #shots_end
                bne     -
                rts

; ---------------------------------------------------------------- hits
collide:
                ldx     #shots          ; shots against aliens
cs_loop:
                stx     ht_a
                ldd     O_SPR,x
                beq     cs_next
                ldaa    O_Y,x           ; this shot's row, for the quick reject
                adda    #24
                staa    cy
                ldx     #aliens
ca_loop:                                ; tight: most pairs are rejected here
                ldd     O_SPR,x
                beq     ca_next
                ldaa    cy              ; within 24 rows of the shot?
                suba    O_Y,x
                cmpa    #48
                bcc     ca_next
                stx     ht_b            ; close: the full test
                jsr     hit_test
                ldx     ht_b
                bcc     ca_next
                ldx     ht_a            ; hit: remove both
                jsr     obj_erase
                ldx     ht_a
                ldd     #0
                std     O_SPR,x
                ldx     ht_b
                jsr     obj_erase
                ldx     ht_b
                ldd     #0
                std     O_SPR,x
                dec     alive
                ldd     hits
                addd    #1
                std     hits
                ldx     #fx_boom
                ldaa    #2
                jsr     snd_play
                bra     cs_next
ca_next:
                ldab    #OBJ_SIZE
                abx
                cpx     #aliens_end
                bne     ca_loop
cs_next:
                ldx     ht_a
                ldab    #OBJ_SIZE
                abx
                cpx     #shots_end
                bne     cs_loop
                ldx     #ship           ; bombs against the ship
                stx     ht_b
                ldx     #bombs
cb_loop:
                stx     ht_a
                ldd     O_SPR,x
                beq     cb_next
                ldaa    O_Y,x           ; quick reject: more than 24 rows apart
                suba    ship+O_Y
                adda    #24
                cmpa    #48
                bcc     cb_next
                jsr     hit_test
                bcc     cb_next
                ldx     ht_a
                jsr     obj_erase
                ldx     ht_a
                ldd     #0
                std     O_SPR,x
                inc     ouch
                ldx     #fx_ouch
                ldaa    #3
                jsr     snd_play
cb_next:
                ldx     ht_a
                ldab    #OBJ_SIZE
                abx
                cpx     #bombs_end
                bne     cb_loop
                rts

; ---------------------------------------------------------------- misc
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

; ---------------------------------------------------------------- data
; Flight paths (designed with tools/pathsim.py: they stay inside the side
; edges and wrap cleanly).  Jinks and U-turns are P_TURNBY.
path_loopL:                             ; loop left, jink, dive down-right;
                fcb     P_SPEED, 0      ; then the mirror image
                fcb     P_HEAD, 64
pl_rep:         fcb     P_FLY, 40, 0
                fcb     P_EVENT, 1
                fcb     P_FLY, 64, 4
                fcb     P_EVENT, 1
                fcb     P_TURNBY, -48
                fcb     P_FLY, 12, 0
                fcb     P_TURNBY, 48
                fcb     P_FLY, 16, -2
                fcb     P_EVENT, 1
                fcb     P_FLY, 60, 0
                fcb     P_HEAD, 64
                fcb     P_FLY, 40, 0
                fcb     P_EVENT, 1
                fcb     P_FLY, 64, -4
                fcb     P_EVENT, 1
                fcb     P_TURNBY, 48
                fcb     P_FLY, 12, 0
                fcb     P_TURNBY, -48
                fcb     P_FLY, 16, 2
                fcb     P_EVENT, 1
                fcb     P_FLY, 60, 0
                fcb     P_HEAD, 64
                fcb     P_GOTO
                fdb     pl_rep
path_loopR:                             ; the mirror image
                fcb     P_SPEED, 0
                fcb     P_HEAD, 64
pr_rep:         fcb     P_FLY, 40, 0
                fcb     P_EVENT, 1
                fcb     P_FLY, 64, -4
                fcb     P_EVENT, 1
                fcb     P_TURNBY, 48
                fcb     P_FLY, 12, 0
                fcb     P_TURNBY, -48
                fcb     P_FLY, 16, 2
                fcb     P_EVENT, 1
                fcb     P_FLY, 60, 0
                fcb     P_HEAD, 64
                fcb     P_FLY, 40, 0
                fcb     P_EVENT, 1
                fcb     P_FLY, 64, 4
                fcb     P_EVENT, 1
                fcb     P_TURNBY, -48
                fcb     P_FLY, 12, 0
                fcb     P_TURNBY, 48
                fcb     P_FLY, 16, -2
                fcb     P_EVENT, 1
                fcb     P_FLY, 60, 0
                fcb     P_HEAD, 64
                fcb     P_GOTO
                fdb     pr_rep
ZIG_R           macro                   ; zigzag down, drifting right
                fcb     P_HEAD, 40
                fcb     P_FLY, 30, 0
                fcb     P_EVENT, 1
                fcb     P_TURNBY, 48
                fcb     P_FLY, 24, 0
                fcb     P_TURNBY, -48
                fcb     P_FLY, 24, 0
                fcb     P_EVENT, 1
                fcb     P_TURNBY, 48
                fcb     P_FLY, 24, 0
                fcb     P_TURNBY, -48
                fcb     P_FLY, 24, 0
                fcb     P_EVENT, 1
                fcb     P_TURNBY, 24
                fcb     P_FLY, 40, 0
                endm
ZIG_L           macro                   ; zigzag down, drifting left
                fcb     P_HEAD, 88
                fcb     P_FLY, 30, 0
                fcb     P_EVENT, 1
                fcb     P_TURNBY, -48
                fcb     P_FLY, 24, 0
                fcb     P_TURNBY, 48
                fcb     P_FLY, 24, 0
                fcb     P_EVENT, 1
                fcb     P_TURNBY, -48
                fcb     P_FLY, 24, 0
                fcb     P_TURNBY, 48
                fcb     P_FLY, 24, 0
                fcb     P_EVENT, 1
                fcb     P_TURNBY, -24
                fcb     P_FLY, 40, 0
                endm
path_zigRL:                             ; sudden swerves, never upward
                fcb     P_SPEED, 0
pz_rep:         ZIG_R
                ZIG_L
                fcb     P_GOTO
                fdb     pz_rep
path_zigLR:
                fcb     P_SPEED, 0
pzl_rep:        ZIG_L
                ZIG_R
                fcb     P_GOTO
                fdb     pzl_rep
path_circle:                            ; two fast circles, a reversal jink,
                fcb     P_SPEED, 0      ; then a dive
                fcb     P_HEAD, 64
pc_rep:         fcb     P_FLY, 40, 0
                fcb     P_FLY, 64, 4
                fcb     P_EVENT, 1
                fcb     P_FLY, 64, 4
                fcb     P_TURNBY, 128
                fcb     P_FLY, 10, 0
                fcb     P_TURNBY, 128
                fcb     P_EVENT, 1
                fcb     P_FLY, 70, 0
                fcb     P_HEAD, 64
                fcb     P_GOTO
                fdb     pc_rep
path_circleR:                           ; the mirror image
                fcb     P_SPEED, 0
                fcb     P_HEAD, 64
pcr_rep:        fcb     P_FLY, 40, 0
                fcb     P_FLY, 64, -4
                fcb     P_EVENT, 1
                fcb     P_FLY, 64, -4
                fcb     P_TURNBY, 128
                fcb     P_FLY, 10, 0
                fcb     P_TURNBY, 128
                fcb     P_EVENT, 1
                fcb     P_FLY, 70, 0
                fcb     P_HEAD, 64
                fcb     P_GOTO
                fdb     pcr_rep

; Waves: descriptor, path; count, launch interval (frames), entry x
waves:
                fdb     saucer_dsc, path_loopL
                fcb     8, 12, 60
                fdb     dart_dsc, path_zigRL
                fcb     8, 10, 40
                fdb     orbiter_dsc, path_circle
                fcb     8, 12, 70
                fdb     saucer_dsc, path_loopR
                fcb     8, 12, 178
                fdb     dart_dsc, path_zigLR
                fcb     8, 10, 198
                fdb     orbiter_dsc, path_circleR
                fcb     8, 12, 168
                fdb     0

; Sound effects
fx_zap:         fcb     8, SND_TONE
                fdb     450, 70
                fcb     0
fx_boom:        fcb     4, SND_NOISE
                fdb     400, 0
                fcb     24, SND_NOISE
                fdb     600, 30
                fcb     0
fx_drop:        fcb     6, SND_TONE     ; a short falling blip
                fdb     700, 60
                fcb     0
fx_ouch:        fcb     20, SND_NOISE   ; a harsh buzz
                fdb     300, 10
                fcb     0

; Star field: 16 stars in three speed layers (rows per frame x 256)
#define NSTAR 18
star_tab:
i               set     0
                rept    NSTAR
                fdb     SCREEN
                fcb     0, 0
                if      i#3 == 0
                fcb     $40             ; far: 1/8 row a frame (updated every
                                        ; other frame: S_SPD is per 2 frames)
                elseif  i#3 == 1
                fcb     $80             ; middle: 1/4
                else
                fcb     $FF             ; near: 1/2
                endif
i               set     i+1
                endm
star_end:

; Objects, in priority order: aliens, bombs, shots, ship
objs:
aliens:
                rept    NALIEN
                fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                endm
aliens_end:
bombs:
                rept    NBOMB
                fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                endm
bombs_end:
shots:
                rept    NSHOT
                fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                endm
shots_end:
ship:
                fcb     (256-ship_W)/2&$FE, 0, 160, 0
                fdb     0, 0, ship_dsc
                fcb     0, 0, 0, 0, 0, 0
objs_end:

#include "frame.asm"
#include "sprite.asm"
#include "sprman.asm"
#include "flight.asm"
#include "sintab.asm"
#include "input.asm"
#include "sound.asm"
#include "stars.asm"
#include "waves_spr.inc"
