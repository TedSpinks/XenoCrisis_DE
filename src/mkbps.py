"""Minimal BPS patch writer/applier (byte-for-byte, same-size files)."""
import sys, zlib
def enc(n):
    out = bytearray()
    while True:
        x = n & 0x7f; n >>= 7
        if n == 0: out.append(0x80 | x); break
        out.append(x); n -= 1
    return bytes(out)
def dec(b, i):
    data, shift = 0, 1
    while True:
        x = b[i]; i += 1
        data += (x & 0x7f) * shift
        if x & 0x80: return data, i
        shift <<= 7; data += shift
def make(src, dst):
    p = bytearray(b'BPS1') + enc(len(src)) + enc(len(dst)) + enc(0)
    i, n = 0, len(dst)
    while i < n:
        j = i
        if i < len(src) and src[i] == dst[i]:
            while j < n and j < len(src) and src[j] == dst[j]: j += 1
            p += enc(((j - i - 1) << 2) | 0)                    # SourceRead
        else:
            while j < n and not (j < len(src) and src[j] == dst[j] and src[j+1:j+4] == dst[j+1:j+4]): j += 1
            p += enc(((j - i - 1) << 2) | 1) + dst[i:j]         # TargetRead
        i = j
    p += zlib.crc32(src).to_bytes(4, 'little') + zlib.crc32(dst).to_bytes(4, 'little')
    p += zlib.crc32(p).to_bytes(4, 'little')
    return bytes(p)
def apply(src, p):
    assert p[:4] == b'BPS1'
    i = 4; ss, i = dec(p, i); ts, i = dec(p, i); ms, i = dec(p, i); i += ms
    assert zlib.crc32(src) == int.from_bytes(p[-12:-8], 'little'), 'wrong source ROM'
    out = bytearray(); end = len(p) - 12
    while i < end:
        d, i = dec(p, i); cmd, ln = d & 3, (d >> 2) + 1
        if cmd == 0: out += src[len(out):len(out) + ln]
        elif cmd == 1: out += p[i:i + ln]; i += ln
        else: raise ValueError('unsupported')
    assert zlib.crc32(out) == int.from_bytes(p[-8:-4], 'little')
    return bytes(out)
if __name__ == '__main__':
    src = open(sys.argv[1], 'rb').read(); dst = open(sys.argv[2], 'rb').read()
    p = make(src, dst); open(sys.argv[3], 'wb').write(p)
    assert apply(src, p) == dst
    print('ok', sys.argv[3], len(p), 'bytes')
