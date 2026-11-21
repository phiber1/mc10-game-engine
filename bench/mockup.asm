; mockup.asm: shows a still screen made by mockups/plat.py (a platformer
; mock-up) in mono RG6 with CSS=0: green on black, no artifacting.
;
;   make run-mockup

#include "layout.inc"

                org     BSS
mk_src          rmb     2
mk_dst          rmb     2

                org     CODE
start:
                sei
                lds     #STACK_TOP
                ldaa    #VDG_RG6        ; CSS=0
                staa    VDG
                ldx     #mk_scr
                stx     mk_src
                ldx     #SCREEN
mk_copy:        stx     mk_dst
                ldx     mk_src
                ldd     0,x
                inx
                inx
                stx     mk_src
                ldx     mk_dst
                std     0,x
                inx
                inx
                cpx     #SCREEN_END
                bne     mk_copy
                bra     *

mk_scr:
#include "mockup_scr.inc"
