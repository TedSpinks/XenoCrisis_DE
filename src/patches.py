"""Hooks into the original game code: (address, expected original bytes, new bytes).
{symbol} placeholders are replaced with 8-hex-digit addresses from the assembled code."""

import os
def PATCHES(variant):
    off = set(os.environ.get('XC_DISABLE', '').split(','))
    p = PATCHES_ALL(variant)
    keep = []
    for a, e, n in p:
        tag = {0x262A: 'roll', 0x2EE0: 'roll', 0x3168A: 'pause', 0x0F3A: 'dispatch',
               0x37B68: 'attract', 0x3817A: 'attract', 0x0730: 'init', 0x1062: 'init', 0x372FC: 'menu', 0x372DE: 'menu', 0x37A2E: 'menu', 0x378C8: 'menu'}.get(a)
        if tag not in off: keep.append((a, e, n))
    return keep

def PATCHES_ALL(variant):
    p = [
        # roll priority: d-pad handler's "fire held? skip roll check" -> our hook
        (0x262A, '4A6F004667004CD2', '4EF9{roll_hook}4E71'),
        # pause HUD: gameplay loop's vsync call -> our routine (calls vsync first)
        (0x3168A, '4EB9000519E6', '4EB9{pause_hud}'),
    ]
    p += [
        # screen dispatcher: call screens through our wrapper (high score table hooks)
        (0x0F3A, '207208004E90', '4EB9{my_dispatch}'),
        # title loop vsync -> idle counter for the attract table (two copies of the lea)
        (0x37B68, '47F9000519E6', '47F9{title_vsync}'),
        (0x3817A, '47F9000519E6', '47F9{title_vsync}'),
        # boot: "high score = 68000" -> load table (save RAM or defaults); skip the other 2 copies
        (0x0730, '23FC000109A000FF0FBC', '4EB9{hs_init}6016'),     # PAL path
        (0x1062, '23FC000109A000FF0FBC', '4EB9{hs_init}6016'),     # NTSC path
    ]
    p += [
        # during a roll: "fire held? cancel the roll" -> roll mode check
        (0x2EE0, '4A6F0046670012E8', '4EF9{roll_cancel}4E71'),
        # options screen: ROLL CANCEL and HIGH SCORES items
        (0x372FC, '303900FF4FB4', '4EB9{opt_draw}'),           # init: draw it
        (0x372DE, '48780011', '48780015'),                     # init: BACK two rows lower
        (0x3729E, '4878000D', '4878000F'),                     # init: CONTROLS one row lower (row 15)
        (0x372BC, '4878000F', '4878000D'),                     # init: LANGUAGE above it (row 13)
        (0x373AA, '303900FF10BA', '4EB9{opt_reent}'),          # init, from a sub-screen: cursor row
        # Options > AUDIO with MD+: two added items (aud_menu)
        (0x2DBBC, '303900FF4FB4', '4EB9{aud_draw}'),
        (0x2DDBE, '0801000067000726', '4EF9{aud_in}4E71'),
        (0x2E240, 'D24106410009', '4EB9{aud_row1}'),
        (0x2DEDE, 'D04006400009', '4EB9{aud_row0}'),
        (0x2DF4E, 'D04006400009', '4EB9{aud_row0}'),
        (0x2E030, 'D04006400009', '4EB9{aud_row0}'),
        (0x2E0CE, 'D04006400009', '4EB9{aud_row0}'),
        (0x2E1B0, 'D04006400009', '4EB9{aud_row0}'),
        (0x2E322, 'D04006400009', '4EB9{aud_row0}'),
        (0x2E3CE, 'D04006400009', '4EB9{aud_row0}'),
        (0x2E6CE, 'D04006400009', '4EB9{aud_row0}'),
        (0x2E850, 'D04006400009', '4EB9{aud_row0}'),
        (0x2E8FC, 'D04006400009', '4EB9{aud_row0}'),
        (0x2E95A, 'D04006400009', '4EB9{aud_row0}'),
        (0x2E9F8, 'D04006400009', '4EB9{aud_row0}'),
        (0x2EA4C, 'D04006400009', '4EB9{aud_row0}'),
        (0x2DDDA, 'E94C064400C7', '4EB9{aud_cy4}'),
        (0x2E482, 'E94C064400C7', '4EB9{aud_cy4}'),
        (0x2E4D6, 'E94C064400C7', '4EB9{aud_cy4}'),
        (0x37A2E, '0C430003', '0C430005'),                     # cursor: two more items
        (0x378C8, '024000C06786', '4EF9{opt_confirm}'),        # A/START handling
    ]
    # per-player scores: gameplay object loop (who damaged which enemy) and every score add
    p.append((0x31FE2, '2F024E90588F', '4EB9{obj_wrap}'))
    # MD+ voice
    p += [
        (0x0470, '207900FF4F4E4E90', '4EB9{mdp_vint}4E71'),    # VBlank: game's handler, then voices
        (0x288C6, '4EF90003E530', '4EF9{mdp_intro_mus}'),     # intro music (the CD track has it)
        (0x1B92E, '707946004878', '4EF9{mdp_mres}'),          # rescued man: our line instead
        (0x1B6EE, '487800032F00', '4EF9{mdp_fres}'),          # rescued woman: our line instead
        (0x1249E, '1E3900FF35DC', '4EB9{mdp_rtrap}'),         # room formations: their lines
        (0x12930, '1E3900FF35DC', '4EB9{mdp_ramb}'),
        (0x128D8, '4EB90000EE92', '4EB9{mdp_rhorde}'),
        (0x13534, '103900FF3304', '4EB9{mdp_rdanger}'),
    ]
    p += [
        # Area Clear: each player's own score (the text call), P1 / P2 rank columns apart
        (0x8D606, '48E7383C2A6F0020', '4EF9{ac_text}4E71'),
        (0x33FA2, '4878006C', '48780058'),      # P1 rank x 108 -> 88 (centred on x 100)
        (0x34044, '487800BC', '487800D0'),      # P2 rank x 188 -> 208 (centred on x 220)
        (0x33F84, '06440044', '06440030'),      # 2 players: both ranks a line higher (no RANK line)
        (0x32506, '7E682D47FF7A3A7C006872542D41FF763D7C0054FF74767A347C007A7A667466784A2D44FF9C7C38367C0038307C0010',
                  '7E702D47FF7A3A7C0070725C2D41FF763D7C005CFF74767A347C00827A6E746E78522D44FF9C7C40367C0040307C0018'),   # 2 players: the result screen's rows at the same heights as 1 player (were 8 higher; d3, the P1/P2 labels' y, stays: ac_p1/ac_p2 place them)
    ]
    p += [
        (0x1B6FC, '067903E800FF35DE', '4EB9{score_u}03E8'),
        (0x1B808, '067903E800FF35DE', '4EB9{score_u}03E8'),
        (0x1B98A, '067903E800FF35DE', '4EB9{score_u}03E8'),
        (0x41EDE, '0679009600FF35DE', '4EB9{score_u}0096'),
        (0x4370C, '067900C800FF35DE', '4EB9{score_u}00C8'),
        (0x43C9C, '067901C200FF35DE', '4EB9{score_u}01C2'),
        (0x44946, '0679012C00FF35DE', '4EB9{score_u}012C'),
        (0x44B48, '067901F400FF35DE', '4EB9{score_u}01F4'),
        (0x44FD0, '067902EE00FF35DE', '4EB9{score_u}02EE'),
        (0x45534, '067905DC00FF35DE', '4EB9{score_u}05DC'),
        (0x45DE8, '067902BC00FF35DE', '4EB9{score_u}02BC'),
        (0x465AA, '0679006400FF35DE', '4EB9{score_u}0064'),
        (0x54458, '0679012C00FF35DE', '4EB9{score_u}012C'),
        (0x5479C, '0679012C00FF35DE', '4EB9{score_u}012C'),
        (0x54CCC, '0679019000FF35DE', '4EB9{score_u}0190'),
        (0x54E04, '0679025800FF35DE', '4EB9{score_u}0258'),
        (0x5586A, '0679006400FF35DE', '4EB9{score_u}0064'),
        (0x55BB6, '0679006400FF35DE', '4EB9{score_u}0064'),
        (0x561B8, '067901C200FF35DE', '4EB9{score_u}01C2'),
        (0x56746, '0679019000FF35DE', '4EB9{score_u}0190'),
        (0x5694C, '067901F400FF35DE', '4EB9{score_u}01F4'),
        (0x58C3A, '067902EE00FF35DE', '4EB9{score_u}02EE'),
        (0x5919C, '067902EE00FF35DE', '4EB9{score_u}02EE'),
        (0x59D80, '0679019000FF35DE', '4EB9{score_u}0190'),
        (0x5A044, '0679025800FF35DE', '4EB9{score_u}0258'),
        (0x7B002, '0679032000FF35DE', '4EB9{score_u}0320'),
        (0x7B56E, '067904B000FF35DE', '4EB9{score_u}04B0'),
        (0x7BA64, '0679032000FF35DE', '4EB9{score_u}0320'),
        (0x7BDBC, '067903B600FF35DE', '4EB9{score_u}03B6'),
        (0x7C25C, '067900C800FF35DE', '4EB9{score_u}00C8'),
        (0x7C766, '067900C800FF35DE', '4EB9{score_u}00C8'),
        (0x7CB92, '0679015E00FF35DE', '4EB9{score_u}015E'),
        (0x7CC24, '067900FA00FF35DE', '4EB9{score_u}00FA'),
        (0x7FB56, '0679028A00FF35DE', '4EB9{score_u}028A'),
        (0x80288, '067903E800FF35DE', '4EB9{score_u}03E8'),
        (0x807A4, '0679003200FF35DE', '4EB9{score_u}0032'),
        (0x80C02, '067900FA00FF35DE', '4EB9{score_u}00FA'),
        (0x872FE, '0679006400FF35DE', '4EB9{score_u}0064'),
        (0x4B664, '0679001400FF36E6', '4EB9{score_k}0014'),
        (0x4D694, '0679000A00FF36E6', '4EB9{score_k}000A'),
        (0x5D1FE, '0679002800FF36E6', '4EB9{score_k}0028'),
        (0x5FC46, '0679001E00FF36E6', '4EB9{score_k}001E'),
        (0x6446E, '0679003200FF36E6', '4EB9{score_k}0032'),
        (0x65562, '0679006400FF36E6', '4EB9{score_k}0064'),
    ]
    return p

def _sram_header(rom, syms):
    # battery save RAM: odd bytes $200001-$203FFF
    rom[0x1B0:0x1BC] = b'RA' + bytes([0xF8, 0x20]) + (0x200001).to_bytes(4, 'big') + (0x203FFF).to_bytes(4, 'big')

POST = [_sram_header]
