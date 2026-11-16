; frame.asm: the frame tick.
;
; The MC-10 has no vertical-blank interrupt, but one video frame is exactly
; FRAME_CYCLES E cycles, so an output-compare interrupt that advances OCR by
; FRAME_CYCLES each time stays phase-locked to the VDG forever.
;
; frame_init    install the ISR and start the tick (call with interrupts on
;               or off; returns with them on)
; frame_wait    wait for the next tick
; frame_count   8-bit tick counter (direct page)

frame_init:
                sei
                ldx     VEC_OCF         ; the RAM hook the ROM vector points at
                ldaa    #$7E            ; JMP frame_isr
                staa    0,x
                ldd     #frame_isr
                std     1,x
                clr     frame_count
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
                addd    #FRAME_CYCLES
                std     OCR             ; ... then write OCR
                inc     frame_count
                if DEBUG_TICK
                ldaa    frame_count
                DBGA
                endif
                rti

frame_wait:
                ldaa    frame_count
-               cmpa    frame_count
                beq     -
                rts
