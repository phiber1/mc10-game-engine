/* spritec: compile text-art sprites into 6803 code for RG6.
 *
 *   spritec IN.spr > OUT.inc
 *   spritec -e IN.spr > OUT.inc   only the constants (NAME_W ... NAME_PADY):
 *                                 for a program whose sprite code is
 *                                 elsewhere (an overlay loaded later)
 *
 * Input: one or more sprites
 *
 *   sprite NAME mono|artifact|cg6 [pad N] [halo N | halo X Y] [delta]
 *               [shift S] [bg C]
 *   ..XXXX..           mono:     . = 0, X = 1                 (8 pixels/byte)
 *   .XXXXXX.           artifact: . black, O orange, B blue, W white
 *   end                          (4 pixels/byte, pairs 10=O 01=B at phase 0)
 *                      cg6:      G green, Y yellow, B blue, R red (CSS=0),
 *                                or W buff, C cyan, M magenta, O orange
 *                                (CSS=1): pairs 00, 01, 10, 11 (4/byte)
 *
 *   "." (or a space) is transparent: not part of the sprite.  "bg C" names
 *   the background color (a color letter of the mode; default: pixel value
 *   0, i.e. black, or green/buff in CG6): the halo, erase and store
 *   routines fill with it, so halo sprites work on a plain background of
 *   any color.  The OR, XOR and delta routines assume a background of 0.
 *
 * Output, for every horizontal sub-byte shift s (8 for mono, 4 for artifact):
 *
 *   NAME_or<s>  OR the sprite onto the screen   (transparent; uses A)
 *   NAME_xr<s>  XOR it                           (draw twice = erase; uses A)
 *   NAME_er<s>  clear the bytes NAME_or touches  (to the background; uses D)
 *   NAME_sr<s>  with "pad N": store the whole padded box, zeros included.
 *               The blank border erases the previous position as it draws,
 *               so a sprite moving at most N pixels a frame needs no erase.
 *   NAME_hr<s>  with "halo N": the sprite plus a halo (its shape grown by
 *               N pixels) cleared around it, in one read-modify-write pass.
 *               Erases its old position (moves up to N pixels) without
 *               ever going blank, and draws in front of anything drawn
 *               earlier: draw in priority order, lowest first.
 *               Halo sprites get only NAME_hr and NAME_er, plus NAME_dsc:
 *               a sprite manager descriptor (draw, erase, call, pad,
 *               visible width, visible height).
 *   NAME_or, NAME_xr, NAME_er (, NAME_sr / NAME_hr)  routine tables
 *   NAME_d<d>s<s>  with "delta": XOR(old, new) for a one-pixel move in
 *               direction d = (dy+1)*3 + (dx+1) from shift s, in one
 *               read-modify-write pass, so the sprite is never missing.
 *               Tables NAME_dt (9 pointers) -> NAME_dt<d> (one per shift).
 *               Call through spr_mono_d / spr_art_d with the OLD x, y.
 *   "shift S" compiles only shift S, and every entry of the routine tables
 *   points at it: the game must keep the sprite's x on that shift (x & 3
 *   = S for artifact, x & 7 for mono) and not move it across.  For big
 *   sprites that never move sideways (a warp ship, explosions) it saves
 *   three quarters (or seven eighths) of their code.
 *   NAME_W, NAME_H (including the pad), NAME_SHIFTS, NAME_PAD (= NAME_PADX),
 *   NAME_PADX, NAME_PADY.  "halo X Y" grows the halo X pixels across and
 *   Y rows down (artifact sprites: move half as far across as down).
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
static int artifact, cg6, twobpp, bgval, bgfill, w, h, pad, padx, pady, delta, halo, halox, haloy, oneshift, equonly;
static char art[MAXH][MAXW + 1];
static unsigned char hal[MAXH][MAXW];   /* halo: sprite grown by `halo` pixels */

