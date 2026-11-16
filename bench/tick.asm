; tick.asm: frame-tick test.
;
; Starts the frame tick, switches to RG6, and on every tick inverts one
; byte of the screen so the tick is visible.  With DEBUG_TICK the ISR logs
; every tick to the debug port: the emulator log should show dt=14934 and
; the same beam line every frame.

#include "layout.inc"

                org     CODE

start:
                sei
                lds     #STACK_TOP
                ldaa    #VDG_RG6|VDG_CSS
                staa    VDG
                jsr     cls
                jsr     frame_init
loop:
                jsr     frame_wait
                com     SCREEN+96*ROW_BYTES+15
                bra     loop

; cls: clear the RG6 screen (about 18K cycles)
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

#include "frame.asm"
