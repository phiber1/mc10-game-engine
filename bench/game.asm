; game.asm: the game prototype: title screen, waves, score, lives.
;
; An original vertical space shooter in artifact colour.  The title screen
; shows a colour sample (C swaps orange and blue, for real NTSC machines
; that power up in the other colour phase); SPACE starts.  "PLAYER 1" is
; shown at the start and after each lost ship.  Waves of aliens fly
; scripted paths, dive through the bottom and back in at the top, and
; drop bombs; shots make them explode.  Bombs or collisions destroy the
; ship; it comes back flashing (invulnerable) while ships remain.
;
;   W A S Z / arrows move, SPACE fires.     METER=1  CPU meter

#define OBJ_EXTRA 9                     /* flight (6) + animation (3) */
#define AN_BASE 6                       /* animation bytes after flight's */
#define FL_HALFX 1                      /* artifact colour: 128 pixels across */
#include "layout.inc"

#define NALIEN 10
#define NBOMB 6
#define NSHOT 3

SHIP_SPEEDX     equ     $0100           ; 1 artifact pixel (2 screen pixels)
SHIP_SPEED      equ     $0200           ; 2 rows a frame
SHOT_SPEED      equ     $0400
BOMB_SPEED      equ     $0300
SHIP_XMAX       equ     128-ship_W
AL_W            equ     saucer_W        ; all alien types share one box size
AL_H            equ     saucer_H
SHIP_YMIN       equ     120
SHIP_YMAX       equ     192-ship_H
FIRE_DELAY      equ     8
WAVE_GAP        equ     90              ; frames between waves
SPRAY_ON        equ     48              ; bombs may drop for 48 frames,
SPRAY_OFF       equ     80              ; then a quiet spell of 80
BOMB_GAP        equ     7               ; at least 7 frames between bombs

START_SHIPS     equ     3
DEAD_TIME       equ     110             ; frames from losing a ship to what's next
BANNER_TIME     equ     110             ; frames a banner stays up
OVER_TIME       equ     200             ; "GAME OVER"
INVULN_TIME     equ     120             ; flashing, untouchable, after a respawn
STATUS_EVERY    equ     12              ; redraw the status line every n frames
BANNER_ROW      equ     93
NAREAS          equ     4
MODE_PLAY       equ     0
MODE_SALUTE     equ     1               ; the victory salute
MODE_WARP       equ     2               ; blasting off, up behind the status bar
MODE_COAST      equ     3               ; gone: just the streaking stars
MODE_ARRIVE     equ     4               ; rising in from the bottom, braking
COAST_TIME      equ     70
SALUTE_TIME     equ     110
MAP_TIME        equ     130             ; frames the map screen stays up
MAP_SEG         equ     30              ; map rows per area
MAP_BOTTOM      equ     176             ; the map's bottom row
MAP_COL         equ     15              ; the map strip's byte column

                org     PROG_DP         ; direct page: the per-frame variables
cooldown        rmb     1
seed            rmb     2
obj             rmb     2               ; object being processed
obj2            rmb     2
wv_ptr          rmb     2               ; current wave
wv_left         rmb     1               ; aliens still to launch
wv_timer        rmb     1               ; frames to the next launch / wave
wv_x            rmb     1               ; entry x of the next launch
bomb_cd         rmb     1               ; frames until another bomb may drop
spray_t         rmb     1               ; bomb rhythm: spray, then quiet
alive           rmb     1               ; aliens on screen
cy              rmb     1               ; collide: the shot's row + 24
dead            rmb     1               ; nonzero while the ship is lost
invuln          rmb     1               ; frames of invulnerability left
mode            rmb     1               ; MODE_PLAY, MODE_SALUTE, MODE_WARP ...
warpf           rmb     1               ; star updates per frame
banner_t        rmb     1               ; frames the banner stays up
status_t        rmb     1
area_done       rmb     1               ; the area's waves are all launched
                DP_CHECK

                org     BSS             ; ordinary RAM: the rest
