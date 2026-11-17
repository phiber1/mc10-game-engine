; sintab.asm: 2 sin(angle) in 8.8 fixed point for angle 0-255
; (64 = 90 degrees; with y growing down the screen, 64 points down).
sintab:
i               set     0
                rept    256
                fdb     int(512.0*sin(i*3.14159265358979/128.0))
i               set     i+1
                endm
