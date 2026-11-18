/* p2decb: turn an AS (ASL) object file into a CoCo DECB binary (.BIN),
 * one segment per contiguous block of code, for the MCX32-SD's LOADM.
 *
 *   p2decb IN.p OUT.bin EXEC [LIMITS...]
 *
 * EXEC is the start address (hex).  Each LIMIT is LO-HI (hex, inclusive):
 * if given, every byte must fall inside one of them (the build fails
 * otherwise), which keeps segments clear of BASIC and the SD BIOS while
 * LOADM runs.  Prints the segments it wrote.
 *
 * P format: magic $1489, then records: $81 family segment granularity
 * start(4, LE) length(2, LE) data; $80 entry(4); $00 creator (end);
 * other headers (old style): start(4) length(2) data.
 *
 * Public domain (Unlicense).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned char mem[65536], used[65536];

static unsigned long le(const unsigned char *p, int n)
{
    unsigned long v = 0;
    for (int i = n - 1; i >= 0; i--) v = v << 8 | p[i];
    return v;
}

int main(int argc, char **argv)
{
    if (argc < 4) { fprintf(stderr, "usage: p2decb IN.p OUT.bin EXEC [LO-HI ...]\n"); return 2; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    static unsigned char buf[1 << 20];
    size_t n = fread(buf, 1, sizeof buf, f);
    fclose(f);
    if (n < 2 || buf[0] != 0x89 || buf[1] != 0x14) { fprintf(stderr, "%s: not an AS P file\n", argv[1]); return 1; }
    size_t i = 2;
    while (i < n) {
        int h = buf[i++];
        if (h == 0x00) break;                       /* creator: the end */
        if (h == 0x80) { i += 4; continue; }        /* entry point */
        if (h == 0x81) i += 3;                      /* family, segment, granularity */
        if (i + 6 > n) { fprintf(stderr, "%s: truncated record\n", argv[1]); return 1; }
        unsigned long start = le(buf + i, 4), len = le(buf + i + 4, 2);
        i += 6;
        if (i + len > n || start + len > 0x10000) { fprintf(stderr, "%s: bad record at $%lX\n", argv[1], start); return 1; }
        for (unsigned long k = 0; k < len; k++) { mem[start + k] = buf[i + k]; used[start + k] = 1; }
        i += len;
    }
    /* limits */
    int nlim = argc - 4, bad = 0;
    for (long a = 0; a < 0x10000 && nlim; a++) {
        if (!used[a]) continue;
        int ok = 0;
        for (int l = 0; l < nlim; l++) {
            unsigned lo, hi;
            if (sscanf(argv[4 + l], "%x-%x", &lo, &hi) == 2 && a >= (long)lo && a <= (long)hi) ok = 1;
        }
        if (!ok) {
            long b = a;
            while (b + 1 < 0x10000 && used[b + 1]) b++;
            fprintf(stderr, "p2decb: $%04lX-$%04lX is outside the allowed ranges\n", a, b);
            bad = 1;
            a = b;
        }
    }
    if (bad) return 1;
    FILE *o = fopen(argv[2], "wb");
    if (!o) { perror(argv[2]); return 1; }
    for (long a = 0; a < 0x10000; ) {
        if (!used[a]) { a++; continue; }
        long b = a;
        while (b + 1 < 0x10000 && used[b + 1] && b + 1 - a < 0xFF00) b++;
        long len = b - a + 1;
        fputc(0x00, o); fputc((int)(len >> 8), o); fputc((int)(len & 0xFF), o);
        fputc((int)(a >> 8), o); fputc((int)(a & 0xFF), o);
        fwrite(mem + a, 1, (size_t)len, o);
        printf("  segment $%04lX-$%04lX  %5ld bytes\n", a, b, len);
        a = b + 1;
    }
    unsigned exec = (unsigned)strtoul(argv[3], NULL, 16);
    fputc(0xFF, o); fputc(0, o); fputc(0, o);
    fputc((int)(exec >> 8), o); fputc((int)(exec & 0xFF), o);
    fclose(o);
    printf("  exec   $%04X\n", exec);
    return 0;
}
