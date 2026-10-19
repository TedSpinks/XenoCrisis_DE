#!/usr/bin/env python3
"""Xeno Crisis Definitive Edition - MD+ voice pack builder.

Builds the CD audio tracks for the MD+ voice feature of the Xeno Crisis Definitive Edition
Mega Drive hack, from YOUR OWN copy of the Neo Geo version (the MAME set sold by
Bitmap Bureau, v1.0.0). No game audio comes with the patch: this script decodes the
Neo Geo sound ROMs on your computer and writes WAV tracks plus a .cue sheet next to
your patched Mega Drive ROM.

Usage:
    python3 xc_voice_extract.py  <Neo Geo zip or folder>  <patched Mega Drive ROM>

Example:
    python3 xc_voice_extract.py XenoCrisis_NG_MAME_v1_0_0.zip "Xeno Crisis Definitive Edition.bin"

This writes "Xeno Crisis Definitive Edition.cue" and "Xeno Crisis Definitive Edition NN.wav" (NN = 01..85)
in the same folder as the ROM. Keep them together and load the ROM as usual.

Needs Python 3.7 or newer. Nothing else (uses numpy automatically if installed,
which just makes it faster).
"""
import argparse, os, struct, sys, wave, zipfile, zlib

# ---------------------------------------------------------------------------
# The Neo Geo files this was written for (MAME set "XenoCrisis_NG_MAME_v1_0_0")
M1_CRC = 0x28C13ED9      # BB01-m1.m1  (Z80 sound driver + sample tables)
V1_CRC = 0x60D57867      # BB01-v1.v1  (ADPCM sample ROM)

RATE_IN = 18518          # 8MHz/432 (ADPCM-A); ADPCM-B entries use delta-N 0x5555 = same rate
RATE_OUT = 44100

# ---------------------------------------------------------------------------
# Track list. The ROM hack plays these by track number, so the order is fixed.
#   ('B', n) = sample table 1 entry n, ADPCM-B
#   ('A', n) = sample table 1 entry n, ADPCM-A
#   ('C', n) = sample table 2 entry n (cutscene narration), ADPCM-A
TRACKS = [
    ('B', 27,  'Intro: music + "Commander Darius..."'),
    ('C', 41,  'Cutscene 1'),
    ('C', 42,  'Cutscene 2'),
    ('C', 43,  'Cutscene 3'),
    ('C', 44,  'Cutscene 4'),
    ('C', 45,  'Cutscene 5'),
    ('C', 46,  'Cutscene 6'),
    ('C', 54,  'Herzog: "Well done on making it this far..."'),
    ('C', 55,  'Herzog: "What did you think of my creations?..."'),
    ('C', 47,  'Herzog: "I see you made use of the elixir..."'),
    ('C', 48,  'Herzog: "The elixir actually contains nanomachines..."'),
    ('C', 49,  'Marine: "You mean... these damned drugs..."'),
    ('C', 50,  'Herzog: "Correct! We needed some prime human specimens..."'),
    ('C', 51,  'Herzog: "So, although you fought well..."'),
    ('C', 52,  'Herzog: "We were hoping you would make use of the elixir..."'),
    ('C', 53,  'Herzog: "It is a mere inconvenience though..."'),
    ('C', 38,  'Ending 1'),
    ('C', 39,  'Ending 2'),
    ('C', 40,  'Ending 3'),
]
VOICE_A = [92, 94, 95, 100, 101, 106, 107] + list(range(133, 172)) + list(range(175, 187))
TRACKS += [('A', n, 'Voice A%03d' % n) for n in VOICE_A]
# added during testing (appended, so earlier track numbers stay the same)
TRACKS += [
    ('C', 3,  'Herzog laughs'),
    ('C', 8,  'Man: "Thank you!"'),
    ('C', 9,  'Man: "Thanks!"'),
    ('C', 11, 'Man: "Hey!"'),
    ('C', 12, 'Man: "Save me!"'),
    ('C', 13, 'Man: "Help!"'),
    ('C', 14, 'Man: "Over here!"'),
    ('C', 16, 'Man: "Hey!" (calling out)'),
]

# ---------------------------------------------------------------------------
STEP = [16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97,
        107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449,
        494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552]
INC = [-1, -1, -1, -1, 2, 5, 7, 9]
JEDI = []
for s in STEP:
    for n in range(16):
        v = (2 * (n & 7) + 1) * s // 8
        JEDI.append(-v if n & 8 else v)

def decode_a(data):
    """YM2610 ADPCM-A: 12-bit accumulator, 4-bit codes, high nibble first."""
    acc = 0; step = 0; out = []
    ap = out.append; jedi = JEDI; inc = INC
    for b in data:
        for n in (b >> 4, b & 15):
            acc = (acc + jedi[step * 16 + n]) & 0xFFF
            ap((acc - 0x1000 if acc & 0x800 else acc) << 4)
            step += inc[n & 7]
            step = 0 if step < 0 else (48 if step > 48 else step)
    return out

BTAB = [57, 57, 57, 57, 77, 102, 128, 153, 57, 57, 57, 57, 77, 102, 128, 153]

def decode_b(data):
    """YM2610 ADPCM-B (delta-T)."""
    acc = 0; d = 127; out = []; ap = out.append
    for b in data:
        for n in (b >> 4, b & 15):
            x = (2 * (n & 7) + 1) * d // 8
            acc = acc - x if n & 8 else acc + x
            acc = -32768 if acc < -32768 else (32767 if acc > 32767 else acc)
            d = d * BTAB[n] // 64
            d = 127 if d < 127 else (24576 if d > 24576 else d)
            ap(acc)
    return out