score           rmb     3               ; BCD, 6 digits
lives           rmb     1
dead_t          rmb     1
gover           rmb     1               ; game over: back to the title
col_o           rmb     1               ; the orange and blue masks (swapped
col_b           rmb     1               ; by C on the title screen)
keyprev         rmb     1
col_ok          rmb     1               ; the colours were confirmed (first game)
area            rmb     1               ; 0-3
wv_index        rmb     1               ; waves done in this area (the map)
mode_t          rmb     1
wp_wrapped      rmb     1
banner_p        rmb     2               ; the banner being shown
bu_s            rmb     2
mp_t            rmb     1
mp_a            rmb     2
BSS_USED        equ     *
                BSS_CHECK

                org     CODE
start:
                sei
                lds     #STACK_TOP
                ldaa    #$FF
                staa    P1DDR
                ldaa    #VDG_RG6|VDG_CSS
                staa    VDG
                staa    vdg_shadow
                ldx     #PROG_DP        ; clear all of this program's variables
-               clr     0,x
                inx
                cpx     #ht_al
                bne     -
                ldx     #BSS
-               clr     0,x
                inx
                cpx     #BSS_USED
                bne     -
                ldd     FRC
                orab    #1
                std     seed
                std     st_seed
                ldaa    #TXT_ORANGE
                staa    col_o
                ldaa    #TXT_BLUE
                staa    col_b
                ldx     #objs
                stx     obj_first
                ldx     #objs_end
                stx     obj_end
                jsr     frame_init

; ---------------------------------------------------------------- title
title:
                jsr     snd_stop
                jsr     title_draw
t_loop:
                jsr     frame_wait
                jsr     snd_frame
                jsr     kbd_read
                tst     col_ok          ; asked only before the first game
                bne     +
                jsr     key_c           ; C: swap the colours
                cmpa    keyprev
                beq     +
                staa    keyprev
                tsta
                beq     +
                ldx     #all_sprites
                jsr     col_swap
                ldaa    col_o
                ldab    col_b
                staa    col_b
                stab    col_o
                jsr     title_draw
+               ldaa    joy
                bita    #J_FIRE
                beq     t_loop

; ---------------------------------------------------------------- a game
game_start:
                inc     col_ok          ; the colours are settled now
                jsr     cls
                jsr     stars_init
                ldx     #objs           ; empty every object slot
-               clr     0,x
                inx
                cpx     #ship
                bne     -
                ldd     #0
                std     score
                staa    score+2
                ldaa    #START_SHIPS
                staa    lives
                clr     alive
                clr     dead
                clr     invuln
                clr     gover
                clr     bomb_cd
                clr     spray_t
                ldaa    #FIRE_DELAY
                staa    cooldown
                ldaa    #1
                staa    status_t
                jsr     ship_place
                clr     area
                clr     mode
                ldaa    #1
                staa    warpf
                ldx     #fx_start       ; the start fanfare, over the map
                ldaa    #9
                jsr     snd_play
                jsr     area_begin
                jsr     map_show
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
                jsr     victory_check
                ldab    warpf           ; stars first: sprites cover them
-               pshb                    ; (several updates a frame at warp)
                jsr     stars_update
                pulb
                decb
                bne     -
                jsr     spr_update_all
                ldaa    mode            ; blasting off: the status bar is a
                cmpa    #MODE_WARP      ; solid band in front of the ship
                bne     +
                jsr     status_band
+               jsr     banner_update
                jsr     status_update
                ldaa    #$BB
                DBGA
                METER_OFF
                ldaa    gover           ; game over and its banner done?
                beq     loop
                ldaa    banner_t
                bne     loop
                jmp     title

; ---------------------------------------------------------------- waves
; A wave: fdb descriptor, script; fcb count, launch interval, entry x,
; x step (added to the entry x after each launch, signed: spreads the
; wave across the screen).  The table ends with fdb 0 (back to the start).
W_DESC          equ     0
W_PATH          equ     2
W_COUNT         equ     4
W_GAP           equ     5
W_X             equ     6
W_XSTEP         equ     7
W_SIZE          equ     8

wave_begin:
                ldx     wv_ptr
                ldaa    W_X,x
                staa    wv_x
                ldaa    W_COUNT,x
                staa    wv_left
                ldaa    #1
                staa    wv_timer
                rts

wave_logic:
                tst     mode
                bne     wl_done
                tst     area_done
                bne     wl_done
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
                ldab    W_GAP,x
                stab    wv_timer
                ldaa    wv_x            ; this alien's entry x; the next one's
                tab                     ; is W_XSTEP further across
                addb    W_XSTEP,x
                stab    wv_x
                ldx     obj
                staa    O_X,x           ; enter just above the top
                clr     O_XF,x
                ldab    #256-AL_H
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
                inc     wv_index
                ldd     0,x
                bne     +
                inc     area_done       ; the end of the area's waves
                rts
