#!/usr/bin/env python3
"""pathsim: simulate engine/flight.asm paths with the same integer maths.

Prints each path's x and y extents and the frames where it wraps, so
paths can be designed to stay inside the screen's side edges.
Public domain (Unlicense)."""
import math
SIN = [int(512.0 * math.sin(i * math.pi / 128.0)) for i in range(256)]

def s16(v): return v - 65536 if v & 0x8000 else v

def run(script, x0, y0, box_w, box_h, frames, head0=64, speed0=0):
    """script: list of tuples like ('fly', n, turn), ('head', a), ('speed', s),
    ('goto', index), ('event', n).  Positions are 8.8."""
    x, y = x0 << 8, y0 << 8
    ang, turn, cnt, spd, pc = head0, 0, 0, speed0, 0
    xs, ys, wraps, events, side_hits = [], [], [], [], []
    for f in range(frames):
        if cnt == 0:
            while True:
                op = script[pc]
                if op[0] == 'fly': cnt, turn = op[1], op[2]; pc += 1; break
                if op[0] == 'head': ang = op[1] & 255
                elif op[0] == 'speed': spd = op[1]
                elif op[0] == 'goto': pc = op[1]; continue
                elif op[0] == 'event': events.append(f)
                pc += 1
        cnt -= 1
        ang = (ang + turn) & 255
        dx, dy = SIN[(ang + 64) & 255] >> spd, SIN[ang] >> spd
        # game logic: side safety (mirror), wrap through the bottom
        nx = ((x + dx) >> 8) & 255
        if nx >= 256 - box_w:
            side_hits.append(f); ang = (128 - ang) & 255
            dx, dy = SIN[(ang + 64) & 255] >> spd, SIN[ang] >> spd
        x = (x + dx) & 0xFFFF
        y = (y + dy) & 0xFFFF
        yp = y >> 8
        if 192 <= yp < 224:
            y = ((256 - box_h) << 8) | (y & 255); wraps.append(f)
        xs.append(x >> 8); yp = y >> 8
        ys.append(yp - 256 if yp >= 224 else yp)
    return xs, ys, wraps, events, side_hits

if __name__ == '__main__':
    import sys
    exec(open(sys.argv[1]).read())
