# mc10-game-engine: design notes

Working notes for a game engine for the TRS-80 MC-10, starting with RG6
(256x192) games for machines with the internal 8K RAM mod.  Developed with
the VMC10 for Linux emulator (github.com/phiber1/vmc10-linux).

## Goals

* High-performance software sprite engine, and an interrupt-driven sound
  engine.
* Both RG6 colour models: true 256x192 monochrome (CSS=1, buff on black),
  and NTSC artifact 128x192 in four colours (pixel pairs: 00 black,
  11 white, 10/01 orange/blue, phase-dependent).
* First milestone: proof-of-concept benchmarks:
  * how many sprites per event loop at 60 Hz and 30 Hz (8 is typical on
    hardware with sprites; we'll find our real limit);
  * smooth scrolling variants;
  * mono vs artifact.

## Target hardware

* MC-10 with the internal 8K RAM mod (`$4000-$5FFF`).  The RG6 screen
  occupies `$4000-$57FF` (6144 bytes) and the VDG always displays from
  `$4000` (no SAM, so no page flipping).
* Plus an MCX32-SD for RAM: SRAM at `$0020-$1FFF` and `$5000-$AFFF`.  Code
  and data go at `$5800-$AFFF` (about 22K) and `$0400-$1FFF`.  Keep the
  engine portable to the MCX-128 with the 8K GAL.
* Emulator: `vmc10 --mcx32sd --8k` (the `$4200` remap is off by default;
  `--remap` enables it).

## Timing: a VBLANK substitute

* No VBLANK interrupt (the 6847's FS isn't wired to the CPU).
* One frame is exactly **14,934 E cycles**: 262 lines x 228 colour clocks
  = 59,736 crystal ticks, and E = crystal/4.  An output-compare (OCF)
  interrupt that adds 14,934 to OCR each time is phase-locked to the VDG
  and never drifts.  The phase vs the beam is fixed but unknown on real
  hardware; tune it in the emulator.
* Classic VBLANK-style event loop: the ISR sets a frame flag and runs the
  sound sequencer; the main loop waits for the flag, then
  erases/draws/updates in beam-friendly order.
* The 6803 interrupt vectors go through BASIC's RAM hooks (OCF → `$4206`
  in stock BASIC; MCX BASIC 3 moved the hooks to `$0200` page:
  `$0206`).  Or take over the machine entirely.

## Budget and techniques (E cycles)

* 14,934 cycles per frame.  A full-screen clear is about 30K with
  LDD/STD, or about 12K with a `PSHX` stack blast (2 cycles/byte, needs
  SEI: the ISR shares the stack).  So everything is dirty-region based.
* Sprites:
  * compiled sprites (`LDD #imm / STD n,X`, about 5 cycles/byte);
  * pre-shifted copies (8 for mono, 4 for artifact);
  * save-under or background restore;
  * a 192-entry row-address table (no multiply).
* `MUL` as a barrel shifter: `LDAA byte / LDAB #2^n / MUL` gives the byte
  shifted by n across A:B in 10 cycles.  Good for run-time pre-shifting
  and arbitrary-offset scrolls.
* The ASLD/LSRD (D register) trick: 16-bit shifts for sprite rows across a
  byte boundary and the first word of a chain (no carry-in).
* Scrolling, 1 pixel: a ROL/ROR ,X chain costs 6 cycles/byte (192 per
  row); a full screen costs about 36.9K cycles, about 2.5 frames.  So:
  * a scrolling band (48-64 lines);
  * sparse redraw (Defender-style terrain and stars);
  * coarse byte scrolls on alternate frames;
  * or work split in beam order across frames.
* Sound: one OCF channel, scheduling the nearer of the next speaker toggle
  and the next frame tick (an event scheduler).  CPU cost scales with
  pitch (a 1 kHz tone costs about 8%).  Sequencing on the frame tick;
  duty-cycle tricks for timbre.  Never use the ROM's blocking SOUND.

## Toolchain

* ASL (Macro Assembler AS 1.42, `/usr/local/bin/asl`, `p2bin`), with
  `CPU 6801` (ASL has no 6803 entry; the 6803 is a ROM-less 6801).