+               stx     wv_ptr
                ldaa    W_X,x
                staa    wv_x
                ldaa    W_COUNT,x
                staa    wv_left
                ldaa    #WAVE_GAP
                staa    wv_timer
                rts

; ---------------------------------------------------------------- aliens
aliens_logic:
                ldaa    bomb_cd         ; bomb rhythm
                beq     +
                dec     bomb_cd
+               inc     spray_t
                ldaa    spray_t
                cmpa    #SPRAY_ON+SPRAY_OFF
                bcs     +
                clr     spray_t
+               ldaa    ship+O_X        ; the aim target: the ship
                staa    fl_tx
                ldaa    ship+O_Y
                staa    fl_ty
                ldx     #aliens
al_loop:
                stx     obj
                ldd     O_SPR,x
                beq     al_next
                ldd     AN_PTR,x        ; exploding?
                beq     al_live
                ldd     O_X,x           ; drift, but not off the sides
                addd    O_DX,x
                cmpa    #128-AL_W
                bcs     +
                ldd     #0
                std     O_DX,x
+               jsr     obj_anim_step   ; next frame; frees the slot at the end
                bra     al_next
al_live:
                jsr     fl_step
                ldaa    fl_event        ; event 1: drop a bomb
                cmpa    #1
                bne     +
                jsr     drop_bomb
+               ldx     obj             ; safety: mirror off the sides
                ldd     O_X,x
                addd    O_DX,x
                cmpa    #128-AL_W
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
                ldaa    #256-AL_H
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
                ldaa    bomb_cd         ; too soon after the last bomb?
                bne     db_done
                ldaa    spray_t         ; in a spray window?
                cmpa    #SPRAY_ON
                bcc     db_done
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
                adda    #saucer_PADX+3-bomb_PADX
                ldab    O_Y,x
                addb    #saucer_H-saucer_PADY-bomb_PADY
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
                ldaa    #BOMB_GAP
                staa    bomb_cd
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
                ldaa    mode
                beq     sl_play
                cmpa    #MODE_SALUTE
                bne     sl_warp
                ldx     #ship           ; the salute: hold still
                ldd     #0
                std     O_DX,x
                std     O_DY,x
                dec     mode_t
                bne     sl_ret
                jmp     warp_begin
sl_warp:        cmpa    #MODE_WARP
                bne     sl_nwarp
                jmp     warp_logic
sl_nwarp:       cmpa    #MODE_COAST
                bne     sl_ncoast
                jmp     coast_logic
sl_ncoast:      jmp     arrive_logic
sl_play:        tst     dead
                beq     sl_alive
                ldx     #ship           ; lost: let the explosion play out
                ldd     AN_PTR,x
                beq     +
                jsr     obj_anim_step
+               dec     dead_t
                bne     sl_ret
                tst     lives
                beq     sl_over
                jsr     map_show        ; where we are
                clr     dead            ; another ship
                jsr     ship_place
                ldaa    #INVULN_TIME
                staa    invuln
                ldx     #fx_life        ; a fresh ship's phrase
                ldaa    #9
                jmp     snd_play
sl_over:
                inc     gover
                ldd     #s_gameover
                jsr     banner_show
                ldaa    #OVER_TIME
                staa    banner_t
sl_ret:         rts
sl_alive:
                ldaa    invuln          ; flashing after a respawn
                beq     sl_move
                dec     invuln
                ldx     #ship
                ldaa    invuln
                beq     +               ; the end: visible
                bita    #4
                beq     ++              ; every 4 frames: hide ...
+               ldd     #ship_dsc       ; ... or show
                std     O_SPR,x
                bra     sl_move
+               ldd     O_SPR,x
                beq     sl_move
                jsr     obj_erase
                ldx     #ship
                ldd     #0
                std     O_SPR,x
sl_move:
                ldx     #ship
                ldd     #0
                std     O_DX,x
                std     O_DY,x
                ldaa    joy
                bita    #J_LEFT
                beq     +
                ldd     #-SHIP_SPEEDX
                std     O_DX,x
                ldaa    joy
