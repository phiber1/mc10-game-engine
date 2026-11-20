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

; MCX32-SD BIOS (see vmc10-linux docs/MCX32-SD_protocol.md): JSR MCX_BIOS
; with A = device (0 = SD card), B = function, X = a parameter block;
; returns carry clear and B = 0, or carry set and B = an error code
MCX_BIOS        equ     $2000
BIOS_CLOSE      equ     0               ; close a data file (PB_MODE bit 7: written)
BIOS_OPEN       equ     $42             ; open a data file (fn 2; bit 6 as BASIC)
BIOS_READ       equ     6               ; read PB_LEN bytes to PB_BUF
BIOS_WRITE      equ     12              ; write PB_LEN bytes from PB_BUF
BIOS_LOAD       equ     22              ; LOAD a file (mode in PB_MODE)
PB_SIZE         equ     18              ; parameter block: its size,
PB_NAME         equ     4               ; ... the name's address,
PB_MODE         equ     10              ; ... the mode (PB_LOADM: a DECB binary,
PB_LOADM        equ     2               ;     to its own addresses + PB_BUF),
PB_NLEN         equ     11              ; ... the name's length,
PB_BUF          equ     12              ; ... buffer / load offset,
PB_LEN          equ     14              ; ... length (read / write)
PB_CALLBACK     equ     16              ; ... callback (0 = none)
PB_IN           equ     $40             ; PB_MODE for a data file: input,
PB_OUT          equ     $80             ; ... output (| the file number 1-2)
