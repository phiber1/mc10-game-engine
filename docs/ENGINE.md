# mc10-game-engine reference

A sprite and sound engine for full-screen graphics games on the TRS-80
MC-10, in 6803 assembly.  This document is for people writing programs
with it.  Each module's source also starts with a summary of its calls.

Contents: [Requirements](#requirements) ·
[Memory and loading](#memory-and-loading) ·
[A program's skeleton](#a-programs-skeleton) ·
[Graphics modes](#graphics-modes) ·
[The frame tick](#the-frame-tick) · [Sprites](#sprites) ·
[The sprite manager](#the-sprite-manager) ·
[Other modules](#other-modules) · [Sound](#sound) ·
[Debugging and measuring](#debugging-and-measuring)

## Requirements

* **An MC-10 with the internal 8K RAM mod and an MCX32-SD.**  The 8K mod
  lets the VDG show a full 6K screen (`$4000-$57FF`); the MCX32-SD loads
  the programs, provides the RAM hook for the timer interrupt and gives
  the low segment at `$0400-$1FFF`.
* **To build:** [ASL](http://john.ccac.rwth-aachen.de:8000/as/) (`asl`), a
  C compiler (for cpp and the tools), make and Python 3.
* **To run on a PC:** the [VMC10 for Linux](https://github.com/phiber1/vmc10-linux)
  emulator (`--8k --mcx32sd`).  `make run-NAME` uses it.

## Memory and loading

| Address | Use |
|---|---|
| `$0080-$00FF` | 6803 internal RAM: the engine's direct-page variables |
| `$0200-$03FF` | MCX BASIC's hooks and variables (`LOADM` needs them) |
| `$0400-$1FFF` | LOW: an optional second segment (MCX32-SD SRAM, 7K) |
| `$2000-$3FFF` | MCX32-SD flash (BIOS); `$3C00-$3FFF` doubles as the top sprite gutter |
| `$4000-$57FF` | the screen (32 bytes x 192 rows) |
| `$5800-$5BFF` | the bottom sprite gutter (hidden rows 192-223) |
| `$5C00-$5EFF` | BSS: ordinary variables (`org BSS`) |
| `$5F00-$5FFF` | the stack |
| `$6000-$ADFF` | CODE: the main segment (19.5K) |

Every `bench/NAME.asm` builds `build/NAME.bin`, a DECB binary with a main
segment at `$6000` and, if used, a low one at `$0400`.  The build refuses
any byte outside those two ranges.  Copy the `.BIN` to the SD card and
type `RUNM"NAME"` (or `LOADM"NAME"` then `EXEC`).

Sources go through cpp first (`#include`, `#define`, `#if`), then ASL
(`cpu 6801`: the 6803 is a ROM-less 6801).  `engine/layout.inc` must be
included first; it sets up the CPU, the memory layout and the direct-page
variables, and includes `hw.inc` (hardware), `macros.inc` and `notes.inc`.

## A program's skeleton

```
#define GFX_MODE GFX_CG6        ; optional: see Graphics modes
#define GFX_BG CG_BLUE
#include "layout.inc"

                org     BSS
score           rmb     3               ; your variables

                org     CODE
start:          sei
                lds     #STACK_TOP
                jsr     gfx_init        ; the mode, the screen cleared
                ldx     #objs           ; the sprite manager's table
                stx     obj_first
                ldx     #objs_end
                stx     obj_end
                jsr     frame_init      ; the tick (interrupts on)
loop:           jsr     frame_wait      ; once per 60 Hz frame
                jsr     snd_frame
                jsr     kbd_read
                ...                     ; game logic
                jsr     spr_update_all  ; move and draw every sprite
                bra     loop

#include "gfx.asm"
#include "frame.asm"
#include "sound.asm"
#include "input.asm"
#include "text.asm"
#include "sprite.asm"
#include "sprman.asm"
#include "mygame_spr.inc"               ; from sprites/mygame.spr
```

`bench/cg6demo.asm` is a complete small program in this shape.

## Graphics modes

Choose the mode with defines **before** including `layout.inc`.  The
choice is made when assembling, so it costs nothing while running.

| `GFX_MODE` | Screen | Colors | Notes |
|---|---|---|---|
| `GFX_MONO` | RG6, 256x192 | 2: black and green (`GFX_CSS` 0) or buff (1) | sharpest; sprite x 0-255 |
| `GFX_ARTIFACT` (default) | RG6 with CSS=1, 128x192 | 4: black, orange, blue, white | **NTSC only**: the colors are artifacts of the NTSC signal, so PAL machines show stripes |
| `GFX_CG6` | CG6, 128x192 | 4 real colors: green, yellow, blue, red (`GFX_CSS` 0) or buff, cyan, magenta, orange (1) | NTSC and PAL alike; **no black** |

* `GFX_CSS`: the VDG's color set (default 1, or 0 in CG6).
* `GFX_BG`: the background color, as a pixel value (default 0: black in
  RG6, green or buff in CG6).  For CG6 use `CG_GREEN`, `CG_YELLOW`,
  `CG_BLUE`, `CG_RED` (CSS=0) or `CG_BUFF`, `CG_CYAN`, `CG_MAGENTA`,
  `CG_ORANGE` (CSS=1).
* `layout.inc` then defines `GFX_VDG` (the VDG byte), `GFX_FILL` (a byte
  of background pixels) and `GFX_2BPP` (1 in the 4-color modes, where
  sprite x runs 0-127).  `COLOR_BYTE(c)` is a byte of four pixels of color
  `c`, e.g. for `txt_col`.

`engine/gfx.asm`:

| Call | Does |
|---|---|
| `gfx_init` | set the VDG (and `vdg_shadow`) to the mode, then `gfx_cls` |
| `gfx_cls` | fill the screen with the background color |
| `gfx_css` | A = 0 or 1: switch the color set, keeping the mode and the speaker bit |

**Background colors.**  The halo sprites erase to the background, so a
plain background of any color costs no extra time: spritec builds the
color into the sprite code (its `bg` option, see below).  Text draws onto
the background color too.  Three things still assume a background of 0:
spritec's OR, XOR and delta routines, the star field (`stars.asm`), and
the artifact color swap (`colswap.asm`, which is for artifact mode only).
In CG6 the border around the picture is always green (CSS=0) or buff
(CSS=1).

## The frame tick

`frame.asm`: one output-compare interrupt drives both the 60 Hz frame tick
and the sound.  `frame_init` installs it (through MCX BASIC's RAM hook at
`$0206`) and returns with interrupts on; `frame_wait` waits for the next
tick; `frame_count` (direct page) counts ticks.  The interrupt keeps two
countdowns, to the next speaker event and to the next tick, and is set for
whichever comes first, so ticks stay exactly 14,934 cycles apart whatever
sound is playing (even a very low tone).

A frame is 14,934 CPU cycles (262 lines of 57 cycles).  The MC-10 doesn't
connect the VDG's field sync to the CPU, so the tick's phase against the
picture is unknown on real hardware.  The engine is built for that: it
never races the beam, and its sprites are drawn so that an object never
disappears between being erased and redrawn (see halo sprites), which is
what makes flicker and tearing invisible.

## Sprites

### Sprite files

`tools/spritec` compiles text-art sprites (`sprites/NAME.spr`) into
unrolled 6803 code (`build/NAME_spr.inc`): no loops, no shifting at run
time; one routine per sub-byte position.

```
sprite NAME MODE [halo N | halo X Y] [pad N] [delta] [shift S] [bg C] [noerase]
<rows of art>
end
```

| `MODE` | Letters | Pixels per byte |
|---|---|---|
| `mono` | `X` = set | 8 |
| `artifact` | `O` orange, `B` blue, `W` white | 4 |
| `cg6` | `G` green, `Y` yellow, `B` blue, `R` red (CSS=0); `W` buff, `C` cyan, `M` magenta, `O` orange (CSS=1) | 4 |

`.` (or a space) is transparent.  Options:

* `halo N` (or `halo X Y`, across and down): **the recommended kind.**
  The sprite plus a halo (its shape grown by N pixels) in one
  read-modify-write pass.  The halo clears the sprite's previous position
  as long as it moves at most N pixels a frame, so there is no separate
  erase and the sprite is never missing.  Draw in priority order: each
  sprite covers the ones drawn before it, with a thin background-colored
  outline.  A 1-pixel halo suits most sprites.  Halo sprites get a draw
  table `NAME_hr`, an erase table `NAME_er` and a sprite manager
  descriptor `NAME_dsc`.
* `pad N`: a blank border stored with the sprite (`NAME_sr`), which wipes
  the old position as it draws: the cheapest kind, for sprites that rarely
  overlap.
* `delta`: XOR routines that move the sprite one pixel in any direction in
  one pass (`NAME_dt`): never flickers, cost proportional to what changes.
* `shift S`: compile only sub-byte position S, for big sprites that never
  move sideways (saves 3/4 of the code in 4-color modes, 7/8 in mono).
* `bg C`: the background color (a letter of the mode).  The halo, erase
  and store routines fill with it.  Default: pixel value 0.
* `noerase`: halo sprites without their erase routines (`NAME_er`), for
  programs that erase by redrawing what's behind (the descriptor's erase
  entry is 0, so don't `obj_erase` them).  `halo 0` with `noerase` makes a
  plain masked sprite: only its own pixels drawn, about half the code.

Every sprite also gets OR (`NAME_or`) and XOR (`NAME_xr`) routines unless
it has a halo, and the constants `NAME_W`, `NAME_H` (including the
padding), `NAME_SHIFTS`, `NAME_PADX`, `NAME_PADY`.  `spritec -e` writes
only the constants (for code assembled elsewhere, such as an overlay).

To look at a sprite file without writing a program:
`make run-view VIEW=sprites/NAME.spr` shows each sprite once, in the
file's mode and background.

### Drawing

`sprite.asm`: `spr_mono` (x 0-255) and `spr_art` (x 0-127, used for
both 4-color modes) take A = x, B = y and X = a routine table, pick the
routine for the sub-byte position and call it (about 60 cycles plus the
routine).  Usually the sprite manager calls these for you.

**Gutters:** y values 192-223 address hidden memory below the screen and
224-255 (y = -32..-1) the flash above it, which ignores writes, so sprites
can slide on and off the top and bottom edges whole.  A sprite must stay
within 32 rows of the screen, and nothing else may use `$5800-$5BFF`.

### Speed

Measured in the emulator, erasing, moving and redrawing every sprite each
frame on a black background:

| Sprite | Method | Cycles each | Per 60 Hz frame |
|---|---|---|---|
| 16x16 mono | OR draw, clear erase | ~760 | 18 |
| 8x16 4-color | OR draw, clear erase | ~730 | 20 |
| 16x16 mono, `pad 3` | self-erasing store | ~463 | 32 |
| 8x16 4-color, `pad 3` | self-erasing store | ~507 | 29 |
| 16x16 mono, `halo 1` | halo, via the sprite manager, with simple game logic | ~690 | 16 use 74% of a frame |

A non-zero `bg` adds at most 2 cycles to a few bytes per halo sprite.

## The sprite manager

`sprman.asm` moves and draws a table of objects that the program provides
(`obj_first` .. `obj_end`, direct page).  **Table order is priority:**
later objects are drawn in front of earlier ones.

An object (`OBJ_SIZE` bytes): `O_X`, `O_Y` positions and `O_DX`, `O_DY`
velocities in 8.8 fixed point (one `LDD`/`ADDD`/`STD` moves an axis;
speeds can be fractions of a pixel), and `O_SPR`, the sprite descriptor
(0 = an empty slot).  `#define OBJ_EXTRA n` before `layout.inc` adds n
bytes per object from `O_USER` for the game's own state.

| Call | Does |
|---|---|
| `spr_update_all` | move every object by its velocity and draw it |
| `obj_erase` | X = object: clear its image (to remove it, or before a jump further than its halo) |
| `hit_test` | `ht_a`, `ht_b` = objects: carry set if their visible boxes overlap |

With halo sprites keep `|dx|` and `|dy|` at most the halo width (`$0100`
= 1 pixel a frame for `halo 1`).  `sm_band` (rows) and `sm_dirty` let a
program redraw a status bar at the top after a sprite crosses it.

A descriptor: `fdb draw table, erase table, spr_mono or spr_art` then
`fcb pad x, pad y, visible width, visible height` (for `hit_test`).
spritec writes one for every halo sprite.

## Other modules

| Module | What it gives |
|---|---|
| `text.asm` | `txt_char`, `txt_str`, `txt_bcd`, double-height `txt_char2` / `txt_str2`, with the 3x5 font in `font.asm` (ASCII 32-90).  32 characters a line; `TXT_AT(row, col)` assembles a screen address.  `txt_col` picks the color: `COLOR_BYTE(c)`, or `TXT_WHITE` / `TXT_ORANGE` / `TXT_BLUE` in artifact mode.  Letters draw onto the background color. |
| `input.asm` | `kbd_read`: W A S Z and SPACE into `joy` (`J_UP`, `J_DOWN`, `J_LEFT`, `J_RIGHT`, `J_FIRE`).  The emulator maps the arrow keys to W A S Z, and a PI-KEY10's joystick 1 sends the same keys. |
| `flight.asm` | scripted flight paths: an object flies by heading and turn rate, driven by a few bytes of script, so a swooping attack path is tiny.  `#define FL_HALFX 1` in the 4-color modes. |
| `stars.asm` | a falling parallax star field (`stars_init`, `stars_update`), optionally passing behind text (`st_behind`).  Needs a background of 0. |
| `colswap.asm` | `col_swap`: swaps orange and blue in compiled artifact sprites, for NTSC machines that start in the other color phase. |
| `sintab.asm` | 2 sin(angle) in 8.8 for angles 0-255. |
| `hw.inc` | hardware registers, VDG bits, and the MCX32-SD BIOS entry and parameter block (`MCX_BIOS`, `BIOS_OPEN`, `BIOS_READ`, `BIOS_WRITE`, `BIOS_LOAD`, ...), for loading overlays and reading or writing files on the SD card.  [StarFall](https://github.com/phiber1/proj-starfall) uses them for its boss overlays and high score file. |

## Sound

`sound.asm` plays sound effects on the interrupt in `frame.asm`, so the
game keeps running while they play.

| Call | Does |
|---|---|
| `snd_play` | X = effect, A = priority: start it unless a higher-priority effect is playing |
| `snd_frame` | call once a frame: steps the effect |
| `snd_stop` | silence |

An effect is a list of segments ending with a 0 byte:

```
                fcb     FRAMES, MODE    ; SND_TONE, SND_NOISE or SND_REST
                fdb     HALF, SWEEP     ; half-period in cycles; added to HALF each frame
```

A tone's frequency is 447443 / HALF Hz; `notes.inc` names the notes
(`N_C5` ...).  Each half-period costs an interrupt of about 100 cycles, so
a sound costs roughly 100 / HALF of the CPU (C4 ~6%, C6 ~37%).  Keep HALF
at or above `SND_MIN_HALF` (150), and keep sounds that play often low.

## Debugging and measuring

* **Debug port:** with `DEBUG=1` (the default build), `DBGA` / `DBGB` write
  a register to `$BE00`, which the emulator can log
  (`--debug-port BE00,FILE`; `make log-NAME` runs headless and prints the
  log).  `make DEBUG=0` leaves them out.
* **CPU meter:** build with `METER=1` and bracket the frame's work with
  `METER_ON` / `METER_OFF`: the picture's color set flips while working,
  showing how much of each frame is used.
* **Headless runs:** the emulator's `headless` harness runs a program
  without a window, types keys, pokes memory, and saves screenshots
  (`ppm:FILE`), for automated tests.

## Licence

Public domain, under the [Unlicense](../LICENSE).