+               bita    #J_RIGHT
                beq     +
                ldd     #SHIP_SPEEDX
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
sl_done:        ldd     O_SPR,x         ; hidden (flashing): the sprite manager
                bne     +               ; won't move it, so move it here
                ldd     O_X,x
                addd    O_DX,x
                std     O_X,x
                ldd     O_Y,x
                addd    O_DY,x
                std     O_Y,x
+               rts

ship_place:                             ; a fresh ship at the bottom centre
                ldx     #ship
                ldaa    #(128-ship_W)/2
                staa    O_X,x
                ldaa    #160
                staa    O_Y,x
                clr     O_XF,x
                clr     O_YF,x
                ldd     #0
                std     O_DX,x
                std     O_DY,x
                std     AN_PTR,x
                ldd     #ship_dsc
                std     O_SPR,x
                rts

; the ship is hit (unless already lost or flashing)
ship_hit:
                tst     mode            ; untouchable during the salute and warp
                bne     +
                tst     dead
                bne     +
                tst     invuln
                bne     +
                inc     dead
                ldaa    #DEAD_TIME
                staa    dead_t
                dec     lives
                ldaa    #1
                staa    status_t
                ldx     #ship
                ldd     #0
                std     O_DX,x
                std     O_DY,x
                ldd     #anim_shipboom
                jsr     obj_anim_start
                ldx     #fx_shipboom
                ldaa    #3
                jmp     snd_play
+               rts

; ---------------------------------------------------------------- shots
fire_logic:
                tst     dead
                bne     fl_done
                tst     mode
                bne     fl_done
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
+               ldaa    ship+O_X        ; the nose: column 3 of the ship
                adda    #ship_PADX+3-shot_PADX
                staa    O_X,x
                ldaa    ship+O_Y
                adda    #ship_PADY-shot_H+shot_PADY
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
                ldd     AN_PTR,x        ; already exploding
                bne     ca_next
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
                ldx     ht_b            ; the alien explodes, drifting on at
                asr     O_DX,x          ; half its speed
                ror     O_DX+1,x
                asr     O_DY,x
                ror     O_DY+1,x
                ldd     #anim_boom
                jsr     obj_anim_start
                dec     alive
                jsr     score_10
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
                tst     dead            ; bombs against the ship
                bne     cb_skip
                ldx     #ship
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
                jsr     ship_hit
cb_next:
                ldx     ht_a
                ldab    #OBJ_SIZE
                abx
                cpx     #bombs_end
                bne     cb_loop
cb_skip:
                tst     dead            ; aliens against the ship
                bne     cc_done
                tst     invuln
                bne     cc_done
                ldx     #ship
                stx     ht_b
                ldaa    O_Y,x
                adda    #24
                staa    cy
                ldx     #aliens
cc_loop:
                ldd     O_SPR,x
                beq     cc_next
                ldd     AN_PTR,x
                bne     cc_next
                ldaa    cy
                suba    O_Y,x
                cmpa    #48
                bcc     cc_next
                stx     ht_a
                jsr     hit_test
                ldx     ht_a
                bcc     cc_next
                ldd     #anim_boom      ; collision: both explode
                jsr     obj_anim_start
                dec     alive
                jsr     score_10
                jmp     ship_hit
cc_next:
                ldab    #OBJ_SIZE
                abx
                cpx     #aliens_end
                bne     cc_loop
cc_done:        rts

; ---------------------------------------------------------------- areas
area_begin:                             ; start the waves of area `area`
                ldab    area
                aslb
                ldx     #areas
                abx
                ldx     0,x
                stx     wv_ptr
                jsr     wave_begin
                ldaa    #60
                staa    wv_timer
                clr     area_done
                clr     wv_index
                rts

; The area is won when all its waves are launched and every alien is gone
; (later: when its boss is destroyed).
victory_check:
                tst     mode
                bne     vc_done
                tst     dead
                bne     vc_done
                tst     area_done
                beq     vc_done
                tst     alive
                bne     vc_done
                ldaa    #MODE_SALUTE
                staa    mode
                ldaa    #SALUTE_TIME
                staa    mode_t
                jsr     score_1000
                ldx     #fx_salute
                ldaa    #9
                jsr     snd_play
                ldd     #s_cleared
                jmp     banner_show
vc_done:        rts

