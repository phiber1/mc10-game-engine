; colswap.asm: swap orange and blue in compiled artifact sprites.
;
; Which color a bit pair shows (10 or 01) depends on the VDG's color
; phase, which on real NTSC hardware can change between power-ups.  Rather
; than keeping a second copy of the art, col_swap walks each sprite's
; compiled halo routines and swaps the two bits of every pixel in every
; data byte.  Masks (ANDA #) cover whole pixels, so they stay.  Running it
; again swaps back.
;
; col_swap      X = 0-terminated list of sprite descriptors (spritec's
;               NAME_dsc for artifact halo sprites): swap their colors.
;               Uses A, B, X.
;
; It decodes only the instructions spritec generates: LDAA/ORAA/EORA #
; (data), LDAB # (data, unless followed by ABX: a row step), LDD # (data),
; ANDA # (mask), LDAA/STAA/STD n,X, CLRA, CLRB, ABX, RTS.

col_swap:
                stx     cs_list
cs_desc:
                ldx     cs_list
                ldx     0,x             ; the next descriptor
                beq     cs_done
                ldx     D_DRAW,x        ; its table of 4 routines (one per shift)
                stx     cs_tab
                ldaa    #4
                staa    cs_n
-               ldx     cs_tab
                ldx     0,x
                bsr     cs_routine
                ldx     cs_tab
                inx
                inx
                stx     cs_tab
                dec     cs_n
                bne     -
                ldx     cs_list
                inx
                inx
                stx     cs_list
                bra     cs_desc
cs_done:        rts

cs_routine:                             ; X = routine: patch it up to its RTS
                ldaa    0,x
                cmpa    #$39            ; RTS
                beq     cs_ret
                cmpa    #$86            ; LDAA #
                beq     cs_one
                cmpa    #$8A            ; ORAA #
                beq     cs_one
                cmpa    #$88            ; EORA #
                beq     cs_one
                cmpa    #$CC            ; LDD #
                beq     cs_two
                cmpa    #$C6            ; LDAB #: data unless a row step
                beq     cs_ldab
                cmpa    #$4F            ; CLRA, CLRB, ABX: one byte
                beq     cs_len1
                cmpa    #$5F
                beq     cs_len1
                cmpa    #$3A
                beq     cs_len1
cs_len2:        inx                     ; ANDA #, LDAA/STAA/STD n,X: skip
cs_len1:        inx
                bra     cs_routine
cs_ldab:
                ldaa    2,x
                cmpa    #$3A            ; followed by ABX: a row step
                beq     cs_len2
cs_one:
                ldab    1,x
                bsr     cs_swap
                stab    1,x
                bra     cs_len2
cs_two:
                ldab    1,x
                bsr     cs_swap
                stab    1,x
                ldab    2,x
                bsr     cs_swap
                stab    2,x
                inx
                bra     cs_len2
cs_ret:         rts

cs_swap:                                ; B = B with each bit pair swapped
                pshb
                andb    #$AA
                lsrb
                stab    cs_t
                pulb
                andb    #$55
                aslb
                orab    cs_t
                rts
