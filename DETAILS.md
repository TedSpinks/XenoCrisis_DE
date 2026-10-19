# Xeno Crisis: Definitive Edition: the details

Everything the [README](README.md) leaves out: exact behaviour, controls, voice lines, checksums and building from source.

## Contents

- [Patched ROM checksums](#patched-rom-checksums)
- [Cancel rules](#cancel-rules)
- [Pause screen](#pause-screen)
- [Area Clear](#area-clear)
- [High score tables](#high-score-tables)
- [Options and saving](#options-and-saving)
- [MD+ voices](#md-voices)
- [Notes](#notes)
- [Building from source](#building-from-source)
- [Version history](#version-history)

## Patched ROM checksums

All patches go on the Mega Drive / Genesis ROM v1.0.0:

| | |
|---|---|
| Size | 4,194,304 bytes (4 MB) |
| CRC32 | `AC5F4CCA` |
| MD5 | `50cca5273cdb6d6df36cbd29dbd3ff7f` |
| SHA-1 | `0b9b100b0140c76a9ecaf96fd3031a8002aeea60` |

The CRC32 of the patched ROM:

| Patch | Alone | + MD+ Voices |
|---|---|---|
| All-in-one | `03EA138B` | (already included) |
| Main | `B809E428` | `03EA138B` (same as All-in-one) |
| MD+ Voices | `17BCBB69` | |
| Controls (Dreamcast) | `8CB96665` | `375A91C6` |
| Controls (Modern) | `D24D2877` | `69AEDFD4` |

The MD+ Voices patch leaves the ROM header checksum alone, which is what lets it go on top of the other patches in either order. The game doesn't check it.

## Cancel rules

Options > CANCEL RULES. Change it with Left / Right, A or START.

| Rule | Behaviour |
|---|---|
| **MODERN** (default) | Like the Switch / Steam versions. Pressing roll while firing starts a full roll, no shots are fired during it, and firing resumes by itself when the roll ends. A *fresh* press of fire cancels a roll (fire already held when you rolled doesn't). |
| **DREAMCAST** | Like the Dreamcast version: as MODERN, but only pressing roll again cancels a roll. |
| **MD/GENESIS** | The original behaviour: holding fire blocks the roll, and firing mid-roll cuts it short. |

As in the original, a roll can't be cancelled during its first few frames. The Controls-only patches have DREAMCAST or MODERN locked in, with no Options item.

## Pause screen

- **Sides:** each player's stats, player 1 on the left and player 2 on the right in a 2-player game. These are health, the current weapon icon (with ammo for the default gun, or the seconds left for a special weapon), grenades and dog tags.
- **Top**, as on the Neo Geo: player 1's score on the left, the high score in the middle, player 2's score on the right.
- **Bottom left:** the difficulty (EASY or HARD), opposite the game's seed.

The Controls-only patches show the side stats only.

## Area Clear

- Each player's own score appears under their rank (with 2 players, P1 on the left and P2 on the right), in place of the combined SCORE and HIGH SCORE.
- NEW HIGH SCORE appears under the score when it beats the top of the table for the difficulty. In a 2-player game it goes under the leading player's score.
- With 2 players, "P1 RANK" / "P2 RANK" replace the single RANK line, and the rows sit at the same heights as with 1 player.

## High score tables

**Where they show:** the tables are shown over the title screen artwork like the Neo Geo version: green for EASY, red for HARD. A game goes on the table for the difficulty it was started on, and the game's built-in high score always matches the top of the table for the difficulty that's set.

**Stage column, the fine print:**
- The room number is rooms cleared + 1, so 3-5 means the player had cleared 4 rooms in area 3. Revisiting a cleared room doesn't count again.
- 7-B covers both ways the final encounter can end a credit: Dr. Herzog stopping a game that used a continue, or dying to his final form.
- In a 2-player game, each player enters their own best credit. A player only gets 7-★ if they were still in the game when the credits rolled.

**Entering initials:** when a game ends with a score that makes the table, after game over or after finishing the game, the table appears with the new row highlighted. In a 2-player game player 1 enters first with pad 1, then player 2 with pad 2.

| Button | Action |
|---|---|
| Up / Down | choose a character: A-Z, ← (back), ✓ (end) |
| A / B / C | confirm the character and move to the next |
| START | finish |

There's a 30-second time limit.

**Viewing and resetting:**
- After 20 seconds of idling on the title screen, the EASY and then the HARD table are shown. START, A, B or C goes back to the title.
- Options > HIGH SCORES shows the tables any time, starting with the one for the difficulty that's set. Left / Right switches between them (the arrow at the top shows which way the other one is), and START, A, B or C goes back.
- **To reset the table you're looking at, hold A + B + C + START together.** A sound plays and the table redraws with the defaults.

## Options and saving

- **Saved when you leave Options:** difficulty, music and sounds on/off, controller layouts, language, cancel rules, and cutscene voices.
- **Controller layouts:** a saved layout is only restored for the same type of pad (3- or 6-button). With a different pad, you get the game's default layout for that pad.
- **Translations:** the new Options items (CANCEL RULES, HIGH SCORES, MODERN) are translated into all of the game's languages. The high score tables are in English.
- **Save RAM:** the patch adds standard battery-backed save RAM to the cartridge header. Emulators store it automatically (RetroArch uses a `.srm` file), as do flash carts and FPGA systems with Mega Drive save support. On hardware without save RAM, such as a reproduction cartridge with no save chip, everything still works (through soft resets too) but only lasts until power-off.

## MD+ voices

### Requirements

- The Neo Geo MAME ROM set v1.0.0 (`XenoCrisis_NG_MAME_v1_0_0.zip`, inside Bitmap Bureau's download). The script also accepts a folder with its files.
- Python 3.7 or newer. No extra packages are needed.
- MD+: Genesis Plus GX (RetroArch), or a flash cart with MD+ support.

**Voices follow the Options SOUNDS setting.** With sounds off, there are no voices. The intro narration also needs MUSIC on.

### Options > AUDIO

With MD+ present, two items are added (main patch + voices):

| Item | What it does |
|---|---|
| CUTSCENE VOICES | **ALL:** the intro and all story narration. **INTRO:** only the Neo Geo intro (music and narration). **NONE:** no narration, and the intro has the Mega Drive music. Saved with the other options. With the Voices patch alone, it's always ALL. |
| CD VOICE | Left / Right picks a voice track (number and name), A or START plays it. Handy for checking your tracks. |

### What speaks when

| When | Lines |
|---|---|
| Intro | The Neo Geo intro: its music and narration replace the Mega Drive intro music |
| Marine select, shop | "Make your selection" |
| Drop-off | "Commencing operations" as the ship takes off |
| First room of each area | Halfway through the area name. 1: "Your mission begins now", 2: "Looks like you're in for a fight", 3: "They're below the surface", 4: "What happened here?", 5 and 6: "Stay alert", 7: "Good luck" |
| New rooms | As on the Neo Geo, a line as the fighting starts. When the enemies come in a special formation, its line: "There are so many of them!" (a crowd), "Danger!" (a pair of big ones), "An ambush?" or "It's a trap!". Otherwise, every 1-4 rooms, one of "Here they come", "Watch out", "The enemy!", "Stay alert", "Be careful", "Watch your back" or "Over there!" |
| Humans in a room | "Rescue the humans". Each waiting human also calls out, as on the Neo Geo: first 1-5 s after appearing, then every 5-22 s until reached. Men: "Hey!", "Save me!", "Help!" or "Over here!". Women: "Over here!", "Help!", "Hey!", "Quickly!", "Save me!" or "Hurry up!" |
| Bodies in a room | "What happened here?" |
| Hostage rescued | When you reach them, with the Neo Geo's odds. Men: "Yeah!", "Thank you!" or "Thanks!". Women: "Thanks!", "I'm outta here" or "Thank you". These replace the game's own samples. Hostages collected automatically when a room is cleared say nothing, as on both versions. |
| Weapon pickups | The weapon's name: "Flamethrower", "Rocket launcher", "Spread shot", "Homing", "Laser", "Rebound shot", "Shotgun", "Vulkan", "BFG" |
| Boss rooms | As the boss's name appears. 1: "Look at the size of that thing!", 2: "Keep your cool", 4: "What a monster!", 5: "What is it?", 6: "This doesn't look good", 7: Dr. Herzog laughs as you reach him, then "What is this?" as the final boss transforms. Area 3 has no boss. |
| Continue | "Continue?" (only when the game offers a continue) |
| Story scenes | As on the Neo Geo, each page's narration starts with its first typed character: the scenes between areas, Dr. Herzog's scene and the ending. Moving on to the next page early cuts it short. |

**When two lines overlap:**
- Room and screen lines (first-room lines, "Rescue the humans", the room's own line, boss lines) are never cut off, and cut in on anything else.
- Rescue lines and weapon names wait their turn. One can wait while another line plays. Any more are dropped, and a line that has waited over 2 seconds is dropped too.
- Waiting hostages only call out when nothing else is playing.

The game's own voice samples ("Xeno Crisis", "Room clear", "Area clear" and "Game over") are left as they are, so those lines aren't doubled. Not voiced: "You!" and "Stop!" (the Mega Drive has its own soldier shouts).

## Notes

- Tested in the Genesis Plus GX emulator core, including its MegaSD emulation. Not yet tested on real hardware or flash carts.
- A finished game is detected when the ending's credits appear during the game. That's been tested from the cheat menu's CREDITS item with the game state set up as a win, not from a real win against the final boss.
- "It's a trap!" goes with a ring of enemies around the player. The game only uses it in rooms with a particular layout, so it may be very rare (on the Neo Geo too).
- The new code lives in unused padding inside the ROM (no size change), and the game's own code is only changed at a handful of hook points.

## Building from source

You only need this if you want to change the hack. You'll need:

- Python 3
- [vasm](http://sun.hasenbraten.de/vasm/), built for 68000 with Motorola syntax, as `src/vasmm68k_mot`
- the clean Mega Drive / Genesis ROM (v1.0.0, CRC32 `AC5F4CCA`)

```
python3 src/make_release.py "Xeno Crisis.bin" out 1.0     # Main, MD+ Voices and All-in-one
python3 src/build_controls.py "Xeno Crisis.bin" out 1.0   # Controls-only patches
```

The main code is `src/xc.s`, and the controls-only code is `src/hack.s`. Technical notes on the MD+ voice feature are in [docs/MDPLUS.md](docs/MDPLUS.md).

This repository contains no ROMs or game audio. The patches contain only new code, and the voice script only converts files you already own.

## Version history

**v1.0:** first public release.
