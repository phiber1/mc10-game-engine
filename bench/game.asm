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

#define OBJ_EXTRA 10                    /* flight (7) + animation (3) */
#define AN_BASE 7                       /* animation bytes after flight's */
#define FL_HALFX 1                      /* artifact colour: 128 pixels across */
#define STAR_TOP 7                      /* stars stay below the status bar */
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
MAX_ALIVE       equ     8               ; live aliens on screen at most
SPRAY_ON        equ     48              ; bombs may drop for 48 frames,
SPRAY_OFF       equ     80              ; then a quiet spell of 80
BOMB_GAP        equ     7               ; at least 7 frames between bombs
FF_HOPL         equ     $02             ; F_FLAGS: back in at a random x (event 2)
FF_HOPR         equ     $04             ; ... for right circles (event 3)
FF_WAIT1        equ     $08             ; F_FLAGS bits 3-7: a hidden wait (count)
HOP_WAIT        equ     10              ; ... after a hop: 10-25 counts of 4 frames
AIM_W           equ     2               ; aimed drops: within 2 pixels of the nose
BOMB_WARN       equ     36              ; bombs start 36 rows above the ship (12 frames)

START_SHIPS     equ     3
DEAD_TIME       equ     110             ; frames from losing a ship to what's next
BANNER_TIME     equ     110             ; frames a banner stays up
OVER_TIME       equ     200             ; "GAME OVER"
INVULN_TIME     equ     120             ; flashing, untouchable, after a respawn
BANNER_ROW      equ     93
BAND            equ     7               ; the status bar: rows 0-6, in front of
                                        ; everything
NAREAS          equ     4
MODE_PLAY       equ     0
MODE_SALUTE     equ     1               ; the victory salute
MODE_WARP       equ     2               ; blasting off, up behind the status bar
MODE_COAST      equ     3               ; gone: just the streaking stars
MODE_ARRIVE     equ     4               ; rising in from the bottom, braking
COAST_TIME      equ     70
BS_NONE         equ     0               ; boss states
BS_ENTER        equ     1               ; descending from under the status bar
BS_FIGHT        equ     2
BS_DYING        equ     3               ; exploding
BS_DEFEATED     equ     4               ; gone: the area is won
BOSS_Y          equ     24              ; where it stops descending
BOSS_SPEED      equ     $0080           ; half a pixel a frame
BOSS_DESCEND    equ     $0040           ; a slow, ominous descent
WARN_TIME       equ     240             ; the warning: siren and flashing banner
BOSS_XMIN       equ     4               ; sway range without envoys ...
BOSS_XMAX       equ     128-boss1_W-4
ENV_DXL         equ     envoy_W+2       ; envoys' boxes: left of the hull ...
ENV_DXR         equ     boss1_W+2       ; ... and right of it
ENV_DY          equ     2
BOSS_EXMIN      equ     ENV_DXL+2       ; ... and with them (they stay on
BOSS_EXMAX      equ     128-ENV_DXR-envoy_W-2 ; screen)
ENV_FIRE        equ     16              ; frames between envoy bombs
CORE_DX         equ     boss1_PADX+10-core_PADX ; the core's box in the boss's
CORE_DY         equ     boss1_PADY+4-core_PADY  ; opening
BOSS_FIRE       equ     22              ; frames between cannon shots
DIE_TIME        equ     120             ; frames of explosions
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
col_par         rmb     1               ; collide: frame parity
cs_par          rmb     1               ; collide: shot parity
dead            rmb     1               ; nonzero while the ship is lost
invuln          rmb     1               ; frames of invulnerability left
mode            rmb     1               ; MODE_PLAY, MODE_SALUTE, MODE_WARP ...
warpf           rmb     1               ; star updates per frame
banner_t        rmb     1               ; frames the banner stays up
status_t        rmb     1
area_done       rmb     1               ; the area's waves are all launched
boss_state      rmb     1               ; BS_NONE ... BS_DEFEATED
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
banner_fl       rmb     1               ; the banner flashes
mp_t            rmb     1
mp_a            rmb     2
bm_xy           rmb     2               ; bomb_at: the bomb's position
bm_dx           rmb     2               ; and its sideways speed
rnd_n           rmb     1               ; rnd: steps left
ba_xy           rmb     2               ; boss_attach scratch
ba_dx           rmb     2
ba_dy           rmb     2
boss_hp         rmb     1               ; core hits left
boss_t          rmb     1               ; boss timer (bombs, dying)
core_flash      rmb     1               ; frames the core stays white
boss_side       rmb     1               ; which cannon fires next
wv_start        rmb     2               ; the escort list (it loops)
env_left        rmb     1               ; envoys still flying (shield up)
env_hp          rmb     2               ; hits left: left envoy, right envoy
env_t           rmb     1               ; envoy bomb timer
env_side        rmb     1               ; which envoy bombs next
boss_xmin       rmb     1               ; the hull's sway range
boss_xmax       rmb     1
status_buf      rmb     BAND*ROW_BYTES  ; the status bar, ready to copy
sr_sp           rmb     2
sr_bsp          rmb     2
sr_dst          rmb     2
sr_n            rmb     1
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
start_b1:       clr     0,x
                inx
                cpx     #ht_al
                bne     start_b1
                ldx     #BSS
start_b2:       clr     0,x
                inx
                cpx     #BSS_USED
                bne     start_b2
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
                bne     t_loop_f1
                jsr     key_c           ; C: swap the colours
                cmpa    keyprev
                beq     t_loop_f1
                staa    keyprev
                tsta
                beq     t_loop_f1
                ldx     #all_sprites
                jsr     col_swap
                ldaa    col_o
                ldab    col_b
                staa    col_b
                stab    col_o
                jsr     title_draw
t_loop_f1:      ldaa    joy
                bita    #J_FIRE
                beq     t_loop

; ---------------------------------------------------------------- a game
game_start:
                inc     col_ok          ; the colours are settled now
                jsr     cls
                jsr     stars_init
                ldx     #objs           ; empty every object slot
game_start_b1:  clr     0,x
                inx
                cpx     #ship
                bne     game_start_b1
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
                ldaa    #BAND
                staa    sm_band
                jsr     ship_place
                clr     area
                clr     mode
                clr     boss_state
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
                jsr     boss_logic
                jsr     bombs_logic
                jsr     shots_logic
                jsr     collide
                jsr     victory_check
                ldab    warpf           ; stars first: sprites cover them