* make + the C preprocessor for macros and defines:
  `gcc -E -x assembler-with-cpp -P` (tolerant of `'`, `$`, `#`).
* `p2bin` produces a raw binary; wrap it as `.C10` (CLOAD/LOADM) and DECB
  `.BIN` (MCX32-SD LOADM).
* Drop builds into the emulator's SD folder; the headless harness runs
  benchmarks and screenshots.

## Planned layout

```
engine/   frame-tick ISR, sprites, sound, input
bench/    proof-of-concept benchmarks
tools/    bin -> C10 / DECB wrappers, graphics converters
Makefile  cpp -> asl -> p2bin -> wrap; "make bench" runs in the emulator
```

## Emulator support to add (in vmc10-linux)

* An optional **debug port**: writes to a spare address log the cycle count
  and the beam's scan line.  Behind a flag, off by default.  For timing
  routines to the cycle.

## Working style

* The owner is an expert in vintage game programming (arcade and home
  computers, VBLANK-driven event loops, an 1806 chess platform with ASL +
  make + cpp).
* Original games only: no recreations of specific existing games.

## Findings (2026-11-16)

### The frame tick works, but its phase is unknowable on hardware

* `bench/tick`: the OCF tick averages exactly 14,934 cycles (individual
  gaps 14,932-14,935: the interrupt waits for the current instruction).
  No drift.
* **FS is not connected on the MC-10** (confirmed by the owner), and
  nothing else reveals the beam.  The tick's phase is random every time a
  program starts.  So: no beam racing unless the player calibrates.
* On a stock ROM the OCF hook is `$4206`, inside the RG6 screen.  Only
  install the ISR when the hook (read from `$FFF4`) is outside the screen,
  as DOttery's DIGDUG does (it also reads the JMP back to confirm RAM).

### Sprite throughput (measured, `bench/sprites`, emulator debug port)

Erase + move + redraw every sprite every frame, black background:

| Sprite | Method | Cycles each | Per frame at 60 Hz |
|---|---|---|---|
| 16x16 mono | OR draw, clear erase | ~760 | 18 |
| 16x16 mono | XOR draw + XOR erase | ~1,040 | 14 |
| 8x16 artifact | OR draw, clear erase | ~730 | 20 |
| 8x16 artifact | XOR draw + XOR erase | ~985 | 15 |
| 16x16 mono, pad 3 | self-erasing store, no erase | ~463 | 32 |
| 8x16 artifact, pad 3 | self-erasing store, no erase | ~507 | 29 |

Self-erasing (`pad N` in spritec, `MODE=2`): the padded box is stored
whole, so the border wipes the previous position.  Verified trail-free
in screenshots; overlapping sprites clip each other as rectangles.  The
store routines are bigger: 22x22 mono box = 281-362 cycles per shift
(3 or 4 bytes wide); the 24-sprite bench binary is 13.7K.

Compiled routines (spritec): 16x16 mono OR draw is 330-450 cycles
depending on shift; erase 98-152.

### How Darren Ottery's games avoid flicker without sync

Disassembled FROGLER, DIGDUG, GALAGOR (all load at `$5000`):

* **Low resolution:** CG3 (VDG `$24`, 128x96, four colours, 3K screen),
  so every operation costs half of RG6.
* **No beam sync at all.**  FROGLER paces its main loop by polling the
  free-running counter: wait until 35,795 cycles (about 25 Hz) have passed
  since the last tick, playing sound while waiting; resync if more than
  8,000 behind.  GALAGOR has no frame timer.
* **OCF interrupt only for sound** (DIGDUG): self-modifying `JMP` picks the
  tone ISR (square wave with a pitch-sweep accumulator) or the noise ISR
  (16-bit LFSR `$ACE1`, taps `$B4`).  Clears timer interrupts at start.
* **The stack pointer as the second index register:** sprite data is
  read with `PULA`/`PULB` (S = source, interleaved mask/data), X =
  destination: `PULA / ANDA n,X / PULB / ABA / STAA n,X`, 18 cycles per
  masked byte, pre-shifted copies chosen with `MUL`.  Interrupts off while S
  is borrowed.
