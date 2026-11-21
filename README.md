# mc10-game-engine

A game engine for the TRS-80 MC-10's 256x192 RG6 graphics mode, for
machines with the internal 8K RAM mod (plus an MCX32-SD for memory).  It
has a software sprite engine and an interrupt-driven sound engine, in 6803
assembly.  Both RG6 colour models are supported: true 256x192 monochrome,
and NTSC artifact colour at 128x192 in four colours.

**StarFall**, a complete vertical shooter, is the first game built on it:
[proj-starfall](https://github.com/phiber1/proj-starfall) (this repository
is its `engine/` submodule).  The engine has a beam-independent frame tick
and sound interrupt, compiled halo sprites with a sprite manager, flight
paths, a star field, text, and MCX32-SD file access (overlays, a high
score file).  See [`NOTES.md`](NOTES.md) for the design, the measurements,
and what we learned from Darren Ottery's games.

## Building

Needs [ASL](http://john.ccac.rwth-aachen.de:8000/as/) (`asl`), a C
compiler (for cpp and the tools) and make.  For running, the
[VMC10 for Linux](https://github.com/phiber1/vmc10-linux) emulator, checked
out next to this repository (or set `VMC10=`).

```
make                    # build every program in bench/ (debug build)
make DEBUG=0            # release build: no debug-port writes
make run-waves          # run a demo in the emulator (see the Makefile)
make run-view VIEW=sprites/waves.spr   # a sprite file's sprites, still
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
| `bench/` | Benchmarks and demos (`tick`, `sprites`, `smdemo`, `shooter`, `waves`, `sndtest`) and the sprite viewer (`view`) |
| `sprites/` | Text-art sprites, compiled by `tools/spritec` |
| `tools/` | `spritec` (sprite compiler), `sprview.py` (the viewer's layout), `p2decb` (ASL object file to a multi-segment DECB `.BIN`), `mkfont.py`, `mknotes.py`, `pathsim.py`, `ppm2png`, `mkc10` (legacy `.C10`) |

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
