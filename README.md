# mc10-game-engine

A game engine for the TRS-80 MC-10's 256x192 RG6 graphics mode, for
machines with the internal 8K RAM mod (plus an MCX32-SD for memory).  It
has a software sprite engine and an interrupt-driven sound engine, in 6803
assembly.  Both RG6 colour models are supported: true 256x192 monochrome,
and NTSC artifact colour at 128x192 in four colours.

**Status: early.** The frame tick and the compiled-sprite compiler work,
with throughput benchmarks.  Scrolling and sound are next.  See
[`NOTES.md`](NOTES.md) for the design, the measurements, and what we learned
from Darren Ottery's games.

## Building

Needs [ASL](http://john.ccac.rwth-aachen.de:8000/as/) (`asl`), a C
compiler (for cpp and the tools) and make.  For running, the
[VMC10 for Linux](https://github.com/phiber1/vmc10-linux) emulator, checked
out next to this repository (or set `VMC10=`).

```
make                    # build every program in bench/ (debug build)
make DEBUG=0            # release build: no debug-port writes
make run-game           # run the game prototype in the emulator
make check              # headless checks of the game prototype
make log-sprites        # run a benchmark headless, print the debug-port log
```

**Target: an MC-10 with the internal 8K RAM mod and an MCX32-SD.**  Each
`bench/NAME.asm` becomes `build/NAME.bin`, a DECB binary for the
MCX32-SD's `LOADM`: a main segment at `$6000-$ADFF` and, for programs that
need it, a low segment at `$0400-$1FFF` (the MCX32-SD's low SRAM).  The
build refuses any byte outside those ranges, which keeps clear of what
`LOADM` itself uses (BASIC's variables at `$0200-$03FF`, its stack near
`$AF00`).  `make run-NAME` copies the binary into `build/sd`, the
emulator's SD card, and types `LOADM"NAME"` and `EXEC`.  On real hardware,
copy the `.BIN` to the SD card and do the same.

## Layout

| Path | Contents |
|---|---|
| `engine/` | Hardware definitions, memory layout, frame tick, sprite calls, sprite manager |
| `bench/` | Proof-of-concept benchmarks and demos (`tick`, `sprites`, `smdemo`) |
| `sprites/` | Text-art sprites, compiled by `tools/spritec` |
| `tools/` | `spritec` (sprite compiler), `p2decb` (ASL object file to a multi-segment DECB `.BIN`), `mkfont.py`, `mknotes.py`, `pathsim.py`, `ppm2png`, `mkc10` (legacy `.C10`) |
| `tests/` | `game_check.sh`: headless checks of the game (`make check`) |

## Sprites

`tools/spritec` turns text-art sprites into unrolled 6803 code, one routine
per sub-byte shift (8 for mono, 4 for artifact), in OR, XOR and erase
versions, plus a self-erasing store version for sprites given a `pad`:

```
sprite ball mono            sprite orb artifact pad 2
.....XXXXXX.....            ...OOO..      . black   O orange
...XXXXXXXXXX...            .OOWWOOO      B blue    W white
end                         end
```

Measured in the emulator, sprites erased, moved and redrawn per 60 Hz frame:
18 (16x16 mono) or 20 (8x16 artifact) with OR draw and erase; 32 and 29 with
self-erasing sprites (`pad N`: a blank border wipes the old position, no
erase pass, and the sprite never disappears).

## Licence

Public domain, under the [Unlicense](LICENSE).
