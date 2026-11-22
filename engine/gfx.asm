; gfx.asm: the graphics mode (chosen with GFX_MODE, GFX_CSS and GFX_BG
; before including layout.inc; see there).
;
; gfx_init      set the VDG to the chosen mode (and vdg_shadow, which
;               the sound interrupt writes back with the speaker bit), then
;               gfx_cls.  Uses A, B, X.
; gfx_cls       fill the screen with the background color.  Uses A, B, X.
; gfx_css       A = 0 or 1: switch the VDG's color set (CG6: the other
;               palette; MONO: green or buff), keeping the mode and the
;               speaker bit.  Uses A.

gfx_init:
                ldaa    #GFX_VDG
                staa    vdg_shadow
                staa    VDG
gfx_cls:
                ldx     #SCREEN
                ldaa    #GFX_FILL
                tab
gfx_cls_b1:     std     0,x
                std     2,x
                inx
                inx
                inx
                inx
                cpx     #SCREEN_END
                bne     gfx_cls_b1
                rts

gfx_css:
                pshb
                tab                     ; B = 0 or 1
                tpa                     ; (the sound interrupt also writes
                psha                    ; vdg_shadow: keep it out meanwhile)
                sei
                ldaa    vdg_shadow
                anda    #~VDG_CSS&$FF
                tstb
                beq     gfx_css_f1
                oraa    #VDG_CSS
gfx_css_f1:     staa    vdg_shadow
                staa    VDG
                pula
                tap
                pulb
                rts
