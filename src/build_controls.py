"""Xeno Crisis: Definitive Edition - Controls-only patches (roll fix + pause stats).

usage: build_controls.py <clean rom> <out dir> <version>
Writes XenoCrisis_DefinitiveEdition_v<version>_Controls_Dreamcast.ips and _Controls_Modern.ips.
Needs vasmm68k_mot next to this script; the code is in hack.s.
"""
import struct, sys, subprocess, re, os

HERE = os.path.dirname(os.path.abspath(__file__))

def assemble():
    subprocess.run([os.path.join(HERE, 'vasmm68k_mot'), '-Fbin', '-quiet', '-o', os.path.join(HERE, 'hack.bin'),
                    '-L', os.path.join(HERE, 'hack.lst'), os.path.join(HERE, 'hack.s')], check=True)
    code = open(os.path.join(HERE, 'hack.bin'), 'rb').read()
    syms = {}
    for line in open(os.path.join(HERE, 'hack.lst')):
        m = re.match(r'^([0-9A-F]{8}) (\w+)\s*$', line.strip())
        if m: syms[m.group(2)] = int(m.group(1), 16)
    return code, syms

def build(src, dst, hud=True, switch=False):
    rom = bytearray(open(src, 'rb').read())
    assert len(rom) == 0x400000
    code, syms = assemble()
    ORG = 0x3FFE20
    assert rom[ORG:ORG + len(code)] == bytes(len(code)), 'free area not empty'
    assert ORG + len(code) <= 0x400000
    rom[ORG:ORG + len(code)] = code

    def put(addr, expect, new):
        expect = bytes.fromhex(expect); new = bytes.fromhex(new)
        assert bytes(rom[addr:addr + len(expect)]) == expect, 'unexpected bytes at %06x' % addr
        rom[addr:addr + len(new)] = new

    # Roll priority
    put(0x262A, '4A6F004667004CD2', '4EF9%08X4E71' % syms['roll_hook'])
    if switch:
        # Switch style: a NEW fire press (not held fire) cancels a roll
        put(0x2EE0, '4A6F0046', '4A6F0054')        # tst.w $54(a7) = newly pressed fire buttons
    else:
        # Dreamcast style: fire never cancels a roll (only pressing roll again does)
        put(0x2EE0, '4A6F0046670012E8', '600012EC4E714E71')
    # Pause HUD: paused loop's vsync call -> our routine (which calls vsync first)
    if hud:
        put(0x3168A, '4EB9000519E6', '4EB9%08X' % syms['pause_hud'])

    cs = sum(struct.unpack('>%dH' % ((len(rom) - 0x200) // 2), rom[0x200:])) & 0xFFFF
    rom[0x18E:0x190] = struct.pack('>H', cs)
    open(dst, 'wb').write(rom)
    return syms

def ips(o, p):
    out = bytearray(b'PATCH'); i = 0
    while i < len(o):
        if o[i] != p[i]:
            j = i
            while j < len(o) and j - i < 0xffff and (o[j] != p[j] or any(o[k] != p[k] for k in range(j + 1, min(j + 6, len(o))))): j += 1
            out += i.to_bytes(3, 'big') + (j - i).to_bytes(2, 'big') + p[i:j]; i = j
        else: i += 1
    return bytes(out + b'EOF')

if __name__ == '__main__':
    src, out, ver = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    clean = open(src, 'rb').read()
    for name, sw in (('Dreamcast', False), ('Modern', True)):
        tmp = os.path.join(out, '_ctl.bin')
        build(src, tmp, switch=sw)
        rom = open(tmp, 'rb').read(); os.remove(tmp)
        path = os.path.join(out, 'XenoCrisis_DefinitiveEdition_v%s_Controls_%s.ips' % (ver, name))
        open(path, 'wb').write(ips(clean, rom))
        print('wrote', path)
