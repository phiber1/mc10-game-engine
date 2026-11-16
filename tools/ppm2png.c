/* ppm2png: convert a binary PPM (P6) to an uncompressed PNG, no libraries.
 *
 *   ppm2png IN.ppm OUT.png
 *
 * Public domain (Unlicense).
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint32_t crc_table[256];

static uint32_t crc(uint32_t c, const uint8_t *p, size_t n)
{
    while (n--) c = crc_table[(c ^ *p++) & 0xFF] ^ (c >> 8);
    return c;
}

static void put32(uint8_t *p, uint32_t v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = (uint8_t)v; }

static void chunk(FILE *f, const char *type, const uint8_t *d, uint32_t n)
{
    uint8_t b[4];
    put32(b, n); fwrite(b, 1, 4, f);
    fwrite(type, 1, 4, f);
    if (n) fwrite(d, 1, n, f);
    uint32_t c = crc(0xFFFFFFFFu, (const uint8_t *)type, 4);
    c = crc(c, d, n) ^ 0xFFFFFFFFu;
    put32(b, c); fwrite(b, 1, 4, f);
}

int main(int argc, char **argv)
{
    if (argc != 3) { fprintf(stderr, "usage: ppm2png IN.ppm OUT.png\n"); return 2; }
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
        crc_table[i] = c;
    }
    FILE *in = fopen(argv[1], "rb");
    if (!in) { perror(argv[1]); return 1; }
    int w, h, max;
    if (fscanf(in, "P6 %d %d %d", &w, &h, &max) != 3 || max != 255 || w <= 0 || h <= 0) {
        fprintf(stderr, "ppm2png: not an 8-bit P6 file\n"); return 1;
    }
    fgetc(in);
    size_t row = (size_t)w * 3 + 1, rawn = row * (size_t)h;
    uint8_t *raw = malloc(rawn);
    for (int y = 0; y < h; y++) {
        raw[y * row] = 0;                                   /* filter: none */
        if (fread(raw + y * row + 1, 1, row - 1, in) != row - 1) { fprintf(stderr, "ppm2png: short file\n"); return 1; }
    }
    fclose(in);

    /* zlib stream of stored (uncompressed) deflate blocks */
    size_t nblk = (rawn + 65534) / 65535;
    uint8_t *z = malloc(rawn + nblk * 5 + 6), *p = z;
    *p++ = 0x78; *p++ = 0x01;
    uint32_t a = 1, b = 0;
    for (size_t off = 0; off < rawn; off += 65535) {
        size_t n = rawn - off > 65535 ? 65535 : rawn - off;
        *p++ = off + n == rawn;
        *p++ = n & 0xFF; *p++ = n >> 8; *p++ = ~n & 0xFF; *p++ = (~n >> 8) & 0xFF;
        memcpy(p, raw + off, n); p += n;
        for (size_t i = 0; i < n; i++) { a = (a + raw[off + i]) % 65521; b = (b + a) % 65521; }
    }
    put32(p, (b << 16) | a); p += 4;

    FILE *out = fopen(argv[2], "wb");
    if (!out) { perror(argv[2]); return 1; }
    fwrite("\x89PNG\r\n\x1a\n", 1, 8, out);
    uint8_t ihdr[13];
    put32(ihdr, (uint32_t)w); put32(ihdr + 4, (uint32_t)h);
    ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = ihdr[11] = ihdr[12] = 0;   /* 8-bit RGB */
    chunk(out, "IHDR", ihdr, 13);
    chunk(out, "IDAT", z, (uint32_t)(p - z));
    chunk(out, "IEND", NULL, 0);
    fclose(out);
    return 0;
}
