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