; ---------------------------------------------------------------- warp
warp_begin:
                ldaa    #MODE_WARP
                staa    mode
                clr     wp_wrapped
                ldx     #ship
                jsr     obj_erase       ; (the flame version is a new shape)
                ldx     #ship
                ldd     #shipw1_dsc
                std     O_SPR,x
                ldx     #fx_warp
                ldaa    #8
                jmp     snd_play

warp_logic:                             ; blast off: up, behind the status bar
                ldx     #ship
                bsr     wp_flame
                ldd     O_DY,x          ; accelerate to 4 rows a frame
                subd    #$0018
                cmpa    #$FC
                bge     +
                ldd     #$FC00
+               std     O_DY,x
                ldaa    frame_count     ; the stars speed up
                anda    #7
                bne     +
                ldaa    warpf
                cmpa    #6
                bcc     +
                inc     warpf
+               ldaa    O_Y,x           ; wholly above the top (-32..-22)?
                cmpa    #224
                bcs     wp_r
                cmpa    #235
                bcc     wp_r
                jsr     obj_erase       ; gone
                ldx     #ship
                ldd     #0
                std     O_SPR,x
                std     O_DY,x
                ldaa    #MODE_COAST
                staa    mode
                ldaa    #COAST_TIME
                staa    mode_t
wp_r:           rts

wp_flame:                               ; X = ship: the afterburner flickers
                ldaa    frame_count
                anda    #2
                beq     +
                ldd     #shipw2_dsc
                bra     ++
+               ldd     #shipw1_dsc
+               std     O_SPR,x
                rts

coast_logic:                            ; just stars for a moment, then the
                dec     mode_t          ; next area: the map, then the ship
                bne     wp_r            ; rises in from the bottom
                inc     area
                ldaa    area
                cmpa    #NAREAS
                bcs     +
                clr     area            ; after the last: round again
+               jsr     area_begin
                jsr     map_show
                ldx     #ship
                ldaa    #(128-ship_W)/2
                staa    O_X,x
                ldaa    #208            ; in the bottom gutter
                staa    O_Y,x
                clr     O_XF,x
                clr     O_YF,x
                ldd     #0
                std     O_DX,x
                ldd     #$FC00
                std     O_DY,x
                bsr     wp_flame
                ldaa    #4
                staa    warpf
                ldaa    #MODE_ARRIVE
                staa    mode
                rts

arrive_logic:                           ; rise in and brake to a stop
                ldx     #ship
                bsr     wp_flame
                ldaa    O_Y,x
                cmpa    #200
                bcc     wp_r            ; still below the screen
                ldaa    frame_count     ; the stars slow down
                anda    #3
                bne     +
                ldaa    warpf
                cmpa    #1
                beq     +
                dec     warpf
+               ldd     O_DY,x
                addd    #$0028
                bmi     +
                jsr     obj_erase       ; stopped: back to the normal ship
                ldx     #ship
                ldd     #ship_dsc
                std     O_SPR,x
                ldd     #0
                std     O_DY,x
                ldaa    #1
                staa    warpf
                clr     mode            ; play: the area's waves begin
                ldaa    #1
                staa    status_t
                rts
+               std     O_DY,x
                rts

; ---------------------------------------------------------------- map
; The map screen: PLAYER 1, the area, a strip of the areas with their
; checkpoints, and the ship at its progress.  Play is paused meanwhile
; (sound goes on).
map_show:
                jsr     cls
                ldaa    #TXT_WHITE
                staa    txt_col
                ldx     #TXT_AT(16,12)
                ldd     #s_player
                jsr     txt_str
                ldaa    col_o
                staa    txt_col
                ldx     #TXT_AT(28,13)
                ldd     #s_area
                jsr     txt_str
                ldaa    area
                adda    #'1'
                jsr     txt_char
                ldx     #TXT_AT(MAP_BOTTOM-NAREAS*MAP_SEG,MAP_COL) ; the strip
