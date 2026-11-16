/* spritec: compile text-art sprites into 6803 code for RG6.
 *
 *   spritec IN.spr > OUT.inc
 *
 * Input: one or more sprites
 *
 *   sprite NAME mono|artifact [pad N]
 *   ..XXXX..           mono:     . = 0, X = 1                 (8 pixels/byte)
 *   .XXXXXX.           artifact: . black, O orange, B blue, W white
 *   end                          (4 pixels/byte, pairs 10=O 01=B at phase 0)
 *
 * Output, for every horizontal sub-byte shift s (8 for mono, 4 for artifact):
 *
 *   NAME_or<s>  OR the sprite onto the screen   (transparent; uses A)
 *   NAME_xr<s>  XOR it                           (draw twice = erase; uses A)
 *   NAME_er<s>  clear the bytes NAME_or touches  (erase on black; uses D)
 *   NAME_sr<s>  with "pad N": store the whole padded box, zeros included.
 *               The blank border erases the previous position as it draws,
 *               so a sprite moving at most N pixels a frame needs no erase.
 *   NAME_or, NAME_xr, NAME_er (, NAME_sr)  tables of the routine addresses
 *   NAME_W, NAME_H (including the pad), NAME_SHIFTS, NAME_PAD
 *
 * Every routine takes X = screen address of the sprite's top-left byte and
 * returns with X changed.  Rows past the 8th are reached by moving X with
 * LDAB #n / ABX, so B is destroyed too.
 *
 * Public domain (Unlicense).
 */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAXW 64
#define MAXH 192

static char name[64];
static int artifact, w, h, pad;
static char art[MAXH][MAXW + 1];

/* the sprite's pixel bits at shift s: row r, byte b */
static int nbytes(int s) { int bpp = artifact ? 2 : 1; return (w * bpp + s * bpp + 7) / 8; }

static unsigned char sbyte(int r, int s, int b)
{
    int bpp = artifact ? 2 : 1;
    unsigned char v = 0;
    for (int bit = 0; bit < 8; bit += bpp) {
        int px = (b * 8 + bit) / bpp - s;          /* sprite pixel in this slot */
        if (px < 0 || px >= w) continue;
        char c = art[r][px];
        int val;
        if (!artifact) val = (c != '.' && c != ' ');
        else val = c == 'W' ? 3 : c == 'O' ? 2 : c == 'B' ? 1 : 0;
        v |= (unsigned char)(val << (8 - bpp - bit));
    }
    return v;
}

/* Load an 8-bit register with v unless it already holds it (-1 = unknown). */
static int load8(char reg, int *cur, int v)
{
    if (*cur == v) return 0;
    if (v == 0) printf("\tclr%c\n", reg);
    else printf("\tlda%c\t#$%02X\n", reg, v);
    *cur = v;
    return 2;
}

/* Emit code for one routine.  kind: 'o' or, 'x' xor, 'e' erase,
 * 's' store (writes every byte of the box, zeros included: with a blank
 * border this erases the sprite's previous position as it draws) */
static void routine(int kind, int s)
{
    printf("%s_%cr%d:\n", name, kind, s);
    int base = 0;                                   /* screen offset X points at */
    int cycles = 0;
    int ra = -1, rb = -1;                           /* known A and B contents */
    if (kind == 'e') { printf("\tclra\n\tclrb\n"); cycles += 4; ra = rb = 0; }
    for (int r = 0; r < h; r++) {
        int nb = nbytes(s);
        for (int b = 0; b < nb; b++) {
            unsigned char v = sbyte(r, s, b);
            if (!v && kind != 's') continue;
            int off = r * 32 + b - base;
            int pair = b + 1 < nb && (kind == 's' || (kind == 'e' && sbyte(r, s, b + 1)));
            int need = pair ? off + 1 : off;
            while (need > 255) {                    /* move X down, whole rows */
                int st = r * 32 - base;
                if (st > 224) st = 224;
                printf("\tldab\t#%d\n\tabx\n", st);
                cycles += 5;
                rb = st;
                base += st;
                off = r * 32 + b - base;
                need = pair ? off + 1 : off;
            }
            if (kind == 's') {
                if (pair) {
                    int lo = sbyte(r, s, b + 1);
                    if (ra != v && rb != lo && v && lo) {
                        printf("\tldd\t#$%02X%02X\n", v, lo);
                        cycles += 3; ra = v; rb = lo;
                    } else {
                        cycles += load8('a', &ra, v);
                        cycles += load8('b', &rb, lo);
                    }
                    printf("\tstd\t%d,x\n", off); cycles += 5; b++;
                } else {
                    cycles += load8('a', &ra, v);
                    printf("\tstaa\t%d,x\n", off); cycles += 4;
                }
            } else if (kind == 'e') {
                cycles += load8('b', &rb, 0);       /* an ABX may have used B */
                if (pair) { printf("\tstd\t%d,x\n", off); cycles += 5; b++; }
                else { printf("\tstaa\t%d,x\n", off); cycles += 4; }
            } else {
                printf("\tldaa\t%d,x\n\t%s\t#$%02X\n\tstaa\t%d,x\n",
                       off, kind == 'o' ? "oraa" : "eora", v, off);
                cycles += 10;
            }
        }
    }
    printf("\trts\t\t\t; %d cycles + rts\n", cycles);
}

