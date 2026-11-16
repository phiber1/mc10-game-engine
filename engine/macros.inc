; macros.inc: assembler macros

; Debug markers: log the register to the emulator's debug port.
; Assembled only when DEBUG is non-zero (make DEBUG=1, the default).
DBGA            macro
                if DEBUG
                staa    DBGPORT
                endif
                endm

DBGB            macro
                if DEBUG
                stab    DBGPORT
                endif
                endm

; CPU meter: METER_ON when work starts, METER_OFF when it ends.  The VDG's
; colour set flips while working, so the RG6 border shows a green band
; (buff otherwise) covering exactly the work, like a raster-time bar.
; Assembled only when METER is non-zero.  (Clobbers A; the sound bit in
; the VDG latch is not preserved yet.)
METER_ON        macro
                if METER
                ldaa    #VDG_RG6
                staa    VDG
                endif
                endm

METER_OFF       macro
                if METER
                ldaa    #VDG_RG6|VDG_CSS
                staa    VDG
                endif
                endm