loop_b1:        pshb                    ; (several updates a frame at warp)
                jsr     stars_update
                pulb
                decb
                bne     loop_b1
                jsr     spr_update_all
                jsr     status_update   ; render the bar if it changed ...
                jsr     status_repair   ; ... and put it in front of sprites
                jsr     banner_update
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
                ldaa    alive           ; at most MAX_ALIVE flying at once:
                cmpa    #MAX_ALIVE      ; the rest wait their turn (the area's
                bcc     wl_wait         ; tally is the same)
                ldx     #aliens         ; launch one into a free slot
wave_logic_b1:  ldd     O_SPR,x
                beq     wave_logic_f1
                ldab    #OBJ_SIZE
                abx
                cpx     #aliens_end
                bne     wave_logic_b1
wl_wait:        inc     wv_timer        ; none free: try next frame
                rts
wave_logic_f1:  stx     obj
                ldx     wv_ptr
                ldab    W_GAP,x
                stab    wv_timer
                ldaa    wv_x            ; this alien's entry x; the next one's
                tab                     ; is W_XSTEP further across ...
                addb    W_XSTEP,x
                cmpb    #128-AL_W       ; ... back to the first lane if that
                bcs     wl_xok          ; would be off screen (relaunched
                ldab    W_X,x           ; survivors can outnumber the lanes)
wl_xok:         stab    wv_x
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
                ldaa    fl_event        ; (a path may start with event 2/3)
                cmpa    #2
                bcs     wl_nohop
                ldx     obj
                jsr     hop_flag
wl_nohop:       dec     wv_left
                inc     alive
wl_done:        rts
wl_next:                                ; next wave when at most 2 remain
                ldaa    alive
                cmpa    #2
                bls     wl_next_f1
                inc     wv_timer
                rts
wl_next_f1:     ldx     wv_ptr
                ldab    #W_SIZE
                abx
                inc     wv_index
                ldd     0,x             ; another wave in the list?
                bne     wl_launch
                tst     boss_state      ; the end of the list.  In a boss
                beq     wl_area_end     ; fight the escorts go round again
                ldx     wv_start
                bra     wl_launch
wl_area_end:    inc     area_done       ; otherwise the area's waves are done
                rts
wl_launch:      stx     wv_ptr
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
                beq     aliens_logic_f1
                dec     bomb_cd
aliens_logic_f1:
                inc     spray_t
                ldaa    spray_t
                cmpa    #SPRAY_ON+SPRAY_OFF
                bcs     aliens_logic_f2
                clr     spray_t
aliens_logic_f2:
                ldaa    ship+O_X        ; the aim target: the ship
                staa    fl_tx
                ldaa    ship+O_Y
                staa    fl_ty
                ldx     #aliens
al_loop:
                stx     obj
                ldd     O_SPR,x
                bne     al_used
                jmp     al_next
al_used:        ldd     AN_PTR,x        ; exploding?
                beq     al_live
                ldd     O_X,x           ; drift, but not off the sides
                addd    O_DX,x
                cmpa    #128-AL_W
                bcs     al_loop_f1
                ldd     #0
                std     O_DX,x
al_loop_f1:     jsr     obj_anim_step   ; next frame; frees the slot at the end
                jmp     al_next
al_live:
                ldaa    F_FLAGS,x       ; waiting out of sight before coming
                cmpa    #FF_WAIT1       ; back in (a count in bits 3-7)?
                bcs     al_go
                ldab    spray_t         ; count every 4th frame
                andb    #3
                bne     al_wait
                suba    #FF_WAIT1
                staa    F_FLAGS,x
                cmpa    #FF_WAIT1
                bcc     al_wait
                jsr     fl_velocity     ; time's up: on along the path
al_wait:        jmp     al_next
al_go:          ldaa    F_FLAGS,x       ; wrapping aliens may be anywhere
                bita    #FF_WRAP
                bne     al_inside
                ldaa    O_X,x           ; off the side somehow?  Back inside
                cmpa    #128-AL_W       ; (left edge if it wrapped below 0)
                bcs     al_inside
                clrb
                cmpa    #192
                bcc     al_clamp
                ldab    #128-AL_W-1
al_clamp:       stab    O_X,x
                ldaa    #128            ; and turn it round
                suba    F_ANG,x
                staa    F_ANG,x
al_inside:      jsr     fl_step
                ldaa    fl_event        ; event 1: drop a bomb
                cmpa    #1
                beq     al_drop
                bcs     al_aim
                ldx     obj
                jsr     hop_flag
                bra     al_live_f1
al_aim:         ldx     obj             ; or right over the ship (no spot
                ldaa    O_X,x           ; is safe for a ship that never
                suba    ship+O_X        ; moves); the rhythm still decides
                adda    #saucer_PADX+3-ship_PADX-3+AIM_W
                cmpa    #2*AIM_W+1
                bcc     al_live_f1
                jsr     drop_aim
                bra     al_live_f1
al_drop:        jsr     drop_bomb
al_live_f1:     ldx     obj
                ldaa    F_FLAGS,x       ; a wrapping alien: through the side
                bita    #FF_WRAP        ; to the other one
                beq     al_mirror
                ldd     O_X,x
                addd    O_DX,x
                bita    #$80            ; next x past either edge (128-255)?
                beq     al_live_f2
                jsr     obj_erase       ; the halo can't bridge the jump
                ldx     obj
                ldaa    O_X,x           ; x stays below 128, so the other
                eora    #$80            ; side is x +/- 128: flip the top bit
                staa    O_X,x
                bra     al_live_f2
al_mirror:      ldd     O_X,x           ; safety: mirror off the sides
                addd    O_DX,x
                cmpa    #128-AL_W
                bcs     al_live_f2
                ldaa    #128
                suba    F_ANG,x
                staa    F_ANG,x
                jsr     fl_velocity
                ldx     obj
al_live_f2:     ldd     O_Y,x           ; through the bottom: back in at the top
                addd    O_DY,x
                cmpa    #192
                bcs     al_next
                cmpa    #224
                bcc     al_next
                ldab    F_FLAGS,x       ; somewhere new?
                bitb    #FF_HOPL|FF_HOPR
                beq     al_top
                jsr     obj_erase       ; (in the hidden rows: just tidy)
                jsr     rnd             ; x = 1-96, or 22-117 for left
                ldab    #96             ; circles (they stay on screen)
                mul
                inca
                ldx     obj
                ldab    F_FLAGS,x
                bitb    #FF_HOPL
                beq     al_hop_x
                adda    #21
