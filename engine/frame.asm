; frame.asm: the frame tick and the sound interrupt.
;
; One output-compare interrupt drives both.  Each interrupt moves OCR on by
; snd_half cycles and, when a sound is playing, toggles the speaker (tone)
; or outputs a random bit (noise).  It also counts snd_half off snd_facc,
; the cycles left until the next frame tick; when that runs out it bumps
; frame_count and adds FRAME_CYCLES back.  The accounting is exact, so the
; tick never drifts; it just lands up to one half-period late, which
; doesn't matter because nothing in the engine races the beam.  When
; silent, snd_half is a whole frame and this is a plain frame tick.
;
; About 67 cycles per tone interrupt (noise ~90): a sound costs roughly
; 67 / snd_half of the CPU (measured: 1 kHz tone ~15%).
;
; frame_init    install the ISR and start the tick (returns with
;               interrupts on).  Set vdg_shadow before, or right after.
; frame_wait    wait for the next tick
; frame_count   8-bit tick counter (direct page)
;
; The 6803's OCF vector goes through a RAM hook in BASIC's area: $0206
; with MCX BASIC.  On a stock ROM it is $4206, inside the RG6 screen, so
; full-screen RG6 programs need the MCX32-SD (or must keep those three
; screen bytes as a JMP).

frame_init:
                sei
                ldx     VEC_OCF         ; the RAM hook the ROM vector points at
                ldaa    #$7E            ; JMP frame_isr
                staa    0,x
                ldd     #frame_isr
                std     1,x
                clr     frame_count
                clr     snd_mode        ; silent
                ldx     #fi_count
                stx     fi_disp+1
                clr     snd_ptr
                clr     snd_ptr+1
                clr     snd_pri
                clr     snd_left
                ldd     #0
                std     snd_sweep
                ldd     #FRAME_CYCLES
                std     snd_half
                subd    #1              ; first interrupt is a tick
                std     snd_facc
                ldd     #$ACE1          ; noise generator seed
                std     snd_lfsr
                ldaa    TCSR            ; first half of clearing a stale OCF
                ldd     FRC
                addd    #FRAME_CYCLES
                std     OCR             ; second half: writing OCR
                ldaa    #TCSR_EOCI
                staa    TCSR
                cli
                rts

frame_isr:
                ldaa    TCSR            ; clear OCF: read TCSR ...
                ldd     OCR
                addd    snd_half
                std     OCR             ; ... then write OCR: the next event
fi_disp:        jmp     fi_count        ; patched by sound.asm: fi_count when
                                        ; silent, fi_tone or fi_noise
fi_tone:
                ldaa    vdg_shadow      ; tone: toggle the speaker
                eora    #VDG_SND
fi_out:
                staa    vdg_shadow
                staa    VDG
fi_count:
                ldd     snd_facc        ; cycles to the next frame tick
                subd    snd_half
                bcs     fi_tick
                std     snd_facc
                rti
fi_tick:
                addd    #FRAME_CYCLES
                std     snd_facc
                inc     frame_count
                if DEBUG_TICK
                ldaa    frame_count
                DBGA
                endif
                rti
fi_noise:                               ; noise: a random speaker bit
                ldd     snd_lfsr
                lsrd
                bcc     +
                eora    #$B4
+               std     snd_lfsr
                ldaa    vdg_shadow
                anda    #~VDG_SND&$FF
                bitb    #1
                beq     fi_out
                oraa    #VDG_SND
                bra     fi_out

frame_wait:
                ldaa    frame_count
-               cmpa    frame_count
                beq     -
                rts
