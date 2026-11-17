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