* **Row-by-row compositing** (FROGLER): for each screen row, copy the
  background from an off-screen buffer (computed jump into an unrolled
  `LDAA n,X / PSHA` run, S = destination, 7 cycles/byte), then at once draw
  the masked sprite pieces on that row.  A pixel is "missing" for only a
  few hundred cycles, so the beam almost never catches it.
* The common principle: **minimise the time between erasing a pixel and
  redrawing it**, so it doesn't matter where the beam is.

### Consequences for this engine

* Beam-independent drawing first; calibration is optional polish.
* **Self-erasing sprites (done, see the table above):** compile each sprite with a blank border as wide
  as its maximum speed and draw it in store mode (`LDD #/STD`, 4
  cycles/byte, no separate erase).  The sprite never disappears, so it
  can't flicker.  Good on black/uniform backgrounds (stars can be redrawn
  after); overlaps clip as rectangles.
* Masked draws and backgrounds: row-band compositing like FROGLER, with
  compiled code instead of data-driven loops.
* Consider a free-running 30 Hz pace (or 20/25 Hz) for heavy scenes.

### Visual testing in the emulator (owner, 2026-11-16)

`make variants`, then `make run-sp_m0` ... `run-sp_a2` (outside the sandbox):

* **Black horizontal bands** about a sprite tall, at random moments, in
  every erase-then-redraw build (m0, m1, a0, a1): the beam catching a
  sprite between its erase and redraw.  The TRACE build measured the beam
  crossing a sprite's rows during that window in ~14% of redraws (an
  upper bound).  **Gone in the self-erasing builds** (m2, a2).
* **Overlaps:** OR + clear punches byte-aligned black boxes; XOR keeps
  balls round (preferred look); self-erasing clips with its border box.
* **Artifact pixels are 2:1** (128 across the width of 192 rows): artifact
  art needs twice as many rows as columns to look round.  The test orb is
  now 8x16, which roughly doubles its cost.
* Next candidate: **XOR delta sprites**, one read-modify-write pass of
  XOR(old, new) per one-pixel step, so no byte is ever blank (no banding)
  and overlaps stay round.  Estimate for the 16x16 ball: ~370 cycles per
  step, but ~11.6K of code for 8 shifts x 8 directions.

### XOR delta sprites (measured, `MODE=3`, spritec `delta`)

| Cycles per sprite | OR + clear | XOR | Self-erasing | XOR delta |
|---|---|---|---|---|
| mono, 1 px/frame | 763 | 1,041 | 471 | **682** |
| mono, 1-3 px/frame (bench default) | 764 | 1,040 | 469 | 1,170 |
| artifact 8x16, 1 px/frame | 727 | 983 | 507 | **710** |
| artifact 8x16, 1-3 px/frame | 725 | 981 | 504 | 1,222 |

* One delta routine per (direction, shift): ~330 cycles average (straight
  up/down ~250, sideways ~360).  Call plus step overhead ~200 more.  Cost
  scales with pixels moved, so it wins only for slow sprites.
* Code size: the 16x16 mono ball with all 8 directions is ~15K (the whole
  m3 build ends at `$A585`, close to the `$AFFF` limit).  The 8x16
  artifact orb is ~4K.  Restricting directions, or 2-pixel delta routines
  for fast sprites, are the obvious next options.
* Correct over long runs: 300 frames, no residue.
* **Visual test (owner):** m3 and a3 both clean: no blocking, no banding.
  Overlaps invert (XOR), as expected.  Artifact sprites look twice as
  fast horizontally because an artifact pixel is two mono pixels wide;
  move them half as far in x for the same on-screen speed (which also
  halves the delta cost).

### Sprite strategy (so far)

Choose per sprite type:
* **Halo** (`halo N`, bench `MODE=4`): the sprite plus a cleared halo (its
  shape grown by N = top speed), one read-modify-write pass, drawn in
  priority order (lowest first).  Never blank, so no banding; front
  sprites cover back ones in shape, with an N-pixel black outline.
  Measured ~707 cycles per 16x16 mono or 8x16 artifact sprite at speeds
  1-3 (18 per 60 Hz frame); both test sprites together ~11K of code.
  Probably the best general-purpose choice.
