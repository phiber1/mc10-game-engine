; frame.asm: the frame tick and the sound interrupt.
;
; One output-compare interrupt drives both.  Two countdowns: snd_tt, the
; cycles to the next speaker event (a tone's toggle, a noise bit; every
; snd_half cycles), and snd_facc, the cycles to the next frame tick (every
; FRAME_CYCLES).  Each interrupt takes the time since the last off both,
; does whichever came due, and sets OCR for whichever comes next.  So the
; ticks are exactly even whatever is playing (a low tone used to make
; them land up to a half-period late: frames of uneven length), and the
; accounting is exact, so nothing drifts.  An event due less than FI_LEAD
; cycles from now (by the free-running counter, after OCR is written) is
; done at once, so OCR is never left on a time already past.
; When silent, snd_half is a whole frame and the speaker events do nothing.
;
; About 100 cycles per tone interrupt (noise ~120): a sound costs roughly
; 100 / snd_half of the CPU.
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

FI_LEAD         equ     40              ; an event nearer than this to now is
                                        ; done at once (setting OCR takes time)

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
                std     snd_tt
                std     snd_facc
                std     fi_step
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
                ldaa    TCSR            ; clear OCF: read TCSR (OCR written below)
fi_due:         ldd     snd_tt          ; the speaker event: due?
                subd    fi_step
                bgt     fi_nt
                addd    snd_half
                std     snd_tt
fi_disp:        jmp     fi_count        ; patched by sound.asm: fi_count when
                                        ; silent, fi_tone or fi_noise
fi_nt:          std     snd_tt
fi_count:                               ; (after the speaker event)
                ldd     snd_facc        ; the frame tick: due?
                subd    fi_step
                bgt     fi_nf
                addd    #FRAME_CYCLES
                inc     frame_count
                if DEBUG_TICK
                psha
                ldaa    frame_count
                DBGA
                pula
                endif
fi_nf:          std     snd_facc
                ldd     snd_tt          ; the next: the nearer of the two
                subd    snd_facc
                bcs     fi_f1           ; (unsigned: both 1 .. 65535)
                ldd     snd_facc
                bra     fi_f2
fi_f1:          ldd     snd_tt
fi_f2:          std     fi_step
                ldd     OCR             ; its time: OCR on by the step (OCR
                addd    fi_step         ; keeps the exact count: no drift)
                std     OCR             ; (writing OCR: OCF cleared)
                subd    FRC             ; still FI_LEAD cycles off?  (a time
                subd    #FI_LEAD        ; already past would only match when
                bmi     fi_due          ; the counter came round: 65,536
                rti                     ; cycles of silence and no ticks)
fi_tone:
                ldaa    vdg_shadow      ; tone: toggle the speaker
                eora    #VDG_SND
fi_out:
                staa    vdg_shadow
                staa    VDG
                bra     fi_count
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
