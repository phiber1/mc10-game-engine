; stars.asm: a falling star field, for the feeling of flying forward.
;
; Single-pixel stars fall at a few speeds (parallax layers).  A star is
; touched only on frames when it completes a whole row: erase the old
; pixel, move down a row, plot the new one.  Call stars_update before
; spr_update_all: sprites drawn afterwards cover the stars and repair any
; sprite pixel a star's erase touched, so nothing is damaged.
;
; stars_init    place every star at random and plot it
; st_behind     nonzero: the stars pass behind whatever is on the screen
;               (a title's text): a star is plotted only into an empty
;               byte, else it stays undrawn (bit 15 of S_ADDR set) and
;               nothing is erased for it.  Zero (the game): plain.
; #define STAR_TOP n to keep the stars below row n (under a status bar).
; stars_update  once per frame: updates half the stars (alternating), so
;               a star's S_SPD is its speed per two frames.  ~20 cycles per
;               star updated, ~75 when it moves.
;
; The program provides the table (star_tab .. star_end), an even number
; of stars of STAR_SIZE bytes, with S_SPD filled in (rows per update x 256,
; at most $FF: a star moves at most one row per update).

S_ADDR          equ     0               ; screen address of the pixel's byte
S_MASK          equ     2               ; the pixel's bit
S_FRAC          equ     3               ; row fraction
S_SPD           equ     4               ; speed, rows per frame x 256
STAR_SIZE       equ     5

stars_init:
                ldx     #star_tab
-               stx     st_ptr
                jsr     st_rnd          ; random row STAR_TOP-191, column, bit
                andb    #127
                stab    st_m            ; row = 0-127 + (0-63) ...
                jsr     st_rnd
                andb    #63
                addb    st_m
                cmpb    #192-STAR_TOP   ; ... folded into the star field
                bcs     +
                subb    #192-STAR_TOP
+               addb    #STAR_TOP
                clra                    ; D = row * 32 + SCREEN
                aslb
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola
                aslb
                rola
                addd    #SCREEN
                std     st_a
                jsr     st_place        ; random column and bit
                ldx     st_a
                bsr     st_plot         ; plot (or not, behind something)
                ldx     st_ptr
                ldd     st_a
                std     S_ADDR,x
                ldaa    st_m
                staa    S_MASK,x
                ldab    #STAR_SIZE
                abx
                cpx     #star_end
                bne     -
                rts

stars_update:                           ; half the stars per call (alternating,
                ldx     #star_tab       ; so calling it n times a frame makes
                com     st_half         ; the stars n/2 times as fast)
                beq     st_loop
                ldab    #STAR_SIZE      ; odd frames: the odd stars
                abx
st_loop:
                ldaa    S_FRAC,x
                adda    S_SPD,x
                staa    S_FRAC,x
                bcc     st_next         ; not a whole row yet: nothing to draw
                stx     st_ptr
                ldaa    S_MASK,x
                staa    st_m
                ldd     S_ADDR,x
                bmi     st_undrawn      ; (behind something: nothing to erase)
                ldx     S_ADDR,x
                ldab    st_m            ; erase the old pixel
                comb
                andb    0,x
                stab    0,x
                bra     st_down
st_undrawn:     anda    #$7F
                std     st_a
                ldx     st_a
st_down:        ldab    #ROW_BYTES      ; down a row
                abx
                cpx     #SCREEN_END
                bcs     +
                ldx     #SCREEN+STAR_TOP*ROW_BYTES ; off the bottom: back in at
                stx     st_a            ; the top, at a new random column
                bsr     st_place
                ldx     st_a
+               bsr     st_plot         ; plot the new pixel
                ldx     st_ptr
                ldd     st_a
                std     S_ADDR,x
                ldaa    st_m
                staa    S_MASK,x
st_next:
                ldab    #2*STAR_SIZE
                abx
                cpx     #star_end       ; (the table has an even number of stars)
                bcs     st_loop
                rts

; st_a += random column (0-31); st_m = the star's pixel: for the slower
; layers (S_SPD < $C0) a single random bit, which artifact color shows as
; an orange or a blue speck; for the fastest layer a bit pair, white.
st_plot:                                ; X = its byte, st_m its bits: plot
                stx     st_a            ; it; st_a = X, or with bit 15 set
                tst     st_behind       ; when it stays hidden (behind)
                beq     st_plot_f1
                tst     0,x
                beq     st_plot_f1
                ldaa    st_a
                oraa    #$80
                staa    st_a
                rts
st_plot_f1:     ldaa    0,x
                oraa    st_m
                staa    0,x
                rts

st_place:
                bsr     st_rnd
                andb    #31
                addb    st_a+1          ; row starts are multiples of 32
                stab    st_a+1
                bsr     st_rnd
                ldx     st_ptr
                ldaa    S_SPD,x
                cmpa    #$C0
                bcc     +
                andb    #7              ; a single bit
                ldaa    #$80
                bra     ++
+               andb    #6              ; a pair: bit position 0, 2, 4, 6
                ldaa    #$C0
+
-               tstb
                beq     +
                lsra
                decb
                bra     -
+               staa    st_m
                rts

st_rnd:                                 ; B = a random byte (16-bit LFSR,
                pshx                    ; stepped 8 bits per byte: one step
                ldx     #8              ; at a time, consecutive bytes are
                ldd     st_seed         ; shifted copies of each other and the
-               lsrd                    ; stars line up diagonally)
                bcc     +
                eora    #$B4
+               dex
                bne     -
                std     st_seed
                pulx
                rts