-               ldaa    col_b
                anda    #$30
                staa    0,x
                ldab    #ROW_BYTES
                abx
                cpx     #TXT_AT(MAP_BOTTOM,MAP_COL)
                bne     -
                clra                    ; the areas' labels
                bsr     map_label
                ldaa    #1
                bsr     map_label
                ldaa    #2
                bsr     map_label
                ldaa    #3
                bsr     map_label
                ldaa    col_o           ; a checkpoint at the top of each area
                staa    txt_col
                ldx     #TXT_AT(MAP_BOTTOM-1*MAP_SEG,MAP_COL)
                bsr     map_mark
                ldx     #TXT_AT(MAP_BOTTOM-2*MAP_SEG,MAP_COL)
                bsr     map_mark
                ldx     #TXT_AT(MAP_BOTTOM-3*MAP_SEG,MAP_COL)
                bsr     map_mark
                ldx     #TXT_AT(MAP_BOTTOM-4*MAP_SEG,MAP_COL)
                bsr     map_mark
                ldaa    area            ; the ship: area base + progress
                inca
                ldab    #MAP_SEG
                mul
                stab    mp_t
                ldaa    #MAP_BOTTOM+MAP_SEG
                suba    mp_t
                suba    #ship_H-ship_PADY
                ldab    wv_index        ; 6 rows per wave
                aslb
                stab    mp_t
                aslb
                addb    mp_t
                stab    mp_t
                suba    mp_t
                tab
                ldaa    #MAP_COL*4-3    ; centred on the strip
                ldx     #ship_hr
                jsr     spr_art
                ldaa    #MAP_TIME
                staa    mp_t
-               jsr     frame_wait
                jsr     snd_frame
                dec     mp_t
                bne     -
                jsr     cls             ; back to play: everything redraws
                jsr     stars_init
                ldaa    #1
                staa    status_t
                rts

map_mark:                               ; X = row start: a checkpoint marker
                ldaa    #$FC            ; (a 3-pixel bar, 3 rows)
                anda    col_o
                staa    0,x
                staa    ROW_BYTES,x
                staa    2*ROW_BYTES,x
                ldab    #2              ; and BOSS beside it
                abx
                ldd     #s_boss
                jmp     txt_str

; A = area number (0-3): its label to the left of the strip, white for
; the current area, blue for the others
map_label:
                psha
                ldab    col_b
                cmpa    area
                bne     +
                ldab    #TXT_WHITE
+               stab    txt_col
                inca                    ; row = bottom - (n + 1/2) segments
                ldab    #MAP_SEG
                mul
                subb    #MAP_SEG/2
                negb
                addb    #MAP_BOTTOM-2
                clra
                aslb                    ; D = row * 32
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola
                addd    #SCREEN+MAP_COL-7
                std     mp_a
                ldx     mp_a
                ldd     #s_area
                jsr     txt_str
                pula
                adda    #'1'
                jmp     txt_char

score_1000:                             ; score += 1000 (BCD)
                ldaa    score+1
                adda    #$10
                daa
                staa    score+1
                ldaa    score
                adca    #0
                daa
                staa    score
                ldaa    #1
                staa    status_t
                rts

; ---------------------------------------------------------------- score
score_10:                               ; score += 10 (BCD)
                ldaa    score+2
                adda    #$10
                daa
                staa    score+2
                ldaa    score+1
                adca    #0
                daa
                staa    score+1
                ldaa    score
                adca    #0
                daa
                staa    score
                ldaa    #1              ; show it at once
                staa    status_t
                rts

; The status line, redrawn every STATUS_EVERY frames (sprites and stars
; fly across it): SCORE 000000 ... SHIPS 3
status_update:
                dec     status_t
                bne     su_done
                ldaa    #STATUS_EVERY
                staa    status_t
                ldaa    col_o
                staa    txt_col
                ldx     #TXT_AT(1,1)
                ldd     #s_score
                jsr     txt_str
                ldaa    #TXT_WHITE
                staa    txt_col
                ldx     #TXT_AT(1,7)
                ldaa    #3
                staa    tx_n
                ldd     #score
                jsr     txt_bcd
                ldaa    col_o
                staa    txt_col
                ldx     #TXT_AT(1,24)
                ldd     #s_ships
                jsr     txt_str
                ldaa    #TXT_WHITE
                staa    txt_col
                ldaa    lives
                adda    #'0'
                ldx     #TXT_AT(1,30)
                jsr     txt_char
su_done:        rts

status_band:                            ; clear rows 0-7, then the status line
                ldx     #SCREEN
                clra
                clrb
-               std     0,x
                std     2,x
                inx
                inx
                inx
                inx
                cpx     #SCREEN+8*ROW_BYTES
                bne     -
                ldaa    #1
                staa    status_t
                jmp     status_update

