; game_sfx.inc: the game's sound effects and jingles (bench/game.asm),
; shared with the sound board (bench/sfx.asm) so it plays the real ones.
; Sound effects
fx_zap:         fcb     8, SND_TONE
                fdb     450, 70
                fcb     0
fx_boom:        fcb     4, SND_NOISE
                fdb     400, 0
                fcb     24, SND_NOISE
                fdb     600, 30
                fcb     0
fx_drop:        fcb     6, SND_TONE     ; a short falling blip
                fdb     700, 60
                fcb     0
; Jingles (priority 9: nothing interrupts them)
fx_start:                               ; the start fanfare, ~1.6 s
                NOTE    N_C5, 7
                NOTE    N_E5, 7
                NOTE    N_G5, 7
                NOTE    N_C6, 14
                REST    4
                NOTE    N_A5, 7
                NOTE    N_B5, 7
                NOTE    N_C6, 28
                fcb     0
fx_life:                                ; a fresh ship, ~0.8 s
                NOTE    N_G5, 6
                NOTE    N_A5, 6
                NOTE    N_B5, 6
                NOTE    N_D6, 22
                fcb     0
fx_salute:                              ; the victory salute, ~1.8 s
                NOTE    N_G5, 7
                NOTE    N_G5, 5
                NOTE    N_G5, 5
                NOTE    N_C6, 14
                REST    4
                NOTE    N_E6, 8
                NOTE    N_D6, 8
                NOTE    N_E6, 8
                NOTE    N_C6, 30
                fcb     0
fx_finale:                              ; all four bosses beaten: a victory
                NOTE    N_G4, 8         ; march, ~10 s (an original tune)
                NOTE    N_C5, 8
                NOTE    N_E5, 8
                NOTE    N_G5, 8
                NOTE    N_C6, 20
                REST    4
                NOTE    N_E5, 8
                NOTE    N_G5, 8
                NOTE    N_C6, 8
                NOTE    N_E6, 16
                NOTE    N_D6, 8
                NOTE    N_C6, 8
                NOTE    N_D6, 32
                NOTE    N_G5, 8         ; (the dominant)
                NOTE    N_B5, 8
                NOTE    N_D6, 8
                NOTE    N_G5, 8
                NOTE    N_D6, 20
                REST    4
                NOTE    N_B5, 8
                NOTE    N_C6, 8
                NOTE    N_D6, 8
                NOTE    N_E6, 16
                NOTE    N_D6, 8
                NOTE    N_B5, 8
                NOTE    N_C6, 32
                NOTE    N_A5, 8         ; (the subdominant)
                NOTE    N_C6, 8
                NOTE    N_F5, 8
                NOTE    N_A5, 8
                NOTE    N_C6, 16
                NOTE    N_A5, 8
                NOTE    N_F5, 8
                NOTE    N_G5, 16
                NOTE    N_E5, 16
                NOTE    N_F5, 8
                NOTE    N_A5, 8
                NOTE    N_D6, 8
                NOTE    N_C6, 8
                NOTE    N_B5, 16
                NOTE    N_G5, 16
                NOTE    N_C6, 8         ; (home)
                NOTE    N_G5, 8
                NOTE    N_E5, 8
                NOTE    N_G5, 8
                NOTE    N_C6, 8
                NOTE    N_E6, 8
                NOTE    N_D6, 8
                NOTE    N_B5, 8
                NOTE    N_C6, 60
                fcb     0
fx_extra:                               ; an extra ship: three quick, high
                rept    3               ; beeps, like no other sound
                fcb     4, SND_TONE
                fdb     N_E6, 0
                fcb     3, SND_REST
                fdb     0, 0
                endm
                fcb     0
fx_warp:                                ; the afterburner: a rising roar
                fcb     40, SND_NOISE
                fdb     900, -12
                fcb     60, SND_NOISE
                fdb     420, 0
                fcb     0
fx_bossin:                              ; the boss arrives: eight low, falling
                rept    8               ; wails (~4 s; low tones are cheap)
                fcb     24, SND_TONE
                fdb     1200, 16
                fcb     6, SND_REST
                fdb     0, 0
                endm
                fcb     0
fx_ping:                                ; a shot bounces off the hull (kept
                fcb     3, SND_TONE     ; below ~1 kHz: high tones cost CPU)
                fdb     480, 0
                fcb     0
fx_clang:                               ; a hit on the core
                fcb     3, SND_NOISE
                fdb     250, 0
                fcb     8, SND_TONE
                fdb     520, 40
                fcb     0
fx_open:                                ; the core's hatch opens
                NOTE    N_C4, 6
                NOTE    N_G4, 6
                NOTE    N_C5, 12
                fcb     0
fx_bossdie:                             ; the boss goes up: a long roar
                fcb     10, SND_NOISE
                fdb     250, 0
                fcb     110, SND_NOISE
                fdb     380, 4
                fcb     0
fx_shipboom:    fcb     6, SND_NOISE    ; the ship: a long, deep explosion
                fdb     300, 0
                fcb     50, SND_NOISE
                fdb     500, 20
                fcb     0

