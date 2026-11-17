; sound.asm: the sound effect sequencer (the interrupt is in frame.asm).
;
; snd_play      X = effect, A = priority: start the effect unless one of
;               higher priority is playing.  Uses A, B, X.
; snd_frame     call once per frame (after frame_wait): steps the effect.
;               Uses A, B, X.
; snd_stop      silence.
;
; An effect is a list of segments, ended by a 0 byte:
;
;   fcb  FRAMES, MODE       MODE: SND_TONE, SND_NOISE or SND_REST
;   fdb  HALF, SWEEP        HALF: speaker half-period in E cycles (tone:
;                           frequency = 447443 / HALF Hz; noise: one random
;                           bit every HALF cycles).  SWEEP: added to HALF
;                           every frame (signed), for slides.
;   ...
;   fcb  0
;
; Keep HALF >= SND_MIN_HALF: the interrupt costs ~64 cycles, so very short
; half-periods eat the CPU (and below ~100 cycles would starve it).

SND_REST        equ     0
SND_TONE        equ     1
SND_NOISE       equ     $80
SND_MIN_HALF    equ     150

snd_play:
                cmpa    snd_pri         ; lower priority than what's playing?
                bcs     sp_done         ; (snd_pri is 0 when nothing plays)
                staa    snd_pri
                stx     snd_ptr
                clr     snd_left        ; snd_frame loads the first segment
sp_done:        rts

snd_stop:
                clr     snd_ptr
                clr     snd_ptr+1
                clr     snd_left
sf_silence:
                ldx     #fi_count       ; silence the interrupt first, then
                stx     fi_disp+1       ; lengthen its period
                ldd     #FRAME_CYCLES
                std     snd_half
                clr     snd_mode
                clr     snd_pri
                rts

snd_frame:
                ldaa    snd_left
                beq     sf_next
                dec     snd_left
                ldd     snd_half        ; slide the pitch
                addd    snd_sweep
                bmi     sf_clamp        ; slid below zero
                cmpa    #SND_MIN_HALF/256
                bhi     sf_set
                bcs     sf_clamp
                cmpb    #SND_MIN_HALF&$FF
                bcc     sf_set
sf_clamp:       ldd     #SND_MIN_HALF
sf_set:         std     snd_half        ; one STD: the interrupt sees both bytes
                rts
sf_next:
                ldx     snd_ptr         ; next segment
                beq     sf_silence      ; no effect
                ldaa    0,x
                beq     snd_stop        ; end of the effect
                staa    snd_left
                ldd     4,x
                std     snd_sweep
                ldd     2,x
                std     snd_half
                stx     snd_ptr
                ldaa    1,x
                staa    snd_mode        ; (sets the flags for the branches)
                beq     sf_rest
                bmi     +
                ldx     #fi_tone        ; point the interrupt at its handler
                bra     ++
+               ldx     #fi_noise
+               stx     fi_disp+1
sf_adv:
                ldx     snd_ptr
                ldab    #6
                abx
                stx     snd_ptr
                rts
sf_rest:
                ldx     #fi_count       ; a rest: silent, frame-length events
                stx     fi_disp+1
                ldd     #FRAME_CYCLES
                std     snd_half
                bra     sf_adv
