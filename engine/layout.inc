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
; $00A0-$00FF: free for programs
