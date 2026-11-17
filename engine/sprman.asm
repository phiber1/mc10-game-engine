; sprman.asm: the sprite manager.
;
; Objects live in a table the game provides (obj_first .. obj_end, in the
; direct page).  Table order is priority: each object is drawn in front of
; the ones before it, so put the lowest priority first.
;
; Positions and velocities are 8.8 fixed point (pixel byte, then fraction
; byte), so one LDD / ADDD / STD moves an axis and speeds can be fractions
; of a pixel.  With halo sprites, keep |dx| and |dy| <= the halo width
; ($0100 = 1 pixel per frame for a 1-pixel halo): the halo then always
; erases the previous position, and nothing ever needs a separate erase.
;
; spr_update_all  move every active object by its velocity and draw it
; obj_erase       X = object: clear its image at its current position (to
;                 remove it, or before moving it further than its halo)
;
; A sprite descriptor is three words:
;   fdb NAME_hr     draw table (halo routines; any spritec table works)
;   fdb NAME_er     erase table
;   fdb spr_mono    call: spr_mono or spr_art

O_X             equ     0               ; x pixel   } 8.8
O_XF            equ     1               ; x fraction}
O_Y             equ     2               ; y pixel   } 8.8
O_YF            equ     3               ; y fraction}
O_DX            equ     4               ; dx, signed 8.8
O_DY            equ     6               ; dy, signed 8.8
O_SPR           equ     8               ; descriptor address, 0 = free slot
OBJ_SIZE        equ     10

D_DRAW          equ     0
D_ERASE         equ     2
D_CALL          equ     4

spr_update_all:
                ldx     obj_first
sm_loop:
                stx     sm_obj
                ldd     O_SPR,x
                beq     sm_next         ; free slot
                std     sm_desc
                ldd     O_X,x           ; x += dx
                addd    O_DX,x
                std     O_X,x
                ldd     O_Y,x           ; y += dy
                addd    O_DY,x
                std     O_Y,x
                ldx     sm_desc
                ldd     D_CALL,x
                std     sm_call+1
                ldx     D_DRAW,x
                stx     sm_tab
                ldx     sm_obj
                ldaa    O_X,x
                ldab    O_Y,x
                ldx     sm_tab
sm_call:
                jsr     sm_call         ; patched: spr_mono or spr_art
sm_next:
                ldx     sm_obj
                ldab    #OBJ_SIZE
                abx
                cpx     obj_end
                bne     sm_loop
                rts

obj_erase:
                stx     sm_obj
                ldx     O_SPR,x
                beq     +
                ldd     D_CALL,x
                std     oe_call+1
                ldx     D_ERASE,x
                stx     sm_tab
                ldx     sm_obj
                ldaa    O_X,x
                ldab    O_Y,x
                ldx     sm_tab
oe_call:
                jmp     oe_call         ; patched (tail call)
+               rts
