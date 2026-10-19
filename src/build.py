"""Xeno Crisis (Genesis v1.0.0) enhancement patch builder.

Source xc.s is split by 'BLOCK <name>' lines. Blocks are measured, packed into free
ROM areas (padding inside the 256-byte sound-effect name records + end of ROM), then
assembled at their final addresses. Hooks into original code are listed in PATCHES.
"""
import re, struct, subprocess, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
VASM = os.path.join(HERE, 'vasmm68k_mot')
CLEAN_MD5 = '50cca5273cdb6d6df36cbd29dbd3ff7f'

def free_chunks(rom):
    chunks = []
    for a in range(0x95a00, 0x3ff000, 0x100):
        m = re.match(rb'([A-Z0-9_]{3,24})\x00', rom[a:a + 32])
        if m:
            s = a + len(m.group(1)) + 1
            if all(b == 0 for b in rom[s:a + 0x100]):
                start = (s + 16 + 1) & ~1          # 16-byte margin after the name
                chunks.append([start, a + 0x100])
    chunks.append([0x3FFE20, 0x400000])            # end-of-ROM padding
    return chunks

def assemble(src, defines):
    path = os.path.join(HERE, '_build.s')
    open(path, 'w').write(src)
    args = [VASM, '-Fsrec', '-quiet', '-nowarn=62', '-o', os.path.join(HERE, '_build.srec'),
            '-L', os.path.join(HERE, '_build.lst')]
    for k, v in defines.items(): args += ['-D%s=%d' % (k, v)]
    r = subprocess.run(args + [path], capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stdout + r.stderr)
    recs = []
    for line in open(os.path.join(HERE, '_build.srec')):
        if line.startswith('S3'):
            n = int(line[2:4], 16); addr = int(line[4:12], 16)
            recs.append((addr, bytes.fromhex(line[12:12 + (n - 5) * 2])))
    syms = {}
    for line in open(os.path.join(HERE, '_build.lst')):
        m = re.match(r'^([0-9A-F]{8}) (\w+)\s*$', line.strip())
        if m: syms[m.group(2)] = int(m.group(1), 16)
    return recs, syms

def split_blocks(text):
    parts = re.split(r'^\s*BLOCK\s+(\w+)(?:[ \t]+(LOW))?[ \t]*$', text, flags=re.M)
    header = parts[0]
    blocks = [(parts[i], parts[i + 2], parts[i + 1] == 'LOW') for i in range(1, len(parts), 3)]
    return header, blocks

def join(header, blocks, orgs):
    out = header
    for (name, body, low), org in zip(blocks, orgs):
        out += '\n        org $%X\n%s:\n%s' % (org, '_blk_' + name, body)
    return out

def build(src_rom, dst_rom, variant='dc', defines=None):
    rom = bytearray(open(src_rom, 'rb').read())
    assert len(rom) == 0x400000
    import hashlib
    assert hashlib.md5(rom).hexdigest() == CLEAN_MD5, 'not the clean v1.0.0 ROM'
    defines = dict(defines or {}); defines['VARIANT_SWITCH'] = 1 if variant == 'switch' else 0
    text = open(os.path.join(HERE, os.environ.get('XC_SRC', 'xc.s'))).read()
    header, blocks = split_blocks(text)
    # pass 1: measure
    fake = [0x1000000 + i * 0x10000 for i in range(len(blocks))]    # (well away from the I/O addresses: no pc-relative surprises)
    recs, _ = assemble(join(header, blocks, fake), defines)
    sizes = []
    for i, f in enumerate(fake):
        hi = max([a + len(d) for a, d in recs if f <= a < f + 0x10000] + [f])
        sizes.append((hi - f + 1) & ~1)
    # allocate (first-fit decreasing)
    chunks = free_chunks(rom)
    orgs = [None] * len(blocks)
    # Enhanced blocks first, then MD+ Voices (mdp_*): Enhanced's layout never depends on Voices
    for i in sorted(range(len(blocks)), key=lambda i: (blocks[i][0].startswith('mdp_'), -sizes[i])):
        # blocks that don't need to be LOW try the space above the save-RAM window first
        order = chunks if blocks[i][2] else sorted(chunks, key=lambda c: c[1] <= 0x200000)
        for c in order:
            if blocks[i][2] and c[1] > 0x200000: continue      # LOW: below the save-RAM window
            if c[1] - c[0] >= sizes[i]:
                orgs[i] = c[0]; c[0] += sizes[i]; break
        else:
            sys.exit('no room for block %s (%d bytes)' % (blocks[i][0], sizes[i]))
    # pass 2: final
    recs, syms = assemble(join(header, blocks, orgs), defines)
    allowed = [(orgs[i], orgs[i] + sizes[i]) for i in range(len(blocks))]
    for a, d in recs:
        assert any(lo <= a and a + len(d) <= hi for lo, hi in allowed), 'record outside block @%06x' % a
        assert rom[a:a + len(d)] == bytes(len(d)), 'target not free @%06x' % a
        rom[a:a + len(d)] = d
    # hooks into the original code
    from patches import PATCHES
    for addr, expect, new in PATCHES(variant):
        expect = bytes.fromhex(expect)
        new = bytes.fromhex(new.format(**{k: '%08X' % v for k, v in syms.items()}))
        assert bytes(rom[addr:addr + len(expect)]) == expect, 'unexpected bytes at %06x' % addr
        rom[addr:addr + len(new)] = new
    for fn in getattr(__import__('patches'), 'POST', []):
        fn(rom, syms)
    cs = sum(struct.unpack('>%dH' % ((len(rom) - 0x200) // 2), rom[0x200:])) & 0xFFFF
    rom[0x18E:0x190] = struct.pack('>H', cs)
    open(dst_rom, 'wb').write(rom)
    used = sum(sizes)
    return syms, used, sorted(zip(orgs, sizes, [b[0] for b in blocks]))

if __name__ == '__main__':
    variant = sys.argv[3] if len(sys.argv) > 3 else 'dc'
    syms, used, layout = build(sys.argv[1], sys.argv[2], variant)
    print('built %s (%s), %d bytes of new code/data in %d blocks' % (sys.argv[2], variant, used, len(layout)))
    for org, size, name in layout: print('  %06X %4d %s' % (org, size, name))