def resample(pcm, gain):
    """18518 Hz -> 44100 Hz, Catmull-Rom interpolation."""
    n_out = int(len(pcm) * RATE_OUT / RATE_IN)
    try:
        import numpy as np
        x = np.asarray(pcm, dtype=np.float64)
        x = np.concatenate([[x[0]], x, [x[-1], x[-1]]])
        t = np.arange(n_out) * (RATE_IN / RATE_OUT)
        i = np.floor(t).astype(np.int64); f = t - i
        p0, p1, p2, p3 = x[i], x[i + 1], x[i + 2], x[i + 3]
        y = p1 + 0.5 * f * (p2 - p0 + f * (2 * p0 - 5 * p1 + 4 * p2 - p3 + f * (3 * (p1 - p2) + p3 - p0)))
        y = np.clip(np.round(y * gain), -32768, 32767).astype('<i2')
        return np.repeat(y, 2).tobytes()                 # stereo
    except ImportError:
        pass
    x = [pcm[0]] + list(pcm) + [pcm[-1], pcm[-1]]
    ratio = RATE_IN / RATE_OUT
    out = bytearray(n_out * 4)
    pack = struct.pack_into
    for k in range(n_out):
        t = k * ratio; i = int(t); f = t - i
        p0, p1, p2, p3 = x[i], x[i + 1], x[i + 2], x[i + 3]
        y = p1 + 0.5 * f * (p2 - p0 + f * (2 * p0 - 5 * p1 + 4 * p2 - p3 + f * (3 * (p1 - p2) + p3 - p0)))
        y = int(round(y * gain))
        y = -32768 if y < -32768 else (32767 if y > 32767 else y)
        pack('<hh', out, k * 4, y, y)
    return bytes(out)

# ---------------------------------------------------------------------------
def load_neogeo(path):
    want = {'m1': None, 'v1': None}
    def take(name, data):
        low = name.lower()
        for k in want:
            if low.endswith('.' + k) or low.endswith('-' + k) or low.endswith('-%s.bin' % k):
                want[k] = data
    if os.path.isdir(path):
        for fn in os.listdir(path):
            p = os.path.join(path, fn)
            if os.path.isfile(p) and os.path.getsize(p) <= 32 << 20:
                take(fn, open(p, 'rb').read())
    else:
        with zipfile.ZipFile(path) as z:
            for info in z.infolist():
                take(info.filename, z.read(info))
    for k, crc in (('m1', M1_CRC), ('v1', V1_CRC)):
        if want[k] is None:
            sys.exit('Could not find the %s ROM in %s' % (k.upper(), path))
        got = zlib.crc32(want[k]) & 0xFFFFFFFF
        if got != crc:
            sys.exit('The %s ROM is not the expected version (CRC %08X, expected %08X).\n'
                     'This script needs the Neo Geo MAME set v1.0.0.' % (k.upper(), got, crc))
    return want['m1'], want['v1']

def entry(m1, kind, n):
    if kind in 'AB':
        off = 0x1000 + 16 * n
    else:
        off = 0x0FD0 if n == 0 else 0x2000 + 16 * (n - 1)
    start, end = struct.unpack_from('<HH', m1, off + 6)
    return start * 256, (end + 1) * 256

def write_wav(path, frames):
    w = wave.open(path, 'wb')
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(RATE_OUT)
    w.writeframes(frames); w.close()

def main():
    ap = argparse.ArgumentParser(description='Build the MD+ voice tracks for Xeno Crisis Definitive Edition '
                                 'from your own Neo Geo ROM set.')
    ap.add_argument('neogeo', help='Neo Geo MAME set: the .zip, or a folder with its files')
    ap.add_argument('rom', help='your patched Mega Drive ROM (the tracks are named after it)')
    ap.add_argument('--gain', type=float, default=1.0, help='volume multiplier (default 1.0)')
    a = ap.parse_args()

    m1, v1 = load_neogeo(a.neogeo)
    folder = os.path.dirname(os.path.abspath(a.rom))
    base = os.path.splitext(os.path.basename(a.rom))[0]
    cue = ['REM %s - MD+ voice tracks' % base,
           'REM Built by xc_voice_extract.py from your own Neo Geo ROM. Do not share these files.']
    total = 0.0
    for t, (kind, n, label) in enumerate(TRACKS, 1):
        s, e = entry(m1, kind, n)
        pcm = (decode_b if kind == 'B' else decode_a)(v1[s:e])
        frames = resample(pcm, a.gain)
        name = '%s %02d.wav' % (base, t)
        write_wav(os.path.join(folder, name), frames)
        secs = len(frames) / 4 / RATE_OUT; total += secs
        print('%2d  %5.1fs  %s' % (t, secs, label))
        cue += ['FILE "%s" WAVE' % name,
                '  TRACK %02d AUDIO' % t,
                '    REM NOLOOP',
                '    INDEX 01 00:00:00']
    cue_path = os.path.join(folder, base + '.cue')
    open(cue_path, 'w', newline='\r\n').write('\n'.join(cue) + '\n')
    print('\nWrote %d tracks (%.0f seconds) and %s' % (len(TRACKS), total, cue_path))

if __name__ == '__main__':
    main()
