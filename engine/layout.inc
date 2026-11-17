; layout.inc: CPU, memory layout and direct-page variables.
; Included first by every program.
;
; Memory (8K mod + MCX32-SD; the low 24K also fits an 8K mod + 16K pack):
;   $0080-$00FF  6803 internal RAM: engine variables (direct page, fast)
;   $4000-$57FF  RG6 screen
;   $5800-$5FFF  stack (grows down from $5FFF)
;   $6000-       code and data

                cpu     6801            ; the 6803 is a ROM-less 6801
                page    0               ; no listing page breaks

#ifndef DEBUG
#define DEBUG 1
#endif
#ifndef METER
#define METER 0
#endif
#ifndef OBJ_EXTRA
#define OBJ_EXTRA 0
#endif
#ifndef DEBUG_TICK
#define DEBUG_TICK 0
#endif

#include "hw.inc"
#include "macros.inc"

STACK_TOP       equ     $5FFF
CODE            equ     $6000

; ---------------------------------------------------------------- direct page
                org     $0080
frame_count     rmb     1               ; incremented by the frame tick
spr_col         rmb     1               ; sprite.asm scratch
spr_scr         rmb     2
obj_first       rmb     2               ; sprman.asm: the object table
obj_end         rmb     2
sm_obj          rmb     2               ; sprman.asm scratch
sm_desc         rmb     2
sm_tab          rmb     2
joy             rmb     1               ; input.asm: J_* bits
vdg_shadow      rmb     1               ; last value written to the VDG latch
snd_mode        rmb     1               ; frame.asm / sound.asm: 0, tone, noise
snd_half        rmb     2               ; speaker half-period (E cycles)
snd_facc        rmb     2               ; cycles to the next frame tick
snd_lfsr        rmb     2               ; noise generator
snd_ptr         rmb     2               ; next segment of the effect
snd_sweep       rmb     2               ; per-frame change of snd_half
snd_left        rmb     1               ; frames left in this segment
snd_pri         rmb     1               ; priority of the playing effect
ht_a            rmb     2               ; sprman.asm hit_test: the two objects
ht_b            rmb     2
fl_obj          rmb     2               ; flight.asm
fl_pc           rmb     2
fl_event        rmb     1               ; set by P_EVENT for the game
fl_tx           rmb     1               ; P_AIM target
fl_ty           rmb     1
fl_oct          rmb     1               ; fl_aim scratch
fl_adx          rmb     1
fl_ady          rmb     1
fl_den          rmb     1
fl_q            rmb     1
st_ptr          rmb     2               ; stars.asm
st_a            rmb     2
st_m            rmb     1
st_seed         rmb     2
PROG_DP         equ     *               ; programs' direct-page variables start here
; hit_test scratch lives at $00F8-$00FF
ht_al           equ     $F8             ; visible left, top of a
ht_aw           equ     $FA             ; visible width, height of a
ht_bl           equ     $FC
ht_v            equ     $FE
; PROG_DP-$00F7: free for programs (org PROG_DP)
