; input.asm: keyboard as a joystick.
;
; kbd_read      read W A S Z (the emulator's arrow keys) and SPACE into
;               joy (direct page): J_UP, J_DOWN, J_LEFT, J_RIGHT, J_FIRE.
;               About 70 cycles.  Uses A, B.
;
; The MC-10 keyboard is an 8x7 matrix: writing port 1 with one bit low
; selects a column, and reading $BFFF gives the rows (0 = pressed).

J_UP            equ     $01
J_DOWN          equ     $02
J_LEFT          equ     $04
J_RIGHT         equ     $08
J_FIRE          equ     $10

kbd_read:
                clrb
                ldaa    #$FF-$80        ; column 7: W (row 2), SPACE (row 3)
                staa    P1DAT
                ldaa    KBD
                bita    #$04
                bne     +
                orab    #J_UP
+               bita    #$08
                bne     +
                orab    #J_FIRE
+               ldaa    #$FF-$02        ; column 1: A (row 0)
                staa    P1DAT
                ldaa    KBD
                bita    #$01
                bne     +
                orab    #J_LEFT
+               ldaa    #$FF-$08        ; column 3: S (row 2)
                staa    P1DAT
                ldaa    KBD
                bita    #$04
                bne     +
                orab    #J_RIGHT
+               ldaa    #$FF-$04        ; column 2: Z (row 3)
                staa    P1DAT
                ldaa    KBD
                bita    #$08
                bne     +
                orab    #J_DOWN
+               ldaa    #$FF            ; deselect all columns
                staa    P1DAT
                stab    joy
                rts