* **Self-erasing** (`pad N`): cheapest, never flickers; for sprites that
  don't overlap much, on black or sparse backgrounds.
* **XOR delta** (`delta`): never flickers, overlaps invert; best for slow
  sprites (cost per pixel moved), mind the code size of big mono sprites.
* **Masked + row compositing** (to do): solid overlaps over scenery.
* Plain OR/XOR erase-then-draw: only where banding doesn't matter.
* **Visual test (owner): the 1-pixel halo (m5, a5) is the best effect of
  all.**  The thin dark rim reads like a contact shadow, so front sprites
  look like solid objects passing over the ones behind.  The 3-pixel halo
  (m4) is too heavy.  It's also cheap (~594 cycles per 16x16 mono, ~556 per
  8x16 artifact); it only looks slow because those builds move 1 pixel a
  frame.
* **Plan:** 1-pixel halo as the default sprite method, with fixed-point
  positions (sub-pixel speeds up to 1 pixel per frame); a wider halo only
  for fast sprite types such as bullets; maybe asymmetric halos (e.g. 2
  across, 1 down).

### Sprite manager (`engine/sprman.asm`, demo `bench/smdemo.asm`)

* Object record (10 bytes): x, y in 8.8 fixed point, dx, dy signed 8.8,
  descriptor pointer (0 = free slot).  Table order = priority.
* Descriptor: draw table, erase table, call routine (`spr_mono` or
  `spr_art`), so one manager drives any mix of sprite types.
* `spr_update_all` moves and draws everything; `obj_erase` clears an
  object (removal, or a jump further than its halo).
* Measured with 1-pixel halo sprites and mixed speeds of 0.25 to 1 pixel
  per frame: ~690 cycles per object including the demo's bounce logic
  (~594 of it the draw).  16 objects = ~11.1K mono / ~10.6K artifact, 74%
  / 71% of a frame.  Possible later saving: cache the draw table and call
  in the object record instead of going through the descriptor.

### Playable test: `bench/shooter.asm` (owner verdict, 2026-11-16)

10 aliens on curving paths at up to 2 px/frame (2-pixel halo), ship at 2
px/frame (2-pixel halo), shots at 4 px/frame (4-pixel halo on a 2x6
sprite); ~10.7K cycles per frame median, 12K peak.

* **"Extremely impressive"; it feels like arcade action.**  With the
  aliens' erratic movement the 2-pixel halos are "acceptable and hardly
  noticeable".  The shots look right.
* Conclusion: halo sprites through the sprite manager are the engine's
  sprite system.  Halo = each type's top speed; 1 pixel for slow objects,
  2 for fast craft, wider for tiny fast shots.  Row-band compositing is
  shelved unless big, fast objects need it.
* Missing for a real game: sound, explosions, a score display (text in
  RG6), sprites entering/leaving through the screen edges (clipping), and
  the player's death.

### Sound engine (`engine/frame.asm` interrupt, `engine/sound.asm` sequencer)

* One output-compare interrupt for sound and the frame tick: each event
  moves OCR by `snd_half`, toggles the speaker (tone) or outputs an LFSR
  bit (noise), and counts `snd_half` off the cycles left to the next tick.
  Exact accounting (no drift); the tick lands up to one half-period late,
  which is harmless because nothing races the beam.  Silent = one event
  per frame.  The handler is a patched JMP (no mode tests).
* All VDG writes go through `vdg_shadow` so the speaker bit survives
  (`METER_*`, `VDG_SET`).
* Sequencer: effects are segments of (frames, tone/noise/rest, half-period,
  per-frame sweep); `snd_play` with priority, `snd_frame` once per frame.
