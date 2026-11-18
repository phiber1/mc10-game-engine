#!/usr/bin/env python3
"""nameless: replace ASL nameless labels (+ and -) with named ones.

    nameless.py FILE.asm > NEW.asm

ASL's nameless labels are easy to break: a `bne +` jumps to the next `+`,
so inserting another `+` in between silently retargets it.  This gives
every nameless definition a name (the nearest named label before it plus
_f1, _f2 ... or _b1 ...) and rewrites each reference (`+`, `++`, `-`,
`--` ...) to the definition ASL would choose, so the assembled code is
unchanged.  Public domain (Unlicense).
"""
import re, sys

lines = open(sys.argv[1]).read().split('\n')
label_re = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*):')
defs = []                                  # (line index, kind '+'/'-')
for i, l in enumerate(lines):
    m = re.match(r'^([+-])(\s|$)', l)
    if m: defs.append((i, m.group(1)))

# names for the definitions
names = {}
count = {}
last = 'top'
for i, l in enumerate(lines):
    m = label_re.match(l)
    if m: last = m.group(1); continue
    if re.match(r'^[+-](\s|$)', l):
        kind = l[0]
        count[(last, kind)] = count.get((last, kind), 0) + 1
        names[i] = f"{last}_{'f' if kind == '+' else 'b'}{count[(last, kind)]}"

out = []
for i, l in enumerate(lines):
    new = l
    # rewrite a reference in the operand field
    m = re.match(r'^(\S*\s+)([a-z]{2,4})(\s+)([+-]+)(\s*;.*|\s*)$', new)
    if m and m.group(2).lower() in (
            'bra', 'brn', 'bhi', 'bls', 'bcc', 'bhs', 'bcs', 'blo', 'bne', 'beq', 'bvc',
            'bvs', 'bpl', 'bmi', 'bge', 'blt', 'bgt', 'ble', 'bsr', 'jmp', 'jsr'):
        ref = m.group(4)
        kind, n = ref[0], len(ref)
        if kind == '+':
            cands = [d for d, k in defs if k == '+' and d > i]
            tgt = cands[n - 1]
        else:
            cands = [d for d, k in defs if k == '-' and d <= i]
            tgt = cands[-n]
        new = m.group(1) + m.group(2) + m.group(3) + names[tgt] + m.group(5)
    # rewrite a definition
    if i in names:
        rest = new[1:].strip()
        lbl = names[i] + ':'
        if not rest: new = lbl
        elif len(lbl) < 16: new = lbl.ljust(16) + rest
        else: new = lbl + '\n' + ' ' * 16 + rest
    out.append(new)
sys.stdout.write('\n'.join(out))