al_hop_x:       staa    O_X,x
                ldd     #0              ; and wait there a moment, out of
                std     O_DX,x          ; sight, so it looks intentional
                std     O_DY,x
                jsr     rnd             ; for its own random time (not in
                andb    #15             ; step with the others leaving, or
                addb    #HOP_WAIT       ; it looks like an instant swap)
                aslb
                aslb
                aslb
                ldx     obj
                orab    F_FLAGS,x
                stab    F_FLAGS,x
al_top:         ldaa    #256-AL_H
                staa    O_Y,x
al_next:
                ldx     obj
                ldab    #OBJ_SIZE
                abx
                cpx     #aliens_end
                beq     al_done
                jmp     al_loop
al_done:        rts

; event 2/3 (A) for the alien at X: from now on it comes back in from
; the top at a random x (2: for left circles, 3: right ones)
hop_flag:
                ldab    #FF_HOPL
                cmpa    #2
                beq     hop_flag_f1
                ldab    #FF_HOPR
hop_flag_f1:    orab    F_FLAGS,x
                stab    F_FLAGS,x
                rts

; drop a bomb from the alien at obj: it keeps the alien's sideways
; speed, so bombs thrown along a dive land along its line (an unmoving
; ship is never safe between the drop points)
drop_bomb:
                ldx     obj
                ldd     O_DX,x          ; half the alien's sideways speed
                asra
                rorb
                std     bm_dx
                bra     drop_pos
drop_aim:                               ; straight down, onto the ship
                ldx     #0
                stx     bm_dx
                ldx     obj
drop_pos:       ldaa    O_X,x
                adda    #saucer_PADX+3-bomb_PADX
                ldab    O_Y,x
                addb    #saucer_H-saucer_PADY-bomb_PADY
                bra     bomb_dx

; a bomb at A = x, B = y (its box), falling straight, if the rhythm
; allows and it's far enough above the ship
bomb_at:
                ldx     #0
                stx     bm_dx
bomb_dx:        std     bm_xy
                ldaa    bomb_cd         ; too soon after the last bomb?
                bne     db_done
                ldaa    spray_t         ; in a spray window?
                cmpa    #SPRAY_ON
                bcc     db_done
                ldaa    ship+O_Y        ; far enough above the ship to
                suba    #BOMB_WARN      ; dodge?
                cmpa    bm_xy+1
                bls     db_done
                ldx     #bombs
bomb_at_b1:     ldd     O_SPR,x
                beq     db_done_f1
                ldab    #OBJ_SIZE
                abx
                cpx     #bombs_end
                bne     bomb_at_b1
db_done:        rts
db_done_f1:     ldd     bm_xy
                staa    O_X,x
                stab    O_Y,x
                clr     O_XF,x
                clr     O_YF,x
                ldd     bm_dx
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

; a bomb at A = x, B = y, whatever the rhythm (envoys), if a slot is free
bomb_force:
                std     bm_xy
                ldaa    ship+O_Y        ; far enough above the ship to
                suba    #BOMB_WARN      ; dodge?
                cmpa    bm_xy+1
                bls     bf_done
                ldx     #bombs
bf_find:        ldd     O_SPR,x
                beq     bf_slot
                ldab    #OBJ_SIZE
                abx
                cpx     #bombs_end
                bne     bf_find
bf_done:        rts
bf_slot:        ldd     bm_xy
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
                rts

bombs_logic:
                ldx     #bombs
bombs_logic_b1: stx     obj2
                ldd     O_SPR,x
                beq     bombs_logic_f1
                ldd     O_X,x           ; off a side (thrown bombs)?
                addd    O_DX,x
                cmpa    #128-bomb_W
                bcc     bombs_logic_off
                ldd     O_Y,x           ; off the bottom?
                addd    O_DY,x
                cmpa    #192-bomb_H
                bcs     bombs_logic_f1
bombs_logic_off:
                jsr     obj_erase
                ldx     obj2
                ldd     #0
                std     O_SPR,x
bombs_logic_f1: ldx     obj2
                ldab    #OBJ_SIZE
                abx
                cpx     #bombs_end
                bne     bombs_logic_b1
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
                beq     sl_play_f1
                jsr     obj_anim_step
sl_play_f1:     dec     dead_t
                bne     sl_ret
                tst     lives
                beq     sl_over
                jsr     field_clear     ; a fresh screen ...
                jsr     map_show        ; ... after the map
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
                beq     sl_alive_f1               ; the end: visible
                bita    #4
                beq     sl_alive_f2              ; every 4 frames: hide ...
sl_alive_f1:    ldd     #ship_dsc       ; ... or show
                std     O_SPR,x
                bra     sl_move
sl_alive_f2:    ldd     O_SPR,x
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
                beq     sl_move_f1
                ldd     #-SHIP_SPEEDX
                std     O_DX,x
                ldaa    joy
sl_move_f1:     bita    #J_RIGHT
                beq     sl_move_f2
                ldd     #SHIP_SPEEDX
                std     O_DX,x
                ldaa    joy
sl_move_f2:     bita    #J_UP
                beq     sl_move_f3
                ldd     #-SHIP_SPEED
                std     O_DY,x
                ldaa    joy
sl_move_f3:     bita    #J_DOWN
                beq     sl_move_f4
                ldd     #SHIP_SPEED
                std     O_DY,x
sl_move_f4:     ldd     O_X,x
                addd    O_DX,x
                cmpa    #SHIP_XMAX
                bcs     sl_move_f5
                ldd     #0
                std     O_DX,x
sl_move_f5:     ldd     O_Y,x
                addd    O_DY,x
                cmpa    #SHIP_YMIN
                bcs     sl_stop
                cmpa    #SHIP_YMAX
                bcs     sl_done
sl_stop:        ldd     #0
                std     O_DY,x
sl_done:        ldd     O_SPR,x         ; hidden (flashing): the sprite manager
                bne     sl_done_f1               ; won't move it, so move it here
                ldd     O_X,x
                addd    O_DX,x
                std     O_X,x
                ldd     O_Y,x
                addd    O_DY,x
                std     O_Y,x
sl_done_f1:     rts

; After a lost ship: every alien, bomb and shot goes.  Aliens that weren't
; destroyed still count: they are launched again along the current wave's
; path.  (In a boss fight the boss stays; its escorts start over.)
field_clear:
                ldx     #aliens         ; empty the alien, bomb and shot slots
fc_clear:       clr     0,x
                inx
                cpx     #shots_end
                bne     fc_clear
                ldaa    alive           ; the survivors must come again
                beq     fc_done
                adda    wv_left
                staa    wv_left
                clr     alive
                clr     area_done
                ldx     wv_ptr          ; from the wave's entry point
                ldaa    W_X,x
                staa    wv_x
                ldaa    #60
                staa    wv_timer
fc_done:        rts

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
                bne     ship_hit_f1
                tst     dead
                bne     ship_hit_f1
                tst     invuln
                bne     ship_hit_f1
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
ship_hit_f1:    rts

; ---------------------------------------------------------------- shots
fire_logic:
                tst     dead
                bne     fl_done
                tst     mode
                bne     fl_done
                ldaa    cooldown
                beq     fire_logic_f1
                dec     cooldown
                rts
fire_logic_f1:  ldaa    joy
                bita    #J_FIRE
                beq     fl_done
                ldx     #shots
fire_logic_b1:  ldd     O_SPR,x
                beq     fire_logic_f2
                ldab    #OBJ_SIZE
                abx
                cpx     #shots_end
                bne     fire_logic_b1
                rts
fire_logic_f2:  ldaa    ship+O_X        ; the nose: column 3 of the ship
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
shots_logic_b1: stx     obj2
                ldd     O_SPR,x
                beq     sh_gone_f1
                ldd     O_Y,x           ; under the status bar (or past the
                addd    O_DY,x          ; top): gone
                cmpa    #BAND
                bcs     sh_gone
                cmpa    #192
                bcs     sh_gone_f1
sh_gone:
                jsr     obj_erase
                ldx     obj2
                ldd     #0
                std     O_SPR,x
sh_gone_f1:     ldx     obj2
                ldab    #OBJ_SIZE
                abx
                cpx     #shots_end
                bne     shots_logic_b1
                rts

; ---------------------------------------------------------------- hits
; Collisions.  Shots against the boss every frame (the core's window is
; shallow), but each shot against the aliens only every other frame
; (alternating shots), and the ship against aliens / bombs on alternate
; frames: their overlap windows are deeper than two frames' movement, so
; nothing slips through, and it halves the work.
collide:
                com     col_par         ; this frame's parity
                ldaa    col_par
                staa    cs_par
                ldx     #shots          ; shots against the boss and aliens
cs_loop:
                stx     ht_a
                ldd     O_SPR,x
                beq     cs_next
                jsr     boss_shot       ; the boss first
                bcc     cs_loop_f1
                ldx     ht_a            ; it hit the boss: the shot is spent
                jsr     obj_erase
                ldx     ht_a
                ldd     #0
                std     O_SPR,x
                jmp     cs_next
cs_loop_f1:     com     cs_par          ; every other shot (alternating) meets
                beq     cs_next         ; the aliens this frame
                ldx     ht_a
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
                beq     shots_done
                jmp     cs_loop
shots_done:     tst     col_par         ; bombs against the ship on one frame,
                beq     cb_skip         ; aliens against it on the other
                tst     dead
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
                rts
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
                ldaa    boss_state
                cmpa    #BS_DEFEATED
                beq     vc_win
                tst     area_done       ; waves cleared: the boss comes
                beq     vc_done
                tst     alive
                bne     vc_done
                tst     boss_state
                bne     vc_done
                jmp     boss_start
vc_win:
                clr     boss_state
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

; ---------------------------------------------------------------- boss
; The boss: a big sprite (boss) with its weak spot, the core (core), a
; separate small sprite drawn over the boss's opening and moved with it.
; Only shots on the core do damage; the hull just pings them away.  It
; descends from under the status bar, sways and fires its cannons while
; escorts loop around it, and explodes when its core is spent.

boss_start:
                ldaa    #BS_ENTER
                staa    boss_state
                ldx     #boss
                ldaa    #(128-boss1_W)/2
                staa    O_X,x
                ldaa    #256-boss1_H    ; just above the top, hidden
                staa    O_Y,x
                clr     O_XF,x
                clr     O_YF,x
                ldd     #0
                std     O_DX,x
                ldd     #BOSS_DESCEND
                std     O_DY,x
                ldd     #boss1_dsc
                std     O_SPR,x
                clr     core_flash
                ldab    area            ; this area's boss: core hits, envoys,
                ldaa    #5              ; envoy hits, escorts
                mul
                addd    #boss_tab
                std     bm_xy
                ldx     bm_xy
                ldaa    0,x
                staa    boss_hp
                ldaa    1,x
                staa    env_left
                ldaa    2,x
                staa    env_hp
                staa    env_hp+1
                ldx     3,x
                stx     wv_start
                ldaa    #BOSS_XMIN      ; the sway range
                ldab    #BOSS_XMAX
                tst     env_left
                beq     bst_noenv
                ldaa    #BOSS_EXMIN
                ldab    #BOSS_EXMAX
                ldx     #env1           ; the envoys
                ldd     #envoy_dsc
                std     O_SPR,x
                ldx     #env2
                std     O_SPR,x
                ldaa    #BOSS_EXMIN
                ldab    #BOSS_EXMAX
bst_noenv:      staa    boss_xmin
                stab    boss_xmax
                ldx     #core           ; the core: shut while envoys fly
                ldd     #core_dsc
                tst     env_left
                beq     bst_open
                ldd     #coreshut_dsc
bst_open:       std     O_SPR,x
                jsr     boss_attach
                ldaa    #ENV_FIRE
                staa    env_t
                ldx     wv_start
                stx     wv_ptr
                jsr     wave_begin
                clr     area_done
                ldaa    #WARN_TIME      ; escorts after the warning
                staa    wv_timer
                ldaa    #BOSS_FIRE
                staa    boss_t
                ldx     #fx_bossin
                ldaa    #5
                jsr     snd_play
                ldd     #s_bossin
                jsr     banner_show
                ldaa    #WARN_TIME
                staa    banner_t
                inc     banner_fl       ; flashing
                rts

bl_r0:          rts
boss_logic:
                ldaa    boss_state
                beq     bl_r0
                cmpa    #BS_DEFEATED
                beq     bl_r0
                cmpa    #BS_DYING
                bne     boss_logic_f1
                jmp     boss_dying
boss_logic_f1:  ldx     #boss
                cmpa    #BS_ENTER
                bne     bl_fight
                ldaa    O_Y,x           ; descending: arrived?
                cmpa    #BOSS_Y
                bcs     bl_core         ; (still above: 224-255 counts as high)
                cmpa    #192
                bcc     bl_core
                ldd     #0
                std     O_DY,x
                ldd     #BOSS_SPEED
                std     O_DX,x
                ldaa    #BS_FIGHT
                staa    boss_state
                bra     bl_core
bl_fight:
                ldd     O_X,x           ; sway between the sides
                addd    O_DX,x
                cmpa    boss_xmin
                bcs     bl_fight_f1
                cmpa    boss_xmax
                bcs     bl_fight_f2
bl_fight_f1:    ldd     #0
                subd    O_DX,x
                std     O_DX,x
bl_fight_f2:    dec     boss_t          ; the cannons, in turn
                bne     bl_core
                ldaa    #BOSS_FIRE
                staa    boss_t
                com     boss_side
                ldaa    O_X,x
                adda    #boss1_PADX+4-bomb_PADX
                tst     boss_side
                beq     bl_fight_f3
                adda    #14
bl_fight_f3:    ldab    O_Y,x
                addb    #boss1_PADY+12-bomb_PADY
                jsr     bomb_at
bl_core:
                jsr     env_bomb
                jsr     boss_attach
                ldx     #core
                ldaa    core_flash      ; white for a moment after a hit
                beq     bl_r
                dec     core_flash
                bne     bl_r
                ldd     #core_dsc
                std     O_SPR,x
bl_r:           rts

; The core and the flying envoys ride with the hull: placed relative to
; it, with its velocity.  Exploding envoys stay where they died and play
; out their explosion.
boss_attach:
                ldx     #boss
                ldd     O_DX,x
                std     ba_dx
                ldd     O_DY,x
                std     ba_dy
                ldaa    O_X,x
                ldab    O_Y,x
                std     ba_xy
                adda    #CORE_DX
                addb    #CORE_DY
                ldx     #core
                bsr     ba_place
                ldx     #env1
                ldd     O_SPR,x
                beq     ba_env2
                ldd     AN_PTR,x
                beq     ba_l
                jsr     obj_anim_step
                bra     ba_env2
ba_l:           ldd     ba_xy
                suba    #ENV_DXL
                addb    #ENV_DY
                bsr     ba_place
ba_env2:        ldx     #env2
                ldd     O_SPR,x
                beq     ba_done
                ldd     AN_PTR,x
                beq     ba_r
                jmp     obj_anim_step
ba_r:           ldd     ba_xy
                adda    #ENV_DXR
                addb    #ENV_DY
                ; fall through
ba_place:                               ; X = object, A, B = x, y; hull's speed
                staa    O_X,x
                stab    O_Y,x
                ldd     ba_dx
                std     O_DX,x
                ldd     ba_dy
                std     O_DY,x
ba_done:        rts

; The envoys bomb in turn, fast and outside the aliens' spray rhythm.
env_bomb:
                tst     env_left
                beq     eb_done
                ldaa    boss_state
                cmpa    #BS_FIGHT
                bne     eb_done
                dec     env_t
                bne     eb_done
                ldaa    #ENV_FIRE
                staa    env_t
                com     env_side
                ldx     #env1
                tst     env_side
                beq     eb_try
                ldx     #env2
eb_try:         ldd     AN_PTR,x        ; that one gone?  The other, then
                bne     eb_other
                ldd     O_SPR,x
                bne     eb_fire
eb_other:       cpx     #env1
                bne     eb_o1
                ldx     #env2
                bra     eb_o2
eb_o1:          ldx     #env1
eb_o2:          ldd     AN_PTR,x
                bne     eb_done
                ldd     O_SPR,x
                beq     eb_done
eb_fire:        ldaa    O_X,x
                adda    #envoy_PADX+3-bomb_PADX
                ldab    O_Y,x
                addb    #envoy_H-envoy_PADY-bomb_PADY
                jmp     bomb_force
eb_done:        rts

; a shot (ht_a) against the boss: carry set if it hit anything
boss_shot:
                ldaa    boss_state
                cmpa    #BS_FIGHT
                bne     bs_miss
                ldx     ht_a            ; quick reject: the shot below the boss
                ldaa    O_Y,x
                ldx     #boss
                suba    O_Y,x
                cmpa    #boss1_H
                bcc     bs_miss
                ldx     #env1           ; the envoys
                jsr     env_test
                bcs     bs_hit
                ldx     #env2
                jsr     env_test
                bcs     bs_hit
                ldx     ht_a            ; in the core's column?  (The quick
                ldaa    O_X,x           ; reject above already put the shot
                ldx     #core           ; in the boss's rows, so x decides.)
                suba    O_X,x
                adda    #shot_PADX-core_PADX
                cmpa    #4              ; (the core is 4 pixels wide)
                bcc     bs_hull
                ldx     ht_a            ; up the channel: has it reached the
                ldaa    O_Y,x           ; core's bottom row yet?
                adda    #shot_PADY
                ldx     #core
                suba    O_Y,x
                suba    #core_PADY+4
                bcc     bs_miss         ; not yet: it flies on
                tst     env_left        ; shut: it pings like the hull
                bne     bs_ping
                bra     bs_core
bs_hull:        ldx     ht_a            ; the hull: is the shot within its
                ldaa    O_X,x           ; width?
                adda    #shot_PADX
                ldx     #boss
                suba    O_X,x
                suba    #boss1_PADX
                cmpa    #24             ; (the hull is 24 pixels wide)
                bcc     bs_miss
bs_ping:        ldx     #fx_ping        ; the hull: the shot bounces off
                ldaa    #1
                jsr     snd_play
bs_hit:         sec
                rts
bs_miss:        clc
                rts
bs_core:
                jsr     score_50
                ldx     #core           ; flash white
                ldd     #corehit_dsc
                std     O_SPR,x
                ldaa    #6
                staa    core_flash
                dec     boss_hp
                beq     boss_die
                ldx     #fx_clang
                ldaa    #2
                jsr     snd_play
                sec
                rts

; X = an envoy: if the shot ht_a hits it, take a hit (carry set)
env_test:
                ldd     O_SPR,x
                beq     et_miss
                ldd     AN_PTR,x
                bne     et_miss
                stx     ht_b
                ldaa    O_X,x           ; quick reject: the shot more than an
                ldx     ht_a            ; envoy's width to either side
                suba    O_X,x
                adda    #envoy_W
                cmpa    #2*envoy_W
                bcc     et_miss
                jsr     hit_test
                bcc     et_miss
                ldaa    #0              ; which envoy: 0 left, 1 right
                ldx     ht_b
                cpx     #env1
                beq     et_which
                inca
et_which:       ldx     #env_hp
                tab
                abx
                dec     0,x
                beq     et_down
                ldx     #fx_clang
                ldaa    #2
                jsr     snd_play
                sec
                rts
et_down:        ldx     ht_b            ; destroyed: it explodes ...
                ldd     #0
                std     O_DX,x
                std     O_DY,x
                ldd     #anim_boom
                jsr     obj_anim_start
                jsr     score_500
                ldx     #fx_boom
                ldaa    #3
                jsr     snd_play
                dec     env_left        ; ... and when both are gone the
                bne     et_hit          ; core opens
                ldx     #core
                ldd     #core_dsc
                std     O_SPR,x
                ldx     #fx_open
                ldaa    #4
                jsr     snd_play
et_hit:         sec
                rts
et_miss:        clc
                rts

boss_die:                               ; the core is spent
                ldaa    #BS_DYING
                staa    boss_state
                ldaa    #DIE_TIME
                staa    boss_t
                inc     area_done       ; no more escorts ...
                ldx     #boss
                ldd     #0
                std     O_DX,x
                std     O_DY,x
                ldx     #core
                std     O_DX,x
                std     O_DY,x
                ldx     #aliens         ; ... and those flying explode with it
boss_die_b1:    stx     obj
                ldd     O_SPR,x
                beq     boss_die_f1
                ldd     AN_PTR,x
                bne     boss_die_f1
                ldd     #anim_boom
                jsr     obj_anim_start
                dec     alive
boss_die_f1:    ldx     obj
                ldab    #OBJ_SIZE
                abx
                cpx     #aliens_end
                bne     boss_die_b1
                ldx     #fx_bossdie
                ldaa    #6
                jsr     snd_play
                sec
                rts

boss_dying:                             ; explosions all over the hull
                dec     boss_t
                beq     bd_gone
                ldaa    boss_t
                anda    #7
                bne     bd_r
                ldx     #aliens         ; a burst in a free slot
boss_dying_b1:  ldd     O_SPR,x
                beq     boss_dying_f1
                ldab    #OBJ_SIZE
                abx
                cpx     #aliens_end
                bne     boss_dying_b1
                rts
boss_dying_f1:  stx     obj
                jsr     rnd             ; somewhere on the hull
                andb    #15
                ldx     #boss
                addb    O_X,x
                stab    bm_xy
                jsr     rnd
                andb    #7
                ldx     #boss
                addb    O_Y,x
                ldx     obj
                stab    O_Y,x
                ldaa    bm_xy
                staa    O_X,x
                ldd     #0
                std     O_DX,x
                std     O_DY,x
                ldd     #anim_boom
                jmp     obj_anim_start
bd_gone:
                ldx     #env1           ; the end: the boss is gone
                jsr     obj_erase
                ldx     #env2
                jsr     obj_erase
                ldx     #env1
                ldd     #0
                std     O_SPR,x
                std     AN_PTR,x
                ldx     #env2
                std     O_SPR,x
                std     AN_PTR,x
                ldx     #core
                jsr     obj_erase
                ldx     #core
                ldd     #0
                std     O_SPR,x
                ldx     #boss
                jsr     obj_erase
                ldx     #boss
                ldd     #0
                std     O_SPR,x
                jsr     score_5000
                ldaa    #BS_DEFEATED
                staa    boss_state
bd_r:           rts

score_50:                               ; score += 50 (BCD)
                ldaa    score+2
                adda    #$50
                jmp     sc_lo
score_500:                              ; score += 500 (BCD)
                ldaa    score+1
                adda    #$05
                jmp     sc_mid
score_5000:                             ; score += 5000 (BCD)
                ldaa    score+1
                adda    #$50
                jmp     sc_mid

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
                bge     warp_logic_f1
                ldd     #$FC00
warp_logic_f1:  std     O_DY,x
                ldaa    frame_count     ; the stars speed up
                anda    #7
                bne     warp_logic_f2
                ldaa    warpf
                cmpa    #6
                bcc     warp_logic_f2
                inc     warpf
warp_logic_f2:  ldaa    O_Y,x           ; wholly above the top (-32..-22)?
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
                beq     wp_flame_f1
                ldd     #shipw2_dsc
                bra     wp_flame_f2
wp_flame_f1:    ldd     #shipw1_dsc
wp_flame_f2:    std     O_SPR,x
                rts

coast_logic:                            ; just stars for a moment, then the
                dec     mode_t          ; next area: the map, then the ship
                bne     wp_r            ; rises in from the bottom
                inc     area
                ldaa    area
                cmpa    #NAREAS
                bcs     coast_logic_f1
                clr     area            ; after the last: round again
coast_logic_f1: jsr     area_begin
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
                bne     arrive_logic_f1
                ldaa    warpf
                cmpa    #1
                beq     arrive_logic_f1
                dec     warpf
arrive_logic_f1:
                ldd     O_DY,x
                addd    #$0028
                bmi     arrive_logic_f2
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
arrive_logic_f2:
                std     O_DY,x
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
map_show_b1:    ldaa    col_b
                anda    #$30
                staa    0,x
                ldab    #ROW_BYTES
                abx
                cpx     #TXT_AT(MAP_BOTTOM,MAP_COL)
                bne     map_show_b1
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
                ldab    wv_index        ; 3 rows per wave (up to 10 waves)
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
map_show_b2:    jsr     frame_wait
                jsr     snd_frame
                dec     mp_t
                bne     map_show_b2
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
                rts                     ; (what waits there is a mystery)

; A = area number (0-3): its label to the left of the strip, white for
; the current area, blue for the others
map_label:
                psha
                ldab    col_b
                cmpa    area
                bne     map_label_f1
                ldab    #TXT_WHITE
map_label_f1:   stab    txt_col
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
sc_lo:          daa
                staa    score+2
                ldaa    score+1
                adca    #0
sc_mid:         daa
                staa    score+1
                ldaa    score
                adca    #0
                daa
                staa    score
                ldaa    #1              ; show it at once
                staa    status_t
                rts

; The status bar (rows 0-6: SCORE 000000 ... SHIPS 3) is rendered into
; status_buf when the score or ships change (status_t set), and copied
; to the screen after the sprites whenever any sprite touched it, so it is
; always in front: aliens slide out from under it.
BUF_AT          function row,col,status_buf+(row)*ROW_BYTES+(col)

status_update:
                tst     status_t
                beq     su_done
                clr     status_t
                ldx     #status_buf     ; blank
                clra
                clrb
status_update_b1:
                std     0,x
                inx
                inx
                cpx     #status_buf+BAND*ROW_BYTES
                bne     status_update_b1
                ldaa    col_o
                staa    txt_col
                ldx     #BUF_AT(1,1)
                ldd     #s_score
                jsr     txt_str
                ldaa    #TXT_WHITE
                staa    txt_col
                ldx     #BUF_AT(1,7)
                ldaa    #3
                staa    tx_n
                ldd     #score
                jsr     txt_bcd
                ldaa    col_o
                staa    txt_col
                ldx     #BUF_AT(1,24)
                ldd     #s_ships
                jsr     txt_str
                ldaa    #TXT_WHITE
                staa    txt_col
                ldaa    lives
                adda    #'0'
                ldx     #BUF_AT(1,30)
                jsr     txt_char
                inc     sm_dirty        ; and show it
su_done:        rts

; Repair the status bar (rows 0-6) if sprites touched it (or it changed):
; rows 1-5 (the text) are copied from status_buf, rows 0 and 6 (always
; blank) are cleared.  Each row is a stack blast with interrupts off for
; that row only: S points at the row's end, and LDD n,X / PSHB / PSHA
; writes two bytes backwards (5 cycles a byte; ~3 for the blank rows).
status_repair:
                tst     sm_dirty
                bne     sr_go
                rts
sr_go:          clr     sm_dirty
                sts     sr_sp
                ldd     #SCREEN+ROW_BYTES-1     ; row 0: blank
                jsr     sr_blank
                ldx     #SCREEN+2*ROW_BYTES-1   ; rows 1-5: the text
                stx     sr_dst
                ldx     #status_buf+ROW_BYTES
                ldaa    #5
                staa    sr_n
sr_row:
                sei
                lds     sr_dst
k               set     ROW_BYTES-2
                rept    ROW_BYTES/2
                ldd     k,x
                pshb
                psha
k               set     k-2
                endm
                lds     sr_sp
                cli
                ldab    #ROW_BYTES
                abx
                pshx
                ldd     sr_dst
                addd    #ROW_BYTES
                std     sr_dst
                pulx
                dec     sr_n
                beq     sr_last
                jmp     sr_row
sr_last:        ldd     #SCREEN+7*ROW_BYTES-1   ; row 6: blank
                ; fall through
sr_blank:                               ; D = a row's last byte: clear the row
                std     sr_dst
                sts     sr_bsp          ; (its own S: a JSR may have called it)
                sei
                lds     sr_dst
                clra
                clrb
                rept    ROW_BYTES/2
                pshb
                psha
                endm
                lds     sr_bsp
                cli
sr_done:        rts

; ---------------------------------------------------------------- banner
; D = banner (fdb screen address, then the text): show it for BANNER_TIME
banner_show:
                std     banner_p
                ldaa    #BANNER_TIME
                staa    banner_t
                clr     banner_fl       ; steady unless the caller says
                rts

banner_update:                          ; redraw it each frame while up (the
                ldaa    banner_t        ; aliens fly across it), clear it at
                beq     bu_done         ; the end
                dec     banner_t
                beq     bu_clear
                tst     banner_fl       ; flashing: off every other 16 frames
                beq     bu_draw
                ldaa    banner_t
                bita    #16
                beq     bu_clear
bu_draw:        ldaa    #TXT_WHITE
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
bu_clear_b1:    std     0,x
                inx
                inx
                cpx     #TXT_AT(BANNER_ROW+5,0)
                bne     bu_clear_b1
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
title_draw_b1:  ldaa    col_o
                staa    0,x
                staa    1,x
                staa    2,x
                pshb
                ldab    #ROW_BYTES
                abx
                pulb
                decb
                bne     title_draw_b1
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
rnd:                                    ; D = a new random 16 bits: the
                ldaa    #8              ; LFSR steps 8 times, so values in a
                staa    rnd_n           ; row aren't shifted copies
                ldd     seed
rnd_b1:         lsrd
                bcc     rnd_f1
                eora    #$B4
rnd_f1:         dec     rnd_n
                bne     rnd_b1
                std     seed
                rts

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

; ---------------------------------------------------------------- data
; Flight paths (designed with tools/pathsim.py: they stay inside the side
; edges and wrap cleanly).  Jinks and U-turns are P_TURNBY.
path_loopL:                             ; loop left, jink, dive down-right;
                fcb     P_SPEED, 0      ; then the mirror image
                fcb     P_HEAD, 64
pl_rep:         fcb     P_FLY, 40, 0
                fcb     P_EVENT, 1
                fcb     P_FLY, 16, 4
                fcb     P_EVENT, 1
                fcb     P_FLY, 16, 4
                fcb     P_EVENT, 1
                fcb     P_FLY, 16, 4
                fcb     P_EVENT, 1
                fcb     P_FLY, 16, 4
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
                fcb     P_FLY, 16, -4
                fcb     P_EVENT, 1
                fcb     P_FLY, 16, -4
                fcb     P_EVENT, 1
                fcb     P_FLY, 16, -4
                fcb     P_EVENT, 1
                fcb     P_FLY, 16, -4
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
                fcb     P_FLY, 16, -4
                fcb     P_EVENT, 1
                fcb     P_FLY, 16, -4
                fcb     P_EVENT, 1
                fcb     P_FLY, 16, -4
                fcb     P_EVENT, 1
                fcb     P_FLY, 16, -4
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
                fcb     P_FLY, 16, 4
                fcb     P_EVENT, 1
                fcb     P_FLY, 16, 4
                fcb     P_EVENT, 1
                fcb     P_FLY, 16, 4
                fcb     P_EVENT, 1
                fcb     P_FLY, 16, 4
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
                fcb     P_SPEED, 0      ; then a dive; back in from the top
                fcb     P_HEAD, 64      ; somewhere else each time
                fcb     P_EVENT, 2
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
                fcb     P_EVENT, 3
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

;; Wrap-around paths: these fly through the side edges and come in at the
; other side (P_WRAP 1).
path_sweepR:                            ; long shallow diagonals drifting
                fcb     P_WRAP, 1       ; right through the edge, with curves
                fcb     P_SPEED, 0
                fcb     P_HEAD, 20
psr_rep:        fcb     P_FLY, 40, 0
                fcb     P_EVENT, 1
                fcb     P_FLY, 40, 1
                fcb     P_FLY, 30, -1
                fcb     P_EVENT, 1
                fcb     P_FLY, 60, 0
                fcb     P_HEAD, 20
                fcb     P_GOTO
                fdb     psr_rep
path_sweepL:                            ; the mirror image
                fcb     P_WRAP, 1
                fcb     P_SPEED, 0
                fcb     P_HEAD, 108
psl_rep:        fcb     P_FLY, 40, 0
                fcb     P_EVENT, 1
                fcb     P_FLY, 40, -1
                fcb     P_FLY, 30, 1
                fcb     P_EVENT, 1
                fcb     P_FLY, 60, 0
                fcb     P_HEAD, 108
                fcb     P_GOTO
                fdb     psl_rep
path_weave:                             ; fast passes across the screen,
                fcb     P_WRAP, 1       ; round through the sides, then a dive
                fcb     P_SPEED, 0
                fcb     P_HEAD, 64
pwv_rep:        fcb     P_FLY, 30, 0
                fcb     P_HEAD, 6
                fcb     P_FLY, 70, 0
                fcb     P_EVENT, 1
                fcb     P_TURNBY, 116
                fcb     P_FLY, 50, 0
                fcb     P_EVENT, 1
                fcb     P_TURNBY, -116
                fcb     P_FLY, 50, 0
                fcb     P_TURNBY, 58
                fcb     P_FLY, 60, 0
                fcb     P_HEAD, 64
                fcb     P_GOTO
                fdb     pwv_rep

; Areas: each a list of waves, ending with fdb 0.  At most 10 waves an
; area (the map shows 3 rows per wave).  Later areas launch faster.
areas:          fdb     area1, area2, area3, area4
; (Each wave: descriptor, path; count, launch interval, entry x, x step.)
area1:                                  ; gentle: 6 at a time, then 8
                fdb     saucer_dsc, path_loopL
                fcb     6, 14, 30, 0
                fdb     dart_dsc, path_zigRL
                fcb     6, 16, 21, 12
                fdb     orbiter_dsc, path_circle
                fcb     6, 14, 35, 0
                fdb     saucer_dsc, path_sweepR
                fcb     6, 16, 20, 0
                fdb     dart_dsc, path_zigLR
                fcb     6, 16, 103, -12
                fdb     orbiter_dsc, path_circleR
                fcb     6, 14, 84, 0
                fdb     orbiter_dsc, path_sweepL
                fcb     8, 14, 100, 0
                fdb     dart_dsc, path_zigRL
                fcb     8, 14, 15, 12
                fdb     0
area2:
                fdb     saucer_dsc, path_loopR
                fcb     8, 12, 89, 0
                fdb     dart_dsc, path_zigLR
                fcb     8, 14, 103, -12
                fdb     orbiter_dsc, path_circleR
                fcb     8, 12, 84, 0
                fdb     saucer_dsc, path_loopL
                fcb     8, 12, 30, 0
                fdb     orbiter_dsc, path_circle
                fcb     8, 12, 35, 0
                fdb     dart_dsc, path_weave
                fcb     8, 14, 30, 0
                fdb     saucer_dsc, path_sweepR
                fcb     8, 12, 20, 0
                fdb     orbiter_dsc, path_circleR
                fcb     8, 11, 84, 0
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
                fdb     saucer_dsc, path_sweepL
                fcb     8, 10, 100, 0
                fdb     orbiter_dsc, path_circleR
                fcb     8, 10, 84, 0
                fdb     dart_dsc, path_weave
                fcb     8, 11, 90, 0
                fdb     saucer_dsc, path_loopR
                fcb     8, 9, 89, 0
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
                fdb     dart_dsc, path_weave
                fcb     8, 10, 30, 0
                fdb     saucer_dsc, path_sweepR
                fcb     8, 9, 20, 0
                fdb     orbiter_dsc, path_sweepL
                fcb     8, 8, 100, 0
                fdb     dart_dsc, path_zigRL
                fcb     8, 9, 15, 12
                fdb     0

; Bosses, per area: core hits, escort wave list (it loops)
; (core hits, envoys, hits per envoy, escorts)
boss_tab:       fcb     8, 0, 0
                fdb     esc1
                fcb     10, 2, 4
                fdb     esc2
                fcb     12, 2, 6
                fdb     esc3
                fcb     14, 2, 8
                fdb     esc4
esc1:           fdb     saucer_dsc, path_circle
                fcb     4, 20, 35, 0
                fdb     dart_dsc, path_zigRL
                fcb     4, 20, 21, 12
                fdb     0
esc2:           fdb     orbiter_dsc, path_circleR  ; (envoy bosses: fewer
                fcb     4, 16, 84, 0               ; escorts, the envoys
                fdb     saucer_dsc, path_loopL     ; bring the danger)
                fcb     4, 16, 30, 0
                fdb     0
esc3:           fdb     dart_dsc, path_zigLR
                fcb     4, 14, 103, -12
                fdb     orbiter_dsc, path_circle
                fcb     4, 14, 35, 0
                fdb     0
esc4:           fdb     saucer_dsc, path_loopR
                fcb     4, 12, 89, 0
                fdb     dart_dsc, path_zigRL
                fcb     4, 12, 15, 12
                fdb     orbiter_dsc, path_circleR
                fcb     4, 12, 84, 0
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
s_cleared:      fdb     TXT_AT(BANNER_ROW,10)
                fcc     "AREA CLEARED"
                fcb     0
s_bossin:       fdb     TXT_AT(BANNER_ROW,11)
                fcc     "WARNING!"
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
                fdb     shipw1_dsc, shipw2_dsc, boss1_dsc, core_dsc
                fdb     corehit_dsc, envoy_dsc, coreshut_dsc, 0

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
fx_bossin:                              ; the boss arrives: eight low, falling
                rept    8               ; wails (~4 s; low tones are cheap)
                fcb     24, SND_TONE
                fdb     1200, 16
                fcb     6, SND_REST
                fdb     0, 0
                endm
                fcb     0
fx_ping:                                ; a shot bounces off the hull (kept
                fcb     3, SND_TONE     ; below ~1 kHz: high tones cost CPU)
                fdb     480, 0
                fcb     0
fx_clang:                               ; a hit on the core
                fcb     3, SND_NOISE
                fdb     250, 0
                fcb     8, SND_TONE
                fdb     520, 40
                fcb     0
fx_open:                                ; the core's hatch opens
                NOTE    N_C4, 6
                NOTE    N_G4, 6
                NOTE    N_C5, 12
                fcb     0
fx_bossdie:                             ; the boss goes up: a long roar
                fcb     10, SND_NOISE
                fdb     250, 0
                fcb     110, SND_NOISE
                fdb     380, 4
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
boss:           fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
core:           fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
env1:           fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
env2:           fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
aliens:
                rept    NALIEN
                fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                endm
aliens_end:
bombs:
                rept    NBOMB
                fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                endm
bombs_end:
shots:
                rept    NSHOT
                fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                endm
shots_end:
ship:
                fcb     (128-ship_W)/2, 0, 160, 0
                fdb     0, 0, ship_dsc
                fcb     0, 0, 0, 0, 0, 0, 0, 0, 0, 0
objs_end:

#include "frame.asm"
#include "sprite.asm"
#include "sprman.asm"
#include "flight.asm"
#include "input.asm"
#include "sound.asm"
#include "stars.asm"
#include "text.asm"
#include "colswap.asm"
#include "game_spr.inc"
                CODE_CHECK

; ---------------------------------------------------------------- low
; The low segment ($0400-$1FFF), loaded by LOADM along with the main one:
; the aliens' and explosions' sprite code and the sine table.
                org     LOW
#include "game_lo_spr.inc"
#include "sintab.asm"
                LOW_CHECK
