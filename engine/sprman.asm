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
; #define OBJ_EXTRA before including layout.inc to give every object
; extra bytes (from O_USER) for game state.
;
; spr_update_all  move every active object by its velocity and draw it.
;                 If sm_band is nonzero, sm_dirty is incremented for every
;                 object over rows 0..sm_band-1 (or above the top), so a
;                 program can redraw a status bar there in front of sprites.
; obj_erase       X = object: clear its image at its current position (to
;                 remove it, or before moving it further than its halo).
;                 Counts in sm_dirty like a drawing over the band.
;
; A sprite descriptor (spritec makes one for every halo sprite: NAME_dsc):
;   fdb NAME_hr     draw table (halo routines; any spritec table works)
;   fdb NAME_er     erase table
;   fdb spr_mono    call: spr_mono or spr_art
;   fcb PADX, PADY, VW, VH  halo padding across and down, visible width
;                   and height (for hit_test; optional for objects that
;                   never collide)
;
; hit_test        ht_a, ht_b = objects: carry set if their visible boxes
;                 overlap.  Uses A, B, X.

O_X             equ     0               ; x pixel   } 8.8
O_XF            equ     1               ; x fraction}
O_Y             equ     2               ; y pixel   } 8.8
O_YF            equ     3               ; y fraction}
O_DX            equ     4               ; dx, signed 8.8
O_DY            equ     6               ; dy, signed 8.8
O_SPR           equ     8               ; descriptor address, 0 = free slot
O_USER          equ     10              ; first byte of the game's own data
OBJ_SIZE        equ     10+OBJ_EXTRA    ; #define OBJ_EXTRA n for n game bytes

D_DRAW          equ     0
D_ERASE         equ     2
D_CALL          equ     4
D_PADX          equ     6
D_PADY          equ     7
D_VW            equ     8
D_VH            equ     9

spr_update_all:
                ldd     #0              ; no descriptor cached yet
                std     sm_desc
                ldx     obj_first
sm_loop:
                stx     sm_obj
                ldd     O_SPR,x
                beq     sm_next         ; free slot
                subd    sm_desc         ; same type as the last object?
                beq     +               ; (usual in a wave): reuse its setup
                ldd     O_SPR,x
                std     sm_desc
                ldx     sm_desc
                ldd     D_CALL,x
                std     sm_call+1
                ldx     D_DRAW,x
                stx     sm_tab
                ldx     sm_obj
+               ldd     O_X,x           ; x += dx
                addd    O_DX,x
                std     O_X,x
                ldd     O_Y,x           ; y += dy
                addd    O_DY,x
                std     O_Y,x
                cmpa    sm_band         ; over the top band (rows 0 to sm_band-1,
                bcs     sm_inband       ; or coming in from above)?  Tell the
                cmpa    #224            ; program: it may want to repair it
                bcs     sm_draw
sm_inband:      inc     sm_dirty
sm_draw:
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
                ldd     #0              ; (uses sm_tab: drop spr_update_all's cache)
                std     sm_desc
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
                cmpb    sm_band         ; erasing over the top band (or from
                bcs     oe_band         ; above) needs repairing too, even
                cmpb    #224            ; if nothing is drawn there after
                bcs     oe_go
oe_band:        inc     sm_dirty
oe_go:          ldx     sm_tab
oe_call:
                jmp     oe_call         ; patched (tail call)
+               rts

; Visible boxes overlap when, on each axis,
;   (a_left - b_left + a_width - 1) < (a_width + b_width - 1)
; as unsigned bytes (a negative difference wraps to a large value).
hit_test:
                ldx     ht_a
                ldaa    O_X,x
                ldab    O_Y,x
                ldx     O_SPR,x
                adda    D_PADX,x        ; a's visible left, top
                addb    D_PADY,x
                std     ht_al
                ldaa    D_VW,x
                ldab    D_VH,x
                std     ht_aw
                ldx     ht_b
                ldaa    O_X,x
                ldab    O_Y,x
                ldx     O_SPR,x
                adda    D_PADX,x        ; b's visible left, top
                addb    D_PADY,x
                std     ht_bl
                ldaa    ht_al           ; x axis
                suba    ht_bl
                adda    ht_aw
                deca
                staa    ht_v
                ldaa    ht_aw
                adda    D_VW,x
                deca
                cmpa    ht_v
                bls     ht_miss
                ldaa    ht_al+1         ; y axis
                suba    ht_bl+1
                adda    ht_aw+1
                deca
                staa    ht_v
                ldaa    ht_aw+1
                adda    D_VH,x
                deca
                cmpa    ht_v
                bls     ht_miss
                sec
                rts
ht_miss:
                clc
                rts

; ---------------------------------------------------------------- animation
; An object can play a list of frames (an explosion, say):
;
;   fdb DESC        sprite descriptor for this frame
;   fcb FRAMES      how many frames to show it
;   ...
;   fdb 0           end: the object is erased and freed
;
; The animation state lives in the object's game bytes at AN_BASE
; (#define AN_BASE n before layout.inc; it needs 3 bytes).  AN_PTR is 0
; while an object isn't animating.
;
; obj_anim_start  X = object, D = frame list: erase its current image and
;                 start the list
; obj_anim_step   X = object: count down; on a frame change erase and
;                 switch sprite.  Carry set when the list ended (the object
;                 is now free).  Uses A, B, X.
AN_PTR          equ     O_USER+AN_BASE  ; current entry of the frame list
AN_CNT          equ     O_USER+AN_BASE+2 ; frames left in this one

obj_anim_start:
                stx     an_obj
                std     AN_PTR,x
                jsr     obj_erase       ; the old image goes
                ldx     an_obj
                bra     an_load
obj_anim_step:
                stx     an_obj
                dec     AN_CNT,x
                bne     an_keep
                jsr     obj_erase       ; frame change: erase, then next entry
                ldx     an_obj
                ldd     AN_PTR,x
                addd    #3
                std     AN_PTR,x
an_load:
                ldx     AN_PTR,x
                ldd     0,x
                beq     an_end
                std     an_tmp
                ldaa    2,x
                ldx     an_obj
                staa    AN_CNT,x
                ldd     an_tmp
                std     O_SPR,x
an_keep:        clc
                rts
an_end:
                ldx     an_obj          ; the end: free the object
                ldd     #0
                std     O_SPR,x
                std     AN_PTR,x
                sec
                rts
