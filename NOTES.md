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
| 8x8 artifact | OR draw, clear erase | ~465 | 31 |
| 8x8 artifact | XOR draw + XOR erase | ~590 | 25 |
| 16x16 mono, pad 3 | self-erasing store, no erase | ~463 | 32 |
| 8x8 artifact, pad 3 | self-erasing store, no erase | ~356 | 41 |

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
