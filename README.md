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

Needs [ASL](http://john.ccac.rwth-aachen.de:8000/as/) (`asl`, `p2bin`), a
C compiler (for cpp and the tools) and make.  For running, the
[VMC10 for Linux](https://github.com/phiber1/vmc10-linux) emulator, checked
out next to this repository (or set `VMC10=`).

```
make                    # build every program in bench/ (debug build)
make DEBUG=0            # release build: no debug-port writes
make run-sprites        # run a program in the emulator (MCX32-SD + 8K)
make log-sprites        # run it headless and print the debug-port log
```

Each `bench/NAME.asm` becomes `build/NAME.c10` (for CLOADM) and
`build/NAME.bin` (for the MCX32-SD's LOADM).  Programs load and start at
`$6000`.

## Layout

| Path | Contents |
|---|---|
| `engine/` | Hardware definitions, memory layout, frame tick, sprite calls |
| `bench/` | Proof-of-concept benchmarks (`tick`, `sprites`) |
| `sprites/` | Text-art sprites, compiled by `tools/spritec` |
| `tools/` | `spritec` (sprite compiler), `mkc10` (C10/DECB wrapper), `ppm2png` |

## Sprites

`tools/spritec` turns text-art sprites into unrolled 6803 code, one routine
per sub-byte shift (8 for mono, 4 for artifact), in OR, XOR and erase
versions:

```
sprite ball mono            sprite orb artifact
.....XXXXXX.....            ...OOO..      . black   O orange
...XXXXXXXXXX...            .OOWWOOO      B blue    W white
end                         end
```

Measured in the emulator: about 18 sprites (16x16 mono) or 31 sprites (8x8
artifact) erased, moved and redrawn per 60 Hz frame.

## Licence

Public domain, under the [Unlicense](LICENSE).