; ---------------------------------------------------------------- banner
; D = banner (fdb screen address, then the text): show it for BANNER_TIME
banner_show:
                std     banner_p
                ldaa    #BANNER_TIME
                staa    banner_t
                rts

banner_update:                          ; redraw it each frame while up (the
                ldaa    banner_t        ; aliens fly across it), clear it at
                beq     bu_done         ; the end
                dec     banner_t
                beq     bu_clear
                ldaa    #TXT_WHITE
                staa    txt_col
                ldx     banner_p
                ldd     0,x
                pshb
                psha
                inx
                inx
                stx     bu_s
                pulx
                ldd     bu_s
                jmp     txt_str
bu_clear:
                ldx     #TXT_AT(BANNER_ROW,0)
                clra
                clrb
-               std     0,x
                inx
                inx
                cpx     #TXT_AT(BANNER_ROW+5,0)
                bne     -
bu_done:        rts

; ---------------------------------------------------------------- title
title_draw:
                jsr     cls
                ldaa    col_o
                staa    txt_col
                ldx     #TXT_AT(30,9)
                ldd     #s_title
                jsr     txt_str2
                ldaa    #TXT_WHITE
                staa    txt_col
                ldx     #TXT_AT(50,5)
                ldd     #s_sub
                jsr     txt_str
                tst     col_ok          ; the colour sample: only before the
                bne     td_nosample     ; first game
                ldx     #TXT_AT(92,3)   ; a block that should look orange
                ldab    #10
-               ldaa    col_o
                staa    0,x
                staa    1,x
                staa    2,x
                pshb
                ldab    #ROW_BYTES
                abx
                pulb
                decb
                bne     -
                ldx     #TXT_AT(92,7)
                ldd     #s_sample1
                jsr     txt_str
                ldx     #TXT_AT(100,7)
                ldd     #s_sample2
                jsr     txt_str
td_nosample:
                ldaa    col_b
                staa    txt_col
                ldx     #TXT_AT(140,6)
                ldd     #s_start
                jsr     txt_str
                ldaa    #TXT_WHITE
                staa    txt_col
                ldx     #TXT_AT(165,2)
                ldd     #s_keys
                jmp     txt_str

key_c:                                  ; A = 1 while C is held
                ldaa    #$FF-$08        ; column 3: C is row 0
                staa    P1DAT
                ldaa    KBD
                ldab    #$FF
                stab    P1DAT
                anda    #1
                eora    #1
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

; Areas: each a list of waves (descriptor, path; count, launch interval,
; entry x, x step), ending with fdb 0.  At most 5 waves an area (the map
; shows 6 rows per wave).  Later areas launch faster and mix more.
areas:          fdb     area1, area2, area3, area4
area1:
                fdb     saucer_dsc, path_loopL
                fcb     6, 14, 30, 0
                fdb     dart_dsc, path_zigRL
                fcb     6, 16, 21, 12
                fdb     orbiter_dsc, path_circle
                fcb     6, 14, 35, 0
                fdb     0
area2:
                fdb     saucer_dsc, path_loopR
                fcb     8, 12, 89, 0
                fdb     dart_dsc, path_zigLR
                fcb     8, 16, 103, -12
                fdb     orbiter_dsc, path_circleR
                fcb     8, 12, 84, 0
                fdb     saucer_dsc, path_loopL
                fcb     8, 12, 30, 0
                fdb     0
area3:
                fdb     dart_dsc, path_zigRL
                fcb     8, 12, 15, 12
                fdb     orbiter_dsc, path_circle
                fcb     8, 10, 35, 0
                fdb     saucer_dsc, path_loopR
                fcb     8, 10, 89, 0
                fdb     dart_dsc, path_zigLR
                fcb     8, 12, 103, -12
                fdb     0
area4:
                fdb     orbiter_dsc, path_circleR
                fcb     8, 9, 84, 0
                fdb     dart_dsc, path_zigRL
                fcb     8, 10, 15, 12
                fdb     saucer_dsc, path_loopL
                fcb     8, 9, 30, 0
                fdb     orbiter_dsc, path_circle
                fcb     8, 9, 35, 0
                fdb     dart_dsc, path_zigLR
                fcb     8, 10, 103, -12
                fdb     0

