/* mkc10: wrap a raw binary as an MC-10 cassette image (.C10, for CLOADM)
 * or a CoCo DECB binary (.BIN, for the MCX32-SD's LOADM).
 *
 *   mkc10 IN.raw OUT.c10|OUT.bin NAME LOAD EXEC      (LOAD, EXEC in hex)
 *
 * Public domain (Unlicense).
 */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

static void block(FILE *f, int type, const unsigned char *d, int n)
{
    unsigned char sum = (unsigned char)(type + n);
    fputc(0x55, f); fputc(0x3C, f); fputc(type, f); fputc(n, f);
    for (int i = 0; i < n; i++) { fputc(d[i], f); sum += d[i]; }
    fputc(sum, f);
    fputc(0x55, f);
}

int main(int argc, char **argv)
{
    if (argc != 6) {
        fprintf(stderr, "usage: mkc10 IN.raw OUT.c10|OUT.bin NAME LOAD EXEC (hex)\n");
        return 2;
    }
    FILE *in = fopen(argv[1], "rb");
    if (!in) { perror(argv[1]); return 1; }
    static unsigned char buf[65536];
    size_t len = fread(buf, 1, sizeof buf, in);
    fclose(in);
    unsigned load = (unsigned)strtoul(argv[4], NULL, 16);
    unsigned exec = (unsigned)strtoul(argv[5], NULL, 16);
    if (len == 0 || load + len > 0x10000) { fprintf(stderr, "mkc10: bad size or address\n"); return 1; }

    FILE *out = fopen(argv[2], "wb");
    if (!out) { perror(argv[2]); return 1; }
    const char *ext = strrchr(argv[2], '.');
    if (ext && !strcasecmp(ext, ".bin")) {
        /* DECB: preamble blocks (00 LEN ADDR data), postamble (FF 0000 EXEC) */
        for (size_t off = 0; off < len; off += 0xFF00) {
            size_t n = len - off > 0xFF00 ? 0xFF00 : len - off;
            unsigned a = load + (unsigned)off;
            fputc(0x00, out); fputc((int)(n >> 8), out); fputc((int)(n & 0xFF), out);
            fputc((int)(a >> 8), out); fputc((int)(a & 0xFF), out);
            fwrite(buf + off, 1, n, out);
        }
        fputc(0xFF, out); fputc(0, out); fputc(0, out);
        fputc((int)(exec >> 8), out); fputc((int)(exec & 0xFF), out);
    } else {
        unsigned char hdr[15];
        memset(hdr, ' ', 8);
        for (int i = 0; i < 8 && argv[3][i]; i++) hdr[i] = (unsigned char)toupper((unsigned char)argv[3][i]);
        hdr[8] = 2; hdr[9] = 0; hdr[10] = 0;          /* machine code, binary, no gaps */
        hdr[11] = (unsigned char)(exec >> 8); hdr[12] = (unsigned char)exec;
        hdr[13] = (unsigned char)(load >> 8); hdr[14] = (unsigned char)load;
        for (int i = 0; i < 128; i++) fputc(0x55, out);
        block(out, 0x00, hdr, 15);
        for (int i = 0; i < 128; i++) fputc(0x55, out);
        for (size_t off = 0; off < len; off += 255)
            block(out, 0x01, buf + off, (int)(len - off > 255 ? 255 : len - off));
        block(out, 0xFF, NULL, 0);
    }
    fclose(out);
    return 0;
}