/* the sprite's pixel bits at shift s: row r, byte b */
static int nbytes(int s) { int bpp = twobpp ? 2 : 1; return (w * bpp + s * bpp + 7) / 8; }

static int opaque(char c) { return c != '.' && c != ' '; }

/* a pixel's value in the current mode (-1: not a color of the mode) */
static int pixval(char c)
{
    if (!opaque(c)) return 0;
    if (cg6) return strchr("GW", c) ? 0 : strchr("YC", c) ? 1 : strchr("BM", c) ? 2 : strchr("RO", c) ? 3 : -1;
    if (artifact) return c == 'W' ? 3 : c == 'O' ? 2 : c == 'B' ? 1 : 0;
    return 1;
}

static unsigned char sbyte(int r, int s, int b)
{
    int bpp = twobpp ? 2 : 1;
    unsigned char v = 0;
    for (int bit = 0; bit < 8; bit += bpp) {
        int px = (b * 8 + bit) / bpp - s;          /* sprite pixel in this slot */
        if (px < 0 || px >= w) continue;
        v |= (unsigned char)(pixval(art[r][px]) << (8 - bpp - bit));
    }
    return v;
}

/* the bits of the sprite's own (opaque) pixels at shift s: row r, byte b */
static unsigned char obyte(int r, int s, int b)
{
    int bpp = twobpp ? 2 : 1;
    unsigned char m = 0;
    for (int bit = 0; bit < 8; bit += bpp) {
        int px = (b * 8 + bit) / bpp - s;
        if (px < 0 || px >= w || !opaque(art[r][px])) continue;
        m |= (unsigned char)(((1 << bpp) - 1) << (8 - bpp - bit));
    }
    return m;
}

/* the halo mask bits at shift s: row r, byte b (all bits of a halo pixel) */
static unsigned char mbyte(int r, int s, int b)
{
    int bpp = twobpp ? 2 : 1;
    unsigned char m = 0;
    for (int bit = 0; bit < 8; bit += bpp) {
        int px = (b * 8 + bit) / bpp - s;
        if (px < 0 || px >= w || !hal[r][px]) continue;
        m |= (unsigned char)(((1 << bpp) - 1) << (8 - bpp - bit));
    }
    return m;
}

/* Build the halo: every pixel within `halo` pixels (square distance, so
 * diagonal moves are covered) of a sprite pixel.  The art is already
 * padded by `halo`, so the halo fits in the box. */
