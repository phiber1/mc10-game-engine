; flight.asm: scripted flight paths for sprite manager objects.
;
; An object flies by heading and turn rate: every frame its heading moves
; by its turn rate and its velocity is set from the heading and speed.
; A short script drives the turn rate, so a whole swooping path is a few
; bytes, and every object following the same script flies the same path.
;
; Headings are 0-255: 0 = right, 64 = down, 128 = left, 192 = up.
; Speeds: 0 = 2 px/frame, 1 = 1 px/frame, 2 = 0.5 px/frame.
;
; Object fields (game bytes from O_USER; #define OBJ_EXTRA >= FL_BYTES):
F_ANG           equ     O_USER          ; heading
F_TURN          equ     O_USER+1        ; heading change per frame (signed)
F_CNT           equ     O_USER+2        ; frames left in this P_FLY
F_SPD           equ     O_USER+3        ; speed (0-2)
F_PC            equ     O_USER+4        ; 2 bytes: the next script byte
FL_BYTES        equ     6
;
; Script commands:
P_FLY           equ     0               ; P_FLY, frames, turn: fly, turning
P_HEAD          equ     1               ; P_HEAD, heading
P_SPEED         equ     2               ; P_SPEED, speed
P_GOTO          equ     3               ; P_GOTO, address (2 bytes)
P_AIM           equ     4               ; P_AIM: head for (fl_tx, fl_ty)
P_EVENT         equ     5               ; P_EVENT, n: fl_event = n for the game
;
; fl_start      X = object, D = script: start flying it
; fl_step       X = object: one frame (run commands, turn, set velocity).
;               Returns fl_event (0 = none) for the game to act on.
;               Uses A, B, X.
; fl_velocity   X = object: set O_DX, O_DY from F_ANG and F_SPD
; fl_aim        X = object: F_ANG = heading from the object to (fl_tx, fl_ty)
;
; fl_tx, fl_ty: a target for P_AIM (the game keeps it on the player).

fl_start:
                std     F_PC,x
                clr     F_CNT,x
                clr     F_TURN,x
                rts

fl_step:
                stx     fl_obj
                clr     fl_event
                ldaa    F_CNT,x
                bne     fl_fly
fl_fetch:
                ldx     fl_obj          ; run commands until a P_FLY
                ldx     F_PC,x
                ldaa    0,x
                beq     fl_cmd_fly      ; P_FLY = 0
                cmpa    #P_HEAD
                beq     fl_cmd_head
                cmpa    #P_SPEED
                beq     fl_cmd_speed
                cmpa    #P_GOTO
                beq     fl_cmd_goto
                cmpa    #P_AIM
                beq     fl_cmd_aim
                ; P_EVENT
                ldaa    1,x
                staa    fl_event
                ldab    #2
fl_adv:         abx                     ; X = script: advance by B
                stx     fl_pc
                ldx     fl_obj
                ldd     fl_pc
                std     F_PC,x
                bra     fl_fetch
fl_cmd_head:
                ldaa    1,x
                ldx     fl_obj
                staa    F_ANG,x
                ldx     F_PC,x
                ldab    #2
                bra     fl_adv
fl_cmd_speed:
                ldaa    1,x
                ldx     fl_obj
                staa    F_SPD,x
                ldx     F_PC,x
                ldab    #2
                bra     fl_adv
fl_cmd_goto:
                ldd     1,x
                ldx     fl_obj
                std     F_PC,x
                bra     fl_fetch
fl_cmd_aim:
                ldx     fl_obj
                jsr     fl_aim
                ldx     fl_obj
                ldx     F_PC,x
                ldab    #1
                bra     fl_adv
fl_cmd_fly:
                ldd     1,x             ; frames, turn
                inx
                inx
                inx
                stx     fl_pc
                ldx     fl_obj
                staa    F_CNT,x
                stab    F_TURN,x
                ldd     fl_pc
                std     F_PC,x
fl_fly:
                dec     F_CNT,x
                ldaa    F_ANG,x
                adda    F_TURN,x
                staa    F_ANG,x
                ; fall through

fl_velocity:
                stx     fl_obj
                ldab    F_ANG,x         ; dx = 2 cos = 2 sin(a + 64)
                addb    #64
                bsr     fl_sin
                ldx     fl_obj
                bsr     fl_scale
                std     O_DX,x
                ldab    F_ANG,x         ; dy = 2 sin
                bsr     fl_sin
                ldx     fl_obj
                bsr     fl_scale
                std     O_DY,x
                rts

fl_scale:                               ; X = object: D >>= F_SPD (0-2)
                tst     F_SPD,x
                beq     +
                asra
                rorb
                pshb
                ldab    F_SPD,x
                cmpb    #1
                pulb                    ; (PULB keeps the flags)
                beq     +
                asra
                rorb
+               rts

fl_sin:                                 ; B = angle -> D = 2 sin, 8.8
                clra
                aslb
                rola
                addd    #sintab
                std     fl_pc
                ldx     fl_pc
                ldd     0,x
                rts

; Heading toward (fl_tx, fl_ty) from the object's position, to within a
; couple of degrees: the octant from the signs, the angle within it from
; atan of the smaller/larger ratio (5-bit, by shift-and-subtract).
fl_aim:
                stx     fl_obj
                clr     fl_oct
                ldaa    fl_tx           ; dx = tx - x
                suba    O_X,x
                bcc     +               ; target to the left: negate
                nega
                inc     fl_oct          ; bit 0: dx < 0
+               staa    fl_adx
                ldaa    fl_ty           ; dy = ty - y
                suba    O_Y,x
                bcc     +
                nega
                ldab    fl_oct
                orab    #2              ; bit 1: dy < 0
                stab    fl_oct
+               staa    fl_ady
                cmpa    fl_adx          ; |dy| > |dx|: angle from the y axis
                bhi     +
                ldab    fl_adx          ; ratio = |dy| / |dx|
                bsr     fl_ratio
                bra     ++
+               ldaa    fl_adx          ; ratio = |dx| / |dy|
                ldab    fl_ady
                bsr     fl_ratio
                nega                    ; angle = 64 - atan
                adda    #64
+               ldab    fl_oct          ; mirror into the right quadrant
                bitb    #1
                beq     +
                nega                    ; dx < 0: 128 - angle
                adda    #128
+               bitb    #2
                beq     +
                nega                    ; dy < 0: -angle
+               ldx     fl_obj
                staa    F_ANG,x
                rts

; A = smaller, B = larger (both 0-255) -> A = atan(A/B) in heading units
; (0-32 for 0-45 degrees)
fl_ratio:
                stab    fl_den
                cmpa    fl_den
                bne     +
                ldaa    #32             ; equal: 45 degrees
                bra     fl_atan
+               tsta
                beq     fl_atan         ; 0: straight along the axis
                tab                     ; D = numerator (A = 0, B = num)
                clra
                ldx     #5              ; 5 quotient bits
                clr     fl_q
-               aslb                    ; num <<= 1
                rola
                asl     fl_q
                tsta                    ; num >= den? (num < 2*den < 512)
                bne     +
                cmpb    fl_den
                bcs     ++
+               subb    fl_den
                sbca    #0
                inc     fl_q
+               dex
                bne     -
                ldaa    fl_q            ; 0-31
fl_atan:
                ldx     #atantab
                tab
                abx
                ldaa    0,x
                rts

; atan(i/32) in heading units (256 = full circle), i = 0..32
atantab:
i               set     0
                rept    33
                fcb     int(atan(i/32.0)*128.0/3.14159265358979+0.5)
i               set     i+1
                endm

                if      OBJ_EXTRA < FL_BYTES
                error   "flight.asm needs #define OBJ_EXTRA of at least FL_BYTES (6)"
                endif
