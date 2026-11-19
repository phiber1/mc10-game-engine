; layout.inc: CPU, memory layout and direct-page variables.
; Included first by every program.
;
; Memory (8K internal mod + MCX32-SD, required).  Programs load with the
; MCX32-SD's LOADM from a DECB .BIN of up to two segments:
;   $0080-$00FF  6803 internal RAM: engine variables (direct page, fast)
;   $0200-$03FF  MCX BASIC's interrupt hooks and variables: LOADM uses them
;   $0400-$1FFF  LOW: the low segment (MCX32-SD SRAM, 7K): sprites, tables
;   $2000-$3FFF  MCX32-SD flash (BIOS); $3C00-$3FFF is the top gutter
;   $4000-$57FF  RG6 screen
;   $5800-$5BFF  bottom gutter (hidden rows 192-223, see sprite.asm)
;   $5C00-$5EFF  BSS: programs' ordinary variables (org BSS)
;   $5F00-$5FFF  stack (grows down from $5FFF)
;   $6000-$ADFF  CODE: the main segment (19.5K); above it, BASIC's stack
;                and string space are in use while LOADM runs

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
#ifndef AN_BASE
#define AN_BASE 0
#endif
#ifndef STAR_TOP
#define STAR_TOP 0                      /* stars.asm: first row of the star field */
#endif
#ifndef FL_HALFX
#define FL_HALFX 0
#endif
#ifndef DEBUG_TICK
#define DEBUG_TICK 0
#endif

#include "hw.inc"
#include "macros.inc"
#include "notes.inc"

; TXT_AT(row, col): the screen address of a text cell (row in pixel rows,
; col 0-31).  See text.asm.
TXT_AT          function row,col,SCREEN+(row)*ROW_BYTES+(col)

STACK_TOP       equ     $5FFF
BSS             equ     $5C00           ; ordinary variables, up to BSS_END
BSS_END         equ     $5F00
CODE            equ     $6000
CODE_END        equ     $AE00           ; LOADM's own stack is at ~$AF2C
LOW             equ     $0400           ; the low segment
LOW_END         equ     $2000

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
st_half         rmb     1               ; which half of the stars moves next
st_behind       rmb     1               ; stars pass behind the screen's contents
an_obj          rmb     2               ; sprman.asm animation
an_tmp          rmb     2
sm_band         rmb     1               ; sprman: rows of a status band (0 = none)
sm_dirty        rmb     1               ; sprman: sprites touched the band
txt_col         rmb     1               ; text.asm: colour mask
tx_scr          rmb     2
tx_scr2         rmb     2
tx_g            rmb     2
tx_s            rmb     2
tx_r            rmb     5
tx_n            rmb     1               ; txt_bcd: number of BCD bytes
cs_list         rmb     2               ; colswap.asm
cs_tab          rmb     2
cs_n            rmb     1
cs_t            rmb     1
PROG_DP         equ     *               ; programs' direct-page variables start here
; hit_test scratch lives at $00F8-$00FF
ht_al           equ     $F8             ; visible left, top of a
ht_aw           equ     $FA             ; visible width, height of a
ht_bl           equ     $FC
ht_v            equ     $FE
; PROG_DP-$00F7: free for programs (org PROG_DP).  End a program's
; direct-page block with DP_CHECK: it fails the assembly if the block runs
; into the hit_test scratch at $00F8 (which silently corrupts variables).