; Explosion: frames of 4 game frames each, then the slot is freed
anim_boom:      fdb     boom1_dsc
                fcb     4
                fdb     boom2_dsc
                fcb     4
                fdb     boom3_dsc
                fcb     5
                fdb     boom4_dsc
                fcb     6
                fdb     0

; Text.  Banners: fdb screen address, then the text (centred).
s_score:        fcc     "SCORE"
                fcb     0
s_ships:        fcc     "SHIPS"
                fcb     0
s_player1:      fdb     TXT_AT(BANNER_ROW,12)
                fcc     "PLAYER 1"
                fcb     0
s_gameover:     fdb     TXT_AT(BANNER_ROW,11)
                fcc     "GAME OVER"
                fcb     0
s_player:       fcc     "PLAYER 1"
                fcb     0
s_area:         fcc     "AREA "
                fcb     0
s_boss:         fcc     "BOSS"
                fcb     0
s_cleared:      fdb     TXT_AT(BANNER_ROW,10)
                fcc     "AREA CLEARED"
                fcb     0
s_title:        fcc     "STARFALL"      ; a working title
                fcb     0
s_sub:          fcc     "A TEST OF THE MC-10 ENGINE"
                fcb     0
s_sample1:      fcc     "THIS BLOCK SHOULD BE"
                fcb     0
s_sample2:      fcc     "ORANGE: C SWAPS COLOURS"
                fcb     0
s_start:        fcc     "PRESS SPACE TO START"
                fcb     0
s_keys:         fcc     "ARROWS/WASZ MOVE  SPACE FIRES"
                fcb     0

; Every artifact sprite, for the colour swap
all_sprites:    fdb     ship_dsc, saucer_dsc, dart_dsc, orbiter_dsc, shot_dsc
                fdb     bomb_dsc, boom1_dsc, boom2_dsc, boom3_dsc, boom4_dsc
                fdb     shipw1_dsc, shipw2_dsc, 0

; The ship's explosion: bigger and longer than an alien's
anim_shipboom:  fdb     boom1_dsc
                fcb     6
                fdb     boom2_dsc
                fcb     6
                fdb     boom3_dsc
                fcb     6
                fdb     boom2_dsc
                fcb     5
                fdb     boom3_dsc
                fcb     8
                fdb     boom4_dsc
                fcb     14
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
; Jingles (priority 9: nothing interrupts them)
fx_start:                               ; the start fanfare, ~1.6 s
                NOTE    N_C5, 7
                NOTE    N_E5, 7
                NOTE    N_G5, 7
                NOTE    N_C6, 14
                REST    4
                NOTE    N_A5, 7
                NOTE    N_B5, 7
                NOTE    N_C6, 28
                fcb     0
fx_life:                                ; a fresh ship, ~0.8 s
                NOTE    N_G5, 6
                NOTE    N_A5, 6
                NOTE    N_B5, 6
                NOTE    N_D6, 22
                fcb     0
fx_salute:                              ; the victory salute, ~1.8 s
                NOTE    N_G5, 7
                NOTE    N_G5, 5
                NOTE    N_G5, 5
                NOTE    N_C6, 14
                REST    4
                NOTE    N_E6, 8
                NOTE    N_D6, 8
                NOTE    N_E6, 8
                NOTE    N_C6, 30
                fcb     0
fx_warp:                                ; the afterburner: a rising roar
                fcb     40, SND_NOISE
                fdb     900, -12
                fcb     60, SND_NOISE
                fdb     420, 0
                fcb     0
fx_shipboom:    fcb     6, SND_NOISE    ; the ship: a long, deep explosion
                fdb     300, 0
                fcb     50, SND_NOISE
                fdb     500, 20
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
                fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                endm
aliens_end:
bombs:
                rept    NBOMB
                fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                endm
bombs_end:
shots:
                rept    NSHOT
                fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                endm
shots_end:
ship:
                fcb     (128-ship_W)/2, 0, 160, 0
                fdb     0, 0, ship_dsc
                fcb     0, 0, 0, 0, 0, 0, 0, 0, 0
objs_end:

#include "frame.asm"
#include "sprite.asm"
#include "sprman.asm"
#include "flight.asm"
#include "sintab.asm"
#include "input.asm"
#include "sound.asm"
#include "stars.asm"
#include "text.asm"
#include "colswap.asm"
#include "game_spr.inc"
