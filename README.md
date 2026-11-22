# mc10-game-engine

A game engine for the TRS-80 MC-10's full-screen graphics modes, for
machines with the internal 8K RAM mod and an MCX32-SD.  It has a software
sprite engine and an interrupt-driven sound engine, in 6803 assembly.
Three graphics modes are supported, chosen when assembling: 256x192
monochrome (RG6), NTSC artifact color at 128x192 in four colors, and CG6
at 128x192 in four real colors, which PAL machines show as well.

**StarFall**, a complete vertical shooter, is the first game built on it:
[proj-starfall](https://github.com/phiber1/proj-starfall) (this repository
is its `engine/` submodule).  The engine has a beam-independent frame tick
and sound interrupt, compiled halo sprites with a sprite manager, flight
paths, a star field, text, and the MCX32-SD BIOS interface for loading
overlays and files.  **[docs/ENGINE.md](docs/ENGINE.md) is the reference
for writing programs with it.**

## Building

Needs [ASL](http://john.ccac.rwth-aachen.de:8000/as/) (`asl`), a C
compiler (for cpp and the tools) and make.  For running, the
[VMC10 for Linux](https://github.com/phiber1/vmc10-linux) emulator, checked
out next to this repository (or set `VMC10=`).

```
make                    # build every program in bench/ (debug build)
make DEBUG=0            # release build: no debug-port writes
make run-waves          # run a demo in the emulator (see the Makefile)
make run-cg6demo        # CG6: real colors, NTSC and PAL
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
copy the `.BIN` to the SD card and type `RUNM"NAME"`.

## Layout

| Path | Contents |
|---|---|
| `engine/` | Hardware definitions, memory layout, graphics modes, frame tick, sound, sprite calls, sprite manager, text, input |
| `bench/` | Benchmarks and demos (`tick`, `sprites`, `smdemo`, `shooter`, `waves`, `sndtest`, `cg6demo`) and the sprite viewer (`view`) |
| `docs/` | `ENGINE.md`: the reference |
| `sprites/` | Text-art sprites, compiled by `tools/spritec` |
| `tools/` | `spritec` (sprite compiler), `sprview.py` (the viewer's layout), `p2decb` (ASL object file to a multi-segment DECB `.BIN`), `mkfont.py`, `mknotes.py`, `pathsim.py`, `ppm2png`, `mkc10` (legacy `.C10`) |

## Sprites

`tools/spritec` turns text-art sprites into unrolled 6803 code, one routine
per sub-byte shift (8 for mono, 4 for the 4-color modes).  Halo sprites
(recommended) erase their old position as they draw and are never missing;
self-erasing, XOR delta and plain OR/XOR versions exist too.  See
[docs/ENGINE.md](docs/ENGINE.md#sprites).

```
sprite ball mono halo 1     sprite hero cg6 halo 1 bg B
.....XXXXXX.....            ..GG..        G green   Y yellow
...XXXXXXXXXX...            .YYYY.        B blue    R red
end                         end           (bg B: on a blue background)
```

Measured in the emulator, sprites erased, moved and redrawn per 60 Hz frame:
18 (16x16 mono) or 20 (8x16 artifact) with OR draw and erase; 32 and 29 with
self-erasing sprites (`pad N`: a blank border wipes the old position, no
erase pass, and the sprite never disappears).

## Licence

Public domain, under the [Unlicense](LICENSE).
