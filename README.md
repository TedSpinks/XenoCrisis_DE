# Xeno Crisis: Definitive Edition!

**A Mega Drive / Genesis ROM hack that brings together the best features of Xeno Crisis's later ports, and adds arcade-style high score tables for both difficulties.**

- **Roll while firing!** Pick your roll and fire cancel rules: Modern, Dreamcast, or the original MD/Genesis behaviour.
- **The missing HUD!** Pausing shows all the stats the widescreen versions keep at the sides of the screen, plus both players' scores, the high score, and the difficulty.
- **Arcade scoring!** Every version but one combines both players into a single score. The Neo Geo version started to fix that; this hack finishes the job.
- **High score tables for Easy and Hard,** with initials entry and how far each credit got, saved to SRAM.
- **ALL the voice clips and story narration** played as CD audio over MD+. This not only adds all the voice samples from the modern versions, but also narration for all the cutscenes, which AFAIK was unique to the Neo Geo. You'll want to purchase the [Neo Geo ROM](https://shop.bitmapbureau.com/products/xeno-crisis-neo-geo-aes-mvs-rom-download) to rip the voice clips.

## Roll and fire cancel rules

Every version of Xeno Crisis lets you cancel a roll by pressing roll a second time. The Dreamcast version changed how roll and fire interact, for its Twin Stick peripheral: roll takes priority over shooting, so you get a full roll even while holding fire. The modern console versions kept that, and also let a fresh press of fire cancel a roll. Options > CANCEL RULES lets you pick **MODERN** (the default), **DREAMCAST**, or the original **MD/GENESIS** behaviour.

I find that with MODERN rules, I sometimes cancel a roll when I don't mean to (by changing fire directions), so I actually prefer DREAMCAST rules.

## Arcade scoring

As far as I know, every version of Xeno Crisis combines both players into one score, except the Neo Geo version. It adds a high score table and gives each player their own score: kills go to whoever last damaged the enemy, pickups go to the nearer player, and boss bonuses go to everyone still standing. This hack uses the same scoring logic, taken straight from the Neo Geo version. But the Neo Geo version keeps adding to your score after you continue. High score blasphemy! Here, like most arcade games, continuing starts your score again from zero, so every score on the table was earned on a single credit.

## High score tables

The Neo Geo version is the only one with a high score table, so this hack takes it and levels it up: two Top 10 tables, one each for Easy and Hard like modern indie games, with every entry showing the stage it reached. Because a continue resets your score, each run is split into credits. You can't enter initials when you continue, so at the end of your run you enter them for your best-scoring credit, and its stage column shows where that credit ended, for example:

| Stage | Where the credit ended |
|---|---|
| 3-5 | in area 3, on its 5th room |
| 3-B | in area 3, in the boss fight |
| 7-B | in the final boss fight |
| 7-★ | in the final boss fight, then the player continued and beat the game |
| 1CC | beat the game on a single credit |

Both tables start out with the Neo Geo version's default initials and scores. If you don't enter any initials, your entry is saved as 68K, a nod to the original default high score of 68,000, itself a reference to the Mega Drive's Motorola 68000 CPU. Runs with cheats on (from the hidden CHEAT MENU) or in the hidden Infinite Mode and Boss Rush modes don't enter the tables.

The tables and your options are saved to SRAM, so they're kept in emulators and on flash carts with save support.

## Neo Geo voices (MD+)

The Neo Geo version's voice clips and story narration play as CD audio through MD+. That works in Genesis Plus GX (RetroArch) and on MegaSD-compatible flash carts (but I haven't tested this!). You'll hear room entry lines, hostages calling for help and thanking you, weapon names, boss lines, and the narrated intro, story cutscenes and ending, all following the same playback logic as the Neo Geo ROM. The MD/Genesis music and sound effects play as normal underneath. No game audio is distributed: a Python script extracts the voices from your own copy of the Neo Geo ROM set.

There are also new Options > AUDIO menu items allowing you to play the CD VOICE tracks and choose which cutscene voices you want to hear: ALL (like the Neo Geo), INTRO only (like the other modern consoles), or NONE (like the MD/Genesis).

## Quality of life

- Pausing shows each player's health, weapon and ammo, grenades and dog tags (all the stats the widescreen versions keep at the sides of the screen), plus both players' scores, the high score, and the difficulty.
- Area Clear has a new layout with room for both players' scores, and shows NEW HIGH SCORE once you've beaten the high score.
- The Options screen now includes the new control and audio settings, and remembers all your settings in SRAM, including the language, so the language select at power-on is skipped once it's set.

## Patching

Start from the [Mega Drive / Genesis ROM](https://shop.bitmapbureau.com/products/xeno-crisis-sega-mega-drive-genesis-rom-download), v1.0.0 (CRC32 `AC5F4CCA`). Use a patcher such as Floating IPS or [RomPatcher.js](https://www.marcrobledo.com/RomPatcher.js/). The all-in-one patch is a .bps, which checks that you have the right ROM before patching.

**Pick one** (the files are named `XenoCrisis_DefinitiveEdition_v1.0_...`):

- **All-in-one** (`AllInOne.bps`): everything, including the voice support. Why *wouldn't* you want this one!??
- **2 separate patches:** the main patch (`Main.ips`: controls, scoring, tables, options) and the MD+ Voices patch (`MDPlus_Voices.ips`). Use either on its own, or both, applied in either order. Both together give exactly the same ROM as the all-in-one patch.
- **Controls + Pause only** (`Controls_Dreamcast.ips` or `Controls_Modern.ips`): just the roll fix with one rule set locked in (no menu), plus the pause stats (health, weapon and ammo, grenades, dog tags). The game's original scoring is untouched. These can also be combined with the MD+ Voices patch.

The voice support does nothing until you add the voice tracks, so the all-in-one ROM plays fine without them.

**Getting the voices (MD+):**

1. You'll need your own copy of the [Neo Geo version](https://shop.bitmapbureau.com/products/xeno-crisis-neo-geo-aes-mvs-rom-download) from Bitmap Bureau's shop. Its download is a zip with every format; the script uses the MAME ROM set inside it, `XenoCrisis_NG_MAME_v1_0_0.zip`. You'll also need Python 3.7 or newer; no extra packages are required.
2. Run the script with the Neo Geo zip and your patched ROM:
   ```
   python3 xc_voice_extract.py XenoCrisis_NG_MAME_v1_0_0.zip "Xeno Crisis Definitive Edition.bin"
   ```
3. It writes a `.cue` file and 85 `.wav` tracks (about 48 MB) next to the ROM, named after it. Keep them together. If you rename the ROM, run the script again.
4. In Genesis Plus GX (RetroArch), load the ROM as usual. With the core option "CD add-on (MD mode)" on Auto (or MegaSD), the voices play. Restart the content after changing that option. RetroArch's "CD-DA volume" option sets the voice volume.

For the patched ROM checksums, exact controls, every voice line and more, see [DETAILS.md](DETAILS.md).

## Support the developers

Xeno Crisis is made by Bitmap Bureau, and this hack only exists because it's a great game. If you enjoy it, buy it (both versions!) and support our awesome retro developers. Please keep the generated voice files to yourself, and point friends to the shop instead.

This is an unofficial fan project, not affiliated with or endorsed by Bitmap Bureau.