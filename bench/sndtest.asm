; sndtest.asm: sound engine test.
;
; Plays a test sequence and measures the CPU left over: every frame it
; counts idle loop iterations (9 cycles each) until the next tick and logs
; the count to the debug port as two bytes (high, then low).  The count
; drops while a sound plays; the drop is the sound's cost.
;
;   0-59     silence
;   60-119   1 kHz tone (half-period 447)
;   120-179  silence
;   180-239  noise, a random bit every 500 cycles
;   240      the shooter's zap (10 frames)
;   252      its explosion (30 frames)

#include "layout.inc"

                org     $00A0
tframe          rmb     1
icount          rmb     2

                org     CODE
start:
                sei
                lds     #STACK_TOP
                ldaa    #VDG_RG6|VDG_CSS
                staa    VDG
                staa    vdg_shadow
                jsr     frame_init
                clr     tframe
                jsr     frame_wait
loop:                                   ; (the idle count below ends on a tick)
                jsr     snd_frame
                ldaa    tframe          ; start the test sounds on schedule
                cmpa    #60
                bne     +
                ldx     #fx_tone
                ldaa    #1
                jsr     snd_play
+               ldaa    tframe
                cmpa    #180
                bne     +
                ldx     #fx_noise
                ldaa    #1
                jsr     snd_play
+               ldaa    tframe          ; frame 240: zap
                cmpa    #240
                bne     +
                ldx     #fx_zap
                ldaa    #1
                jsr     snd_play
+               ldaa    tframe          ; frame 252: explosion
                cmpa    #252
                bne     +
                ldx     #fx_boom
                ldaa    #2
                jsr     snd_play
+               ldaa    tframe          ; count frames, stopping at 255
                inca
                beq     +
                staa    tframe
+               ldx     #0              ; idle count until the next tick
                ldaa    frame_count
-               inx
                cmpa    frame_count
                beq     -
                stx     icount
                ldaa    icount
                DBGA
                ldaa    icount+1
                DBGA
                bra     loop

fx_tone:        fcb     60, SND_TONE
                fdb     447, 0
                fcb     0
fx_noise:       fcb     60, SND_NOISE
                fdb     500, 0
                fcb     0
fx_zap:         fcb     10, SND_TONE    ; ~1.5 kHz sliding down to ~640 Hz
                fdb     300, 40
                fcb     0
fx_boom:        fcb     30, SND_NOISE   ; noise that deepens
                fdb     400, 20
                fcb     0

#include "frame.asm"
#include "sound.asm"
