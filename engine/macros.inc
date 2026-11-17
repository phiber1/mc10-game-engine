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
; colour set flips while working, so the screen and the RG6 border turn
; green for exactly the work, like a raster-time bar.  Assembled only when
; METER is non-zero.  Goes through vdg_shadow so the speaker bit survives.
; Clobbers A.
METER_ON        macro
                if METER
                sei
                ldaa    vdg_shadow
                anda    #~VDG_CSS&$FF
                staa    vdg_shadow
                staa    VDG
                cli
                endif
                endm

METER_OFF       macro
                if METER
                sei
                ldaa    vdg_shadow
                oraa    #VDG_CSS
                staa    vdg_shadow
                staa    VDG
                cli
                endif
                endm

; VDG_SET: write A to the VDG latch through the shadow, keeping the
; speaker bit.  Clobbers A and X.
VDG_SET         macro
                sei
                anda    #~VDG_SND&$FF
                psha
                ldaa    vdg_shadow
                anda    #VDG_SND
                tsx
                oraa    0,x
                ins
                staa    vdg_shadow
                staa    VDG
                cli
                endm

; Music for the sound sequencer (sound.asm): notes from notes.inc.
; NOTE pitch, frames   a note, its last 2 frames silent (articulation)
; REST frames          silence
NOTE            macro   pitch,frames
                fcb     (frames)-2, SND_TONE
                fdb     pitch, 0
                fcb     2, SND_REST
                fdb     0, 0
                endm
REST            macro   frames
                fcb     frames, SND_REST
                fdb     0, 0
                endm