* Measured (`bench/sndtest.asm`, idle-loop counting): 1 kHz tone 15.8% of
  the CPU (~2,350 cycles/frame), noise every 500 cycles 18.7%; silence 0.
  Pitch exact (1,001 Hz measured from the emulator's audio).  Cost is
  ~67/half-period: keep effects around 400 Hz-1 kHz.
* Shooter with zap + explosion, fire held continuously: median 12.1K
  cycles per frame, 25 of 1,446 frames over budget (1.7%).
* Bug found on the way: uninitialised sequencer state made the "silent"
  interrupt run every 150 cycles (frame_init now clears everything).
* **Owner verdict:** shooter with sound "great, no noticeable degradation
  even while holding down fire"; spread shots give a "very convincing
  arcade feel"; effects "smooth and effective"; sndtest "perfect".

### Waves, flight paths, gutters (`bench/waves.asm`, `engine/flight.asm`)

* **Gutters instead of clipping:** `rowtab` covers all 256 y values: 192-223
  is hidden memory below the screen (`$5800-$5BFF`), 224-255 is y = -32..-1
  (`$3C00-$3FFF`, MCX32-SD flash, which ignores the writes: the flash only
  programs after an unlock at chip offsets $5555/$2AAA, never addressable
  from that window).  Sprites slide off the bottom and in at the top whole.
  (Check on real hardware.)
* **Flight scripts:** P_FLY frames,turn / P_HEAD / P_SPEED / P_GOTO /
  P_AIM (heading toward a target, via a 33-entry atan table) / P_EVENT n.
  Each path is ~20-40 bytes; every alien on the same script flies the same
  path, so a wave launched at intervals is a snake.  `tools/pathsim.py`
  simulates paths with the same integer maths to check side edges and
  wraps before assembling.
* **Halo sprites are leaner:** only `hr` and `er` routines, plus a
  descriptor `NAME_dsc` with the hitbox; `hit_test` in sprman.  The
  shooter shrank by ~5K.
* Wave test: 3 alien types, 6 waves (loops, S-curves, slow circling and
  dives), bombs from path events.  40 s headless with fire held: median
  11.4K cycles/frame, 1 frame of 2,276 over budget.
* **Tuning round (owner feedback):** P_TURNBY (instant heading change:
  jinks, U-turns); new paths: loops with jinks, downward zigzags (headings
  never point up, alternating sides so they don't drift), fast circles
  with a reversal; orbiters no longer slow; bombs at every drop point (6
  slots); 8-alien waves.
* **Star field** (`engine/stars.asm`): 18 single-pixel stars, three
  speed layers, half updated each frame; drawn before sprites, which
  cover them.
* **Optimisations** (profiled per phase with debug markers): flight skips
  the velocity recompute on straight legs; the manager reuses the setup
  when consecutive objects share a type; collisions use a tight quick-
  reject loop.  Frame with 10 aliens, 6 bombs, 3 shots, 18 stars, sound,
  fire held: median 11.8K cycles, 2% of frames over budget.
* **Second tuning round (owner):** bombs now come in sprays (48-frame
  windows with at least 7 frames between bombs, then 80 quiet frames)
  instead of streams; dart waves enter as a staggered line (x step 24 per
  launch, 16-frame intervals), one zigzag lane each, so there are gaps to
  dodge through.  Bug: the alive counter was never cleared (worked by
  luck until the direct page moved); the program now clears all its
  variables at start.  Fire held: median 9.8K cycles, 0 frames over.

### Decision: artifact colour (owner, 2026-11-16)

The game is in NTSC artifact colour, 128x192 in black, white, orange and
blue.  `bench/waves.asm` converted:
* spritec `halo X Y` (across, down) and per-axis padding; descriptors
  carry PADX, PADY, VW, VH; hit_test uses both.
* `FL_HALFX`: flight halves horizontal speed (an artifact pixel is two
  screen pixels wide), so every path keeps its shape and entry x values
  simply halve.  A 1-pixel halo across now covers 2 screen pixels of
  movement; shots and bombs have no horizontal halo at all.
* Coloured stars: the slow layers are single bits (orange or blue specks),
  the fast layer white pairs.
* Result: program 15K -> 9K (4 shifts instead of 8, narrower halos);
  frame work median 9.8K -> 8.7K, 1 frame of 2,071 over budget.
* Colour phase: the emulator's VDG always starts the same way (colours
  correct first time, confirmed by the owner); real NTSC hardware can come
  up with orange and blue swapped.  CoCo games had you press RESET until a
  sample was right; the MC-10 can't intercept RESET.  Plan: the title
  screen shows a sample block and offers a key to swap colours *in
  software*: one scan over the compiled sprite code that swaps the bit
  pairs of every data immediate (LDAA/LDAB/LDD/ORAA #; an LDAB # followed
  by ABX is a row step, not data; AND masks are pair-symmetric and stay).
  No second copy of the art, no address table.  Stars and text likewise.

### Explosions (frame animation in sprman)

* `obj_anim_start` / `obj_anim_step`: an object plays a list of
  (descriptor, frames) entries and frees itself at the end; state in 3
  game bytes at AN_BASE.  Frame changes erase then draw (a brief flicker
  suits an explosion).
* Alien explosion: flash, burst, ring, debris (4+4+5+6 frames), in the
  aliens' box, drifting at half the alien's speed; the slot stays busy
  (not a target, not free) until it ends.  Fire held: median 9.5K
  cycles, 0 frames over budget.

### Game prototype (`bench/game.asm`)

* Title screen (working title STARFALL) with a colour sample: C runs
  `col_swap` (engine/colswap.asm: decodes each sprite's halo routines and
  swaps the bit pairs of every data byte) and swaps the text colour masks.
* "PLAYER 1" banner at the start and after each lost ship; status line
  (SCORE in BCD via DAA, SHIPS) redrawn every 12 frames because sprites and
  stars cross it.
* Bombs and collisions with aliens destroy the ship (bigger, longer
  explosion and sound); respawn flashing and untouchable for 2 s; GAME
  OVER after the last ship, then back to the title.
* engine/text.asm + font.asm: a 3x5 artifact font, one byte per
  character (32 per line), normal and double height; generated from glyph
  art by tools/mkfont.py.
* Tested headless: swap, start, three deaths, game over, title.  Fire
  held: median 9.5K cycles, 0.6% of frames over budget.

### Areas, map, victory warp, jingles

* Four areas, each a wave list (later areas launch faster); when an
  area's waves are done and no alien is left: AREA CLEARED, +1000, the
  victory salute, then the warp: the ship (afterburner sprites shipw1/2,
  alternating flame, halo 1 across / 6 down so each frame covers the
  other's flame tip at 4 rows a frame) accelerates up, flies off the top,
  through both gutters, back in at the bottom, and brakes to a stop while
  the stars streak (stars_update called up to 6 times a frame; it now
  alternates halves per call).  Then the map and the next area (after the
  last: round again).  Bosses will go at each area's end.
* Map screen at the start, after a lost ship and on arriving in an area:
  PLAYER 1, AREA n, a strip of the areas with boss markers, the ship at
  its progress.  Play pauses; sound continues.
* Jingles: start fanfare, fresh-ship phrase, victory salute; a rising
  noise roar for the afterburner.
* **Memory is getting tight:** the game ends at $A707 (~2.3K left below
  $AFFF).  Next step for space: move tables, text and the font to the
  MCX32-SD's low SRAM ($0400-$1FFF, ~7K), copied there at start.
* **Owner playtest:** finished all four areas to the restart on the third
  try ("challenging").  Fixes from it: the blast-off now slides behind the
  status bar (a solid band redrawn after the sprites during the climb),
  the ship disappears above the top and only rises in from the bottom
  after the map screen (modes WARP -> COAST -> map -> ARRIVE); waves only
  launch during play; stars no longer start in a diagonal (st_rnd steps
  its LFSR 8 bits per byte: single steps made consecutive bytes shifted
  copies); the colour question appears only before the first game.
* **Bug (owner report): stars rushing, ship stuck and flickering, aliens
  slow.**  Two causes: (1) the game's direct-page variables had grown
  into the engine's hit_test scratch at $F8, so every collision test
  overwrote warpf (star updates per frame) and its neighbours; (2) a
  nameless `+` label: new `+` labels inserted between `beq +` and its
  target sent play mode into the arrival code every frame.  Fixes: less
  frequently used variables moved to BSS ($5C00-$5EFF, between the gutter
  and the stack); DP_CHECK / BSS_CHECK macros fail the assembly on an
  overflow; named labels for multi-way dispatch.
* **`make check`** (tests/game_check.sh): headless checks run before
  handing over a build: the ship answers the controls in play, a forced
  area clear reaches the next area back in play, and the frame budget
  holds with fire held.
* **Status bar in front (owner request):** the VDG always shows from
  $4000 and the gutters need hidden memory above the playfield, so the
  playfield can't simply start below the bar.  Instead the bar (rows 0-6)
  is rendered into a buffer when the score or ships change, and copied
  over the screen after the sprites on any frame a sprite touched it
  (sprman flags objects over rows < sm_band or above the top).  The copy
  is a per-row stack blast (LDAA n,X / PSHA, ~240 cycles a row with
  interrupts off).  Shots end under the bar; stars stay below it
  (STAR_TOP).  Aliens now slide out from under the bar.

### Memory segments and loading (2026-11-17)

* The 8K mod + MCX32-SD are required, so programs ship as a DECB `.BIN`
  loaded with the MCX32-SD's `LOADM` (no `.C10`, which is one contiguous
  block).  `tools/p2decb` reads ASL's object file and writes one segment
  per contiguous block, failing the build for any byte outside
  `$0400-$1FFF` (low) and `$6000-$ADFF` (main).
* What LOADM itself uses (measured in the emulator): the direct page,
  `$0103-$0104`, `$022A-$0283`, `$0316-$0317` (BASIC's variables beside
  the interrupt hooks), and BASIC's stack at ~`$AF2C` with string space
  above.  No RAM sector buffer: the BIOS copies straight to the target.
* Game: low `$0400-$1E6B` (alien and explosion sprites, sine table, 6.7K),
  main `$6000-$8E53` (11.6K): ~8K free in main, ~400 bytes in low.
  LOW_CHECK / CODE_CHECK fail the assembly on overflow.
* `make run-NAME` uses `build/sd` as the SD card; `make check` loads the
  game with LOADM too.  Both segments verified byte-exact by checksum.

### Bosses (first: the mothership)

* After an area's waves: WARNING!, a siren, and the boss descends from
  under the status bar, then sways at half a pixel a frame (halo 1 1:
  ~570 cycles to draw) while its two cannons fire (sharing the bomb
  rhythm via `bomb_at`) and escort waves loop around it.
* Weak spot: a separate core sprite in the hull's opening, moved with it;
  only core hits count (8/12/16/20 by area).  The art has a channel under
  the core and shots in the core's column pass the hull's hit box (the
  core sits inside the hull's rectangle, so without that every shot
  pinged off the hull).  Core flashes white, clang; hull hits ping.
* Defeat: the escorts explode, bursts across the hull for 2 s, +5000,
  then the salute and warp.
* Cost: boss fight median ~11.1K cycles/frame, <1% over budget, after
  lowering the ping (a 2 kHz tone cost ~30% CPU while playing) and a
  quick reject before the boss hit tests.  Main segment ends ~$9AE0.
* make check covers the boss: arrival after the waves, kill, warp.
* **Bug (owner report): the boss came after one wave.**  Another nameless
  label: new `+` labels inserted into wave_logic retargeted a `bne +`, so
  every "start the next wave" went to "the area's waves are done".  Fix:
  `tools/nameless.py` converted every nameless label in bench/game.asm to
  a named one (the binary came out byte-identical, proving the conversion
  exact), then the fix was made with named labels.  New check: in normal
  play neither the area's end nor the boss comes before area 1's third
  wave (it flags the buggy build: 52 bad samples of 60).
* Rule from now on: no new nameless labels in the game; convert engine
  files the same way when next touching them.
* **Playtest round (owner):** losing a ship now clears the field (aliens,
  bombs, shots); survivors are relaunched along the current wave's path
  and still count toward the area.  Areas doubled to 8 waves each
  (remixed types and paths, later areas faster; the map shows 3 rows per
  wave).  Boss theatrics: ~4 s of eight low falling wails, a flashing
  WARNING!, a slow descent, escorts only after the warning.  The map
  no longer labels the checkpoints: the bosses are a mystery.
* Next bosses (owner's design): envoys on either side that bomb heavily,
  the core shielded until all envoys are destroyed; later bosses with
  more envoys and several weak spots that must all be destroyed.

### Envoy bosses (areas 2-4)

* Boss table per area: core hits, envoys (0 or 2), hits per envoy,
  escorts.  Area 1: the plain mothership; areas 2-4: two envoys (4/6/8
  hits) flanking the hull (moving with it; the sway range narrows to keep
  them on screen), bombing every 16 frames outside the spray rhythm
  (`bomb_force`).  The core shows a closed hatch (coreshut) and pings
  until both envoys are destroyed (+500 each); then it opens (a rising
  chime) and takes damage.  Same hull as boss 1 (a new hull is ~3K).
* Collisions: envoys get a quick horizontal reject; the core and hull
  tests use simple column/row checks (the quick reject already put the
  shot in the boss's rows).  Escort waves are smaller in envoy fights.
* Frame budget (worst case: fire held, test ship kept invulnerable and
  flashing): ~6-9% of frames over in envoy fights, a brief slowdown like
  arcade boss fights.  Normal play: 0%.
* make check: the shut core takes no hits, both envoys die, then the core.
* **Regression (owner report): slowdowns in normal waves with rapid fire.**
  Found by comparing against the last good build (8f4866e) in a
  two-minute sweep-and-fire run: heavy frames had grown (p95 12.9K ->
  14.3K, 1% -> 3.5% over), mostly from the 8-alien waves (up to 10 on
  screen), which multiplied collision work and status-bar repairs.  Fixes:
  each shot meets the aliens only every other frame (alternating), and
  the ship meets bombs and aliens on alternate frames (the overlap
  windows are deeper than two frames' movement; shots against the boss
  stay every frame, the core's window is shallow); the status bar repair
  copies with LDD/PSHB/PSHA and clears its blank rows.  Now: median 7.2K,
  p95 11.1K, 0.6% over, better than the old build.  The budget check now
  uses that sweep-and-fire scenario (limit 2%).
* **Sliding window (owner's idea):** at most MAX_ALIVE = 8 live aliens fly
  at once; the rest of a wave (and relaunched survivors, and escorts) wait
  their turn and slip in as others die.  The area's tally is unchanged.
  make check: never more than 8 seen in two minutes of play.
* **Bug (owner report): the status bar vanished.**  The faster bar repair
  called a row-clearing routine with JSR, but that routine restored S to
  the value its caller had saved (before the JSR pushed a return
  address), so its RTS returned out of the whole repair, skipping the
  text rows.  Fix: the routine saves its own S.  New checks: the screen's
  rows 0-6 match status_buf during play, and the buffer holds text (the
  broken build fails them).
* **Bug (owner report): a dart stuck half off the right edge, wrapping
  onto the left, unshootable.**  Staggered-lane waves step the entry x
  per launch; when relaunched survivors made more launches than lanes,
  the x ran off the screen (lane 10 of the dart wave entered at x 251),
  and the side-edge mirror can't recover an alien that is already off
  screen and diving straight down.  Fixes: entry lanes wrap back to the
  first one; any live alien found off the side is put back inside and
  turned round.  Reproduced deterministically (14 launches, alive held
  open: the old build puts an alien at x 251) and added to make check.

### Wrap-around aliens (owner's request, Galaxian-style)

* `P_WRAP 1` in a flight script lets an alien fly through the side edges
  (flight.asm F_FLAGS / FF_WRAP; objects are now 20 bytes, AN_BASE 7).
  While straddling an edge its spilled part draws at the other side one
  row lower (the screen's rows are laid end to end); when the next move
  would cross, the old image is erased (the halo can't bridge the jump:
  a one-frame flicker) and x flips by 128 (x < 128, so toggle bit 7).
  Edge mirroring and off-side recovery skip wrapping aliens.
* New paths (pathsim: crossings, no climbing off the top): sweepR /
  sweepL (long shallow diagonals with curves), weave (fast horizontal
  passes with U-turns, then a dive).  A wrap wave or two in every area.
* make check: forced sweep wave, aliens cross right -> left (6 in 10 s),
  none stays straddling.  Main segment ends $A3A6 (~2.6K free).