static void build_halo(void)
{
    memset(hal, 0, sizeof hal);
    for (int r = 0; r < h; r++)
        for (int c = 0; c < w; c++) {
            if (art[r][c] == '.' || art[r][c] == ' ') continue;
            for (int dr = -haloy; dr <= haloy; dr++)
                for (int dc = -halox; dc <= halox; dc++) {
                    int rr = r + dr, cc = c + dc;
                    if (rr >= 0 && rr < h && cc >= 0 && cc < w) hal[rr][cc] = 1;
                }
        }
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
 * border this erases the sprite's previous position as it draws),
 * 'h' halo (clears the halo and draws the sprite: plain stores where a
 * byte is all halo, AND/OR read-modify-write on the halo's edge) */
static void routine(int kind, int s)
{
    printf("%s_%cr%d:\n", name, kind, s);
    int base = 0;                                   /* screen offset X points at */
    int cycles = 0;
    int ra = -1, rb = -1;                           /* known A and B contents */
    if (kind == 'e') {
        if (bgfill) { printf("\tldd\t#$%02X%02X\n", bgfill, bgfill); cycles += 3; }
        else { printf("\tclra\n\tclrb\n"); cycles += 4; }
        ra = rb = bgfill;
    }
    for (int r = 0; r < h; r++) {
        int nb = nbytes(s);
        for (int b = 0; b < nb; b++) {
            unsigned char v = sbyte(r, s, b);
            unsigned char m = kind == 'h' ? mbyte(r, s, b) : 0;
            if (kind == 'h') v |= bgfill & m & ~obyte(r, s, b);    /* the halo: background */
            if (kind == 's') v |= bgfill & ~obyte(r, s, b);
            if (kind == 'h' ? !m : kind == 'e' ? !obyte(r, s, b) : (!v && kind != 's')) continue;
            int store = kind == 's' || (kind == 'h' && m == 0xFF);
            int off = r * 32 + b - base;
            int pair = b + 1 < nb && ((kind == 's') ||
                                      (kind == 'h' && m == 0xFF && mbyte(r, s, b + 1) == 0xFF) ||
                                      (kind == 'e' && obyte(r, s, b + 1)));
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
            if (kind == 'h' && !store) {            /* halo edge: clear halo, add sprite */
                printf("\tldaa\t%d,x\n\tanda\t#$%02X\n", off, (unsigned char)~m);
                cycles += 6;
                if (v) { printf("\toraa\t#$%02X\n", v); cycles += 2; }
                printf("\tstaa\t%d,x\n", off); cycles += 4;
                ra = -1;
            } else if (store) {
                if (pair) {
                    int lo = sbyte(r, s, b + 1);
                    if (kind == 'h') lo |= bgfill & ~obyte(r, s, b + 1);   /* (all halo) */
                    if (kind == 's') lo |= bgfill & ~obyte(r, s, b + 1);
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
                cycles += load8('b', &rb, bgfill);  /* an ABX may have used B */
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

/* XOR delta routine: one read-modify-write pass of XOR(old, new) that moves
 * the sprite one pixel from shift s in direction (dx, dy).  Every changed
 * byte goes straight from the old picture to the new one, so the sprite is
 * never missing.  X points one row up and one byte left of the old position
 * (the engine's spr_mono_d / spr_art_d subtract 33), so all offsets are
 * positive. */
#define DROWS (MAXH + 2)
#define DBYTES 34
static void delta_routine(int d, int s)
{
    static unsigned char g[DROWS][DBYTES];
    int dx = d % 3 - 1, dy = d / 3 - 1;
    int bpp = twobpp ? 2 : 1, m = 8 / bpp;          /* one byte of margin, in pixels */
    memset(g, 0, sizeof g);
    for (int pass = 0; pass < 2; pass++)            /* old image, then new */
        for (int r = 0; r < h; r++)
            for (int c = 0; c < w; c++) {
                char ch = art[r][c];
                int val = pixval(ch);
                if (!val) continue;
                int px = c + s + m + (pass ? dx : 0), row = r + 1 + (pass ? dy : 0);
                int bit = px * bpp % 8;
                g[row][px * bpp / 8] ^= (unsigned char)(val << (8 - bpp - bit));
            }
    printf("%s_d%ds%d:\n", name, d, s);
    int base = 0, cycles = 0;
    for (int row = 0; row < h + 2; row++)
        for (int b = 0; b < DBYTES; b++) {
            unsigned char v = g[row][b];
            if (!v) continue;
            int off = row * 32 + b - base;
            while (off > 255) {
                int st = row * 32 - base;
                if (st > 224) st = 224;
                printf("\tldab\t#%d\n\tabx\n", st);
                cycles += 5;
                base += st;
                off = row * 32 + b - base;
            }
            printf("\tldaa\t%d,x\n\teora\t#$%02X\n\tstaa\t%d,x\n", off, v, off);
            cycles += 10;
        }
    printf("\trts\t\t\t; %d cycles + rts\n", cycles);
}

static void emit_delta(void)
{
    int shifts = twobpp ? 4 : 8;
    /* NAME_dt: 9 direction tables, index (dy+1)*3 + (dx+1); 4 = no move */
    printf("%s_dt:\n", name);
    for (int d = 0; d < 9; d++) printf("\tfdb\t%s_dt%d\n", name, d);
    for (int d = 0; d < 9; d++) {
        printf("%s_dt%d:\n", name, d);
        for (int s = 0; s < shifts; s++)
            if (d == 4) printf("\tfdb\t%s_dnop\n", name);
            else printf("\tfdb\t%s_d%ds%d\n", name, d, s);
    }
    printf("%s_dnop:\n\trts\n", name);
    for (int d = 0; d < 9; d++)
        if (d != 4)
            for (int s = 0; s < shifts; s++) delta_routine(d, s);
}

static void emit(void)
{
    int shifts = twobpp ? 4 : 8;
    printf("\n; ---- sprite %s: %dx%d %s\n", name, w, h, cg6 ? "cg6" : artifact ? "artifact" : "mono");
    printf("%s_W\tequ\t%d\n%s_H\tequ\t%d\n%s_SHIFTS\tequ\t%d\n%s_PAD\tequ\t%d\n",
           name, w, name, h, name, shifts, name, padx);
    printf("%s_PADX\tequ\t%d\n%s_PADY\tequ\t%d\n", name, padx, name, pady);
    if (equonly) return;
    /* halo sprites only need their halo and erase routines */
    const char *kinds = halo ? "eh" : pad ? "oxes" : "oxe";
    int nk = (int)strlen(kinds);
    for (int k = 0; k < nk; k++) {
        printf("%s_%cr:\n", name, kinds[k]);
        for (int s = 0; s < shifts; s++)
            printf("\tfdb\t%s_%cr%d\n", name, kinds[k], oneshift >= 0 ? oneshift : s);
    }
    for (int k = 0; k < nk; k++)
        for (int s = 0; s < shifts; s++)
            if (oneshift < 0 || s == oneshift) routine(kinds[k], s);
    if (delta) emit_delta();
    if (halo) {
        /* a sprite manager descriptor (engine/sprman.asm) with the hitbox */
        int bpp = twobpp ? 2 : 1;
        printf("%s_dsc:\n\tfdb\t%s_hr, %s_er, %s\n", name, name, name,
               twobpp ? "spr_art" : "spr_mono");
        printf("\tfcb\t%d, %d, %d, %d\t; pad x, pad y, visible width, height\n",
               padx, pady, w - 2 * padx, h - 2 * pady);
        (void)bpp;
    }
}

/* Surround the art with a blank border: padx pixels left and right, pady
 * rows above and below. */
static int apply_pad(void)
{
    if (!padx && !pady) return 1;
    if (w + 2 * padx > MAXW || h + 2 * pady > MAXH) return 0;
    for (int r = h - 1; r >= 0; r--) {
        memmove(art[r + pady] + padx, art[r], (size_t)w);
        memset(art[r + pady], '.', (size_t)padx);
        memset(art[r + pady] + padx + w, '.', (size_t)padx);
    }
    for (int r = 0; r < pady; r++) {
        memset(art[r], '.', MAXW);
        memset(art[h + pady + r], '.', MAXW);
    }
    w += 2 * padx;
    h += 2 * pady;
    return 1;
}

int main(int argc, char **argv)
{
    if (argc == 3 && !strcmp(argv[1], "-e")) { equonly = 1; argv++; argc--; }
    if (argc != 2) { fprintf(stderr, "usage: spritec [-e] IN.spr > OUT.inc\n"); return 2; }
    FILE *f = fopen(argv[1], "r");
    if (!f) { perror(argv[1]); return 1; }
    printf("; generated by spritec%s from %s: do not edit\n", equonly ? " -e" : "", argv[1]);
    char line[512], mode[32];
    int in = 0, lineno = 0;
    while (fgets(line, sizeof line, f)) {
        lineno++;
        line[strcspn(line, "\r\n")] = 0;
        if (!in) {
            pad = padx = pady = 0; delta = 0; halo = halox = haloy = 0; oneshift = -1;
            char bgc = 0;
            if (sscanf(line, "sprite %63s %31s", name, mode) == 2) {
                /* options after the mode, in any order:
                 * pad N, halo N, halo X Y (across, down), delta */
                char *opt = strstr(line, mode) + strlen(mode), *tok[16];
                int nt = 0;
                for (char *t = strtok(opt, " \t"); t && nt < 16; t = strtok(NULL, " \t")) tok[nt++] = t;
                for (int i = 0; i < nt; i++) {
                    if (!strcmp(tok[i], "delta")) delta = 1;
                    else if (!strcmp(tok[i], "halo") && i + 1 < nt) {
                        halo = 1;
                        halox = haloy = atoi(tok[++i]);
                        if (i + 1 < nt && isdigit((unsigned char)tok[i + 1][0])) haloy = atoi(tok[++i]);
                        padx = halox; pady = haloy; pad = halox;
                    }
                    else if (!strcmp(tok[i], "pad") && i + 1 < nt) pad = padx = pady = atoi(tok[++i]);
                    else if (!strcmp(tok[i], "shift") && i + 1 < nt) oneshift = atoi(tok[++i]);
                    else if (!strcmp(tok[i], "bg") && i + 1 < nt && strlen(tok[i + 1]) == 1) bgc = tok[++i][0];
                    else { fprintf(stderr, "%s:%d: bad option %s\n", argv[1], lineno, tok[i]); return 1; }
                }
                if (padx < 0 || padx > 16 || pady < 0 || pady > 16) {
                    fprintf(stderr, "%s:%d: pad and halo must be 0-16\n", argv[1], lineno);
                    return 1;
                }
                artifact = !strcmp(mode, "artifact");
                cg6 = !strcmp(mode, "cg6");
                twobpp = artifact || cg6;
                if (oneshift >= (twobpp ? 4 : 8) || (oneshift >= 0 && delta)) {
                    fprintf(stderr, "%s:%d: bad shift (0-3 artifact/cg6, 0-7 mono; not with delta)\n", argv[1], lineno);
                    return 1;
                }
                if (!twobpp && strcmp(mode, "mono")) {
                    fprintf(stderr, "%s:%d: mode must be mono, artifact or cg6\n", argv[1], lineno);
                    return 1;
                }
                bgval = 0;
                if (bgc) {
                    bgval = pixval(bgc);
                    if (bgval < 0 || !opaque(bgc)) {
                        fprintf(stderr, "%s:%d: bg %c is not a color of %s\n", argv[1], lineno, bgc, mode);
                        return 1;
                    }
                }
                bgfill = twobpp ? bgval * 0x55 : bgval * 0xFF;
                if (bgfill && delta) {
                    fprintf(stderr, "%s:%d: delta sprites need a background of 0\n", argv[1], lineno);
                    return 1;
                }
                in = 1; w = h = 0;
            }
            continue;
        }
        if (!strcmp(line, "end")) {
            if (!w || !h) { fprintf(stderr, "%s:%d: empty sprite\n", argv[1], lineno); return 1; }
            if (!apply_pad()) { fprintf(stderr, "%s:%d: sprite too big with its pad\n", argv[1], lineno); return 1; }
            if (halo) build_halo();
            emit();
            in = 0;
            continue;
        }
        int len = (int)strlen(line);
        if (len > MAXW || h >= MAXH) { fprintf(stderr, "%s:%d: sprite too big\n", argv[1], lineno); return 1; }
        for (int i = 0; i < len; i++)
            if (pixval(line[i]) < 0) {
                fprintf(stderr, "%s:%d: %c is not a color of cg6 (G Y B R, W C M O)\n", argv[1], lineno, line[i]);
                return 1;
            }
        if (len > w) w = len;
        memset(art[h], '.', MAXW);
        memcpy(art[h], line, (size_t)len);
        h++;
    }
    fclose(f);
    if (in) { fprintf(stderr, "%s: missing end\n", argv[1]); return 1; }
    return 0;
}
