"""Build the two patches from one source:
  Enhanced  (controls, scoring, tables, ...)   = everything except the mdp_* blocks/hooks
  MD+ Voices                                    = only the mdp_* blocks/hooks
Both are laid out in one build, so they never overlap and stack in either order.

usage: make_release.py <clean rom> <out dir> <version>
(Xeno Crisis: Definitive Edition. The Controls-only patches are built by build_controls.py.)
"""
import sys, os, struct, zlib, hashlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build, mkbps

VOICE_HOOKS = [(0x0470, 8), (0x288C6, 6), (0x1B92E, 6), (0x1B6EE, 6), (0x1249E, 6), (0x12930, 6), (0x128D8, 6), (0x13534, 6)]

def checksum(rom):
    rom[0x18E:0x190] = struct.pack('>H', sum(struct.unpack('>%dH' % ((len(rom) - 0x200) // 2), rom[0x200:])) & 0xFFFF)

def ips(src, dst, skip=()):
    out = bytearray(b'PATCH'); i = 0; n = len(dst)
    while i < n:
        if src[i] == dst[i] or any(a <= i < b for a, b in skip): i += 1; continue
        j = i
        while j < n and src[j] != dst[j] and j - i < 0xFFFF and not any(a <= j < b for a, b in skip): j += 1
        if i == 0x454F46: i -= 1                       # 'EOF' offset can't start a record
        out += i.to_bytes(3, 'big') + (j - i).to_bytes(2, 'big') + dst[i:j]; i = j
    return bytes(out + b'EOF')

def apply_ips(rom, p):
    rom = bytearray(rom); i = 5
    while p[i:i + 3] != b'EOF':
        a = int.from_bytes(p[i:i + 3], 'big'); n = int.from_bytes(p[i + 3:i + 5], 'big'); i += 5
        rom[a:a + n] = p[i:i + n]; i += n
    return rom

def main():
    clean_path, out, ver = sys.argv[1:4]
    clean = open(clean_path, 'rb').read()
    os.makedirs(out, exist_ok=True)
    both_path = os.path.join(out, '_both.bin')
    syms, used, layout = build.build(clean_path, both_path, 'dc')
    both = bytearray(open(both_path, 'rb').read()); os.remove(both_path)
    voice = [(org, org + size) for org, size, name in layout if name.startswith('mdp_')]
    voice += [(a, a + n) for a, n in VOICE_HOOKS]
    isv = lambda i: any(a <= i < b for a, b in voice)

    enh = bytearray(both); vo = bytearray(clean)
    for a, b in voice:
        enh[a:b] = clean[a:b]; vo[a:b] = both[a:b]
    for r in (enh, vo, both): checksum(r)

    names = {
        'enh': 'Xeno Crisis Definitive Edition v%s (Main)' % ver,
        'vo': 'Xeno Crisis Definitive Edition v%s (MD+ Voices only)' % ver,
        'both': 'Xeno Crisis Definitive Edition v%s' % ver,
    }
    for k, r in (('enh', enh), ('vo', vo), ('both', both)):
        open(os.path.join(out, names[k] + '.bin'), 'wb').write(r)
    tag = 'XenoCrisis_DefinitiveEdition_v%s_' % ver
    tag_e = tag + 'Main'; tag_v = tag + 'MDPlus_Voices'
    open(os.path.join(out, tag_e + '.ips'), 'wb').write(ips(clean, enh))
    # voices: IPS without the header checksum, so it applies to the clean ROM or on top of Enhanced
    vp = ips(clean, vo, skip=[(0x18E, 0x190)])
    open(os.path.join(out, tag_v + '.ips'), 'wb').write(vp)
    # checks: both orders give the combined ROM (apart from the header checksum)
    strip = lambda r: bytes(r[:0x18E]) + bytes(r[0x190:])
    assert strip(apply_ips(clean, vp)) == strip(vo)
    assert strip(apply_ips(enh, vp)) == strip(both)
    assert strip(apply_ips(apply_ips(clean, vp), ips(clean, enh))) == strip(both)
    # ship the voice ROMs exactly as the IPS makes them (header checksum left alone)
    vo = apply_ips(clean, vp); both = apply_ips(enh, vp)
    open(os.path.join(out, tag + 'AllInOne.bps'), 'wb').write(mkbps.make(clean, both))
    open(os.path.join(out, names['vo'] + '.bin'), 'wb').write(vo)
    open(os.path.join(out, names['both'] + '.bin'), 'wb').write(both)
    for k, r in (('enh', enh), ('vo', vo), ('both', both)):
        print('%-50s CRC32 %08X' % (names[k], zlib.crc32(r) & 0xFFFFFFFF))
    print('voice bytes:', sum(b - a for a, b in voice), 'in', len(voice), 'ranges')

if __name__ == '__main__':
    main()
