; hw.inc: MC-10 / MC6803 hardware definitions

; MC6803 on-chip registers
P1DDR           equ     $00
P2DDR           equ     $01
P1DAT           equ     $02             ; keyboard column strobes (output)
P2DAT           equ     $03             ; bit 1: keyboard row 6 (SHIFT etc.)
TCSR            equ     $08             ; timer control/status
FRC             equ     $09             ; free-running counter (16 bits)
OCR             equ     $0B             ; output compare register (16 bits)

TCSR_EOCI       equ     $08             ; enable output-compare interrupt
TCSR_OCF        equ     $40             ; output compare flag

; VDG latch: write = mode + sound bit, read = keyboard rows
VDG             equ     $BFFF
KBD             equ     $BFFF
VDG_SND         equ     $80
VDG_CSS         equ     $40
VDG_AG          equ     $20
VDG_GM0         equ     $10
VDG_GM1         equ     $08
VDG_GM2         equ     $04
VDG_RG6         equ     VDG_AG|VDG_GM2|VDG_GM1|VDG_GM0

; Interrupt vector the ROM points at a RAM hook ($4206 stock, $0206 MCX)
VEC_OCF         equ     $FFF4

; Video
SCREEN          equ     $4000           ; RG6: 32 bytes x 192 rows
SCREEN_END      equ     $5800
ROW_BYTES       equ     32

; One video frame: 262 lines x 57 E cycles, phase-locked to the VDG
FRAME_CYCLES    equ     14934

; Debug port (emulator only: vmc10 --debug-port BE00)
DBGPORT         equ     $BE00