static void emit(void)
{
    int shifts = artifact ? 4 : 8;
    printf("\n; ---- sprite %s: %dx%d %s\n", name, w, h, artifact ? "artifact" : "mono");
    printf("%s_W\tequ\t%d\n%s_H\tequ\t%d\n%s_SHIFTS\tequ\t%d\n%s_PAD\tequ\t%d\n",
           name, w, name, h, name, shifts, name, pad);
    const char *kinds = pad ? "oxes" : "oxe";
    int nk = (int)strlen(kinds);
    for (int k = 0; k < nk; k++) {
        printf("%s_%cr:\n", name, kinds[k]);
        for (int s = 0; s < shifts; s++) printf("\tfdb\t%s_%cr%d\n", name, kinds[k], s);
    }
    for (int k = 0; k < nk; k++)
        for (int s = 0; s < shifts; s++) routine(kinds[k], s);
}

/* Surround the art with a blank border of pad pixels on every side. */
static int apply_pad(void)
{
    if (!pad) return 1;
    if (w + 2 * pad > MAXW || h + 2 * pad > MAXH) return 0;
    for (int r = h - 1; r >= 0; r--) {
        memmove(art[r + pad] + pad, art[r], (size_t)w);
        memset(art[r + pad], '.', (size_t)pad);
        memset(art[r + pad] + pad + w, '.', (size_t)pad);
    }
    for (int r = 0; r < pad; r++) {
        memset(art[r], '.', MAXW);
        memset(art[h + pad + r], '.', MAXW);
    }
    w += 2 * pad;
    h += 2 * pad;
    return 1;
}

int main(int argc, char **argv)
{
    if (argc != 2) { fprintf(stderr, "usage: spritec IN.spr > OUT.inc\n"); return 2; }
    FILE *f = fopen(argv[1], "r");
    if (!f) { perror(argv[1]); return 1; }
    printf("; generated by spritec from %s: do not edit\n", argv[1]);
    char line[512], mode[32];
    int in = 0, lineno = 0;
    while (fgets(line, sizeof line, f)) {
        lineno++;
        line[strcspn(line, "\r\n")] = 0;
        if (!in) {
            pad = 0;
            if (sscanf(line, "sprite %63s %31s pad %d", name, mode, &pad) >= 2) {
                if (pad < 0 || pad > 16) { fprintf(stderr, "%s:%d: pad must be 0-16\n", argv[1], lineno); return 1; }
                artifact = !strcmp(mode, "artifact");
                if (!artifact && strcmp(mode, "mono")) {
                    fprintf(stderr, "%s:%d: mode must be mono or artifact\n", argv[1], lineno);
                    return 1;
                }
                in = 1; w = h = 0;
            }
            continue;
        }
        if (!strcmp(line, "end")) {
            if (!w || !h) { fprintf(stderr, "%s:%d: empty sprite\n", argv[1], lineno); return 1; }
            if (!apply_pad()) { fprintf(stderr, "%s:%d: sprite too big with its pad\n", argv[1], lineno); return 1; }
            emit();
            in = 0;
            continue;
        }
        int len = (int)strlen(line);
        if (len > MAXW || h >= MAXH) { fprintf(stderr, "%s:%d: sprite too big\n", argv[1], lineno); return 1; }
        if (len > w) w = len;
        memset(art[h], '.', MAXW);
        memcpy(art[h], line, (size_t)len);
        h++;
    }
    fclose(f);
    if (in) { fprintf(stderr, "%s: missing end\n", argv[1]); return 1; }
    return 0;
}
