# Xeno Crisis Enhanced: MD+ voices (technical notes)

These notes describe the optional MD+ voice feature added in v1.4 beta 1. MD+ means CD audio through the MegaSD interface; Genesis Plus GX emulates it as the "CD add-on (MD mode)" MegaSD option.

## Design

- The Mega Drive chiptunes and sound effects are unchanged. The Neo Geo voice clips play as CD audio tracks on top of them.
- No game audio ships with the patch. `xc_voice_extract.py` decodes each player's own Neo Geo MAME set (v1.0.0, checked by CRC: m1 `28C13ED9`, v1 `60D57867`). It writes 77 tracks as 44.1 kHz stereo WAV files, plus a `.cue` named after the ROM.
- Every track in the `.cue` carries `REM NOLOOP`. That keyword lets Genesis Plus GX switch on MegaSD emulation automatically.
- All MD+ I/O happens in VBlank. The code patches `$470`, replacing the VBlank handler's `movea.l $FF4F4E,a0 / jsr (a0)` with `jsr mdp_vint`.
- Event detection polls game state each frame instead of hooking each event. Only one other game hook is needed:
  - `$288C6`: the intro's `jmp $3E530` (music `$10`). With MD+, it stops the Mega Drive music instead, by writing `$80` to Z80 `$A00100` and `0` to `$A00113`.
- While the interface is open (`$CD54` written to `$3F7FA`), the overlay hides ROM `$3F7F6`-`$3FFFF`. All MD+ code and data is therefore in `LOW` blocks.
- Detection: `mdp_init` (called from `hs_init`, with interrupts masked) writes `$CD54` and reads it back. A plain cartridge reads its own ROM there (`$0004`).
- Commands used:
  - `$11nn`: play track nn once.
  - `$1300`: stop (at boot or reset).
  - `$1308`: stop with a short fade (used when leaving a story screen).
- Priorities:

  | Level | Plays | Used for |
  |---|---|---|
  | `P_CHAT` | only when nothing else is playing | room clear |
  | `P_EVENT` | replaces chatter and other events | screen and substate events |
  | `P_STORY` | always | narration |

  The busy time comes from a per-track length table (8-frame units).
- Voices follow the SFX option (`$FF4720`). The intro track also needs music on (`$FF471C`).

## Game state used

| RAM | Meaning |
|---|---|
| `$FF01B4` | screen (see below) |
| `$FF3410` | screen substate |
| `$FF3304` | current area, 0-6 |
| `$FF045D` / `$FF045E` / `$FF0472` | story text: line being typed / page / character. A page starts when line = 0 and char = 0 |
| `$FF000C` and others | checked at `$29632`: a continue or cheat was used, which selects Herzog's "elixir" pages 2-6 instead of 7-8 |

Screens:

| Screen | Purpose |
|---|---|
| 1 | continue |
| 2 | boot language select |
| 3 | intro (4 auto pages) |
| 4 | story after areas 1-6 (one page, waits for a button) |
| 5 | Dr. Herzog's scene in the final area (pages 0-8) |
| 6 | ending (pages 0-2, then a logo page) |
| 7 | title |
| 14 | marine select |
| 15 | area intro (area 1: drop-off ship) |
| 16 | gameplay |
| 17 | shop |
| 18 | credits |

Gameplay substates (screen 16):

| Substate | Meaning |
|---|---|
| 0 | fighting |
| 1 | area name banner |
| 2 | entering a room |
| 3 | room clear (exits open). 0→3 = just cleared; 4→3 = walked into a cleared room |
| 4 | room scroll |
| 5 | game over |
| 7 | boss room camera |
| 8 | boss intro |
| 9 | area clear |

Screen 15 substates: 1 = ship lands, 4 = ship has left with the marines on the ground, 7 = fade.

## Track list (fixed order)

| Track | Content |
|---|---|
| 1 | Intro: Neo Geo table 1 entry 27 (ADPCM-B), music plus narration |
| 2-7 | cutscenes 1-6 (table 2 entries C041-C046) |
| 8-16 | Herzog pages 0-8: C054, C055, C047, C048, C049, C050, C051, C052, C053 |
| 17-19 | ending pages 0-2: C038-C040 |
| 20-77 | table 1 voice clips: A092, A094, A095, A100, A101, A106, A107, A133-A171, A175-A186 |

Neo Geo M1 sample tables:
- Table 1 is at `$1000`, 16-byte entries. Table 2 is at `$2000`; entry C000 is the one at `$0FD0`.
- Start and end are little-endian words at bytes 6 and 8, in 256-byte units.
- All clips play at 18518 Hz.

## Packaging

Voices ship as a separate patch, "MD+ Voices", so players can use it alone or with Enhanced.

- `make_release.py` builds Enhanced and Voices together in one layout, then splits them by the `mdp_*` blocks and the two hooks. Neither patch overlaps the other.
- The Voices patch is an IPS that leaves out the header checksum, so it applies to the clean ROM or on top of Enhanced, in either order. The game doesn't check the checksum.
- Enhanced doesn't call any voice code. Voices finds the MegaSD interface by itself:
  - on the first VBlank, guarded by a `'MDP+'` magic value at VARS+$30C;
  - again whenever the screen returns to 0, i.e. after a reset.
- Voice RAM is VARS+$300 to $30F (`$FFFB10`). It's free in both the clean and Enhanced game.

## Event to clip (Voices v1.0 beta 5)

Not voiced, because the Mega Drive already has its own PCM samples for these (`AREA_CLEARED`, `GAME_OVER`, `M_HOSTAGE_SAVED`, `ROOM_CLEARED`, `XENO_CRISIS`):
- the title ("Xeno Crisis")
- room clear
- area clear
- game over
- a rescued man

| Event | Detection | Clip |
|---|---|---|
| Intro | screen 3 entry | track 1 |
| Marine select / shop | screen 14 / 17 entry | A152 |
| Drop-off | screen 15, substate 4, area 0 | A137 |
| First room of each area | substate 1→2 (after the area-name banner) | A153, A141, A135, A169, A164, A164, A144 |
| New room | substate 4→2 | see "Room lines" below (beta 9) |
| Humans in a room | for 240 frames from substate 2, any `$FF2C8C` entity with handler `$2A` = `$1B5DC` | A157 / A158 |
| Bodies in a room | same scan, no humans: an entity with handler `$526C0`, the do-nothing routine left by `$53172` (the corpse setup, which randomly picks 4 corpse graphics) | A169; skipped where the first-room line was already A169 (area 4) |
| Woman rescued | object type `$7C` (`$7B` = man) with `OBJBASE+$15` bit 2 set; once per object per room (`MDP_RMASK`) | A178, A095, A177 in turn |
| Weapon pickup | stats `+$0D` (seconds left) rises by more than 1 | by stats `+$08`, weapons 1-9: A142, A159, A163, A147, A150, A156, A161, A166, A136 |
| Boss room | substate 7, then a 62-frame delay (`MDP_DLY`), when "AREA n BOSS" appears | A151, A149, none (area 3 has no boss), A154, A170, A140, none |
| Area 7 transformation | substate 6 | A171 |
| Continue | screen 1 entry, only when the game offers a continue (its own test at `$1AF12`: no special mode `$FF36E0`, continues left `$FF46FD`, and saved play state `$FF0012` ≠ 10, which is Dr. Herzog ending a game that used a continue) | A138 |
| Story pages | screens 4-6, at the first typed character of each page (line 0, char ≠ 0) | tracks 2-19 |

How the weapon numbers were found: firing each weapon type plays fire sound id = name record + 64. Those ids decode to:

| Type | Weapon |
|---|---|
| 0 | rifle |
| 1 | flame |
| 2 | rocket |
| 3 | spread |
| 4 | homing |
| 5 | laser |
| 6 | rebound |
| 7 | shotgun |
| 8 | vulcan |
| 9 | BFG |

The Neo Geo starts each story page's narration at that page's first typed character. Its screen-4 loop calls the voice helper `$58C7C` with id `$111` + page when the line and character are both 0 at a typing tick (`$7BBA4`).

Build note: `build.py` places the Enhanced blocks before the `mdp_*` ones, so changing Voices never moves Enhanced.

Still to do: Dr. Herzog's laugh, which plays before his scene; the clip hasn't been identified yet.

## Room lines (Voices v1.0 beta 9)

How the Neo Geo picks them:
- Its gameplay substate 2 (entering a room) runs a per-frame table at `$7681E`. Frame 50, `$78656`, plays the room's line, then starts the fight.
- Order of choice:
  1. `$107E6C`, if the spawn code set it for this room's enemy formation.
  2. Else `$107EA6` (humans waiting): A157 or A158 at random.
  3. Else chatter. The countdown `$107E6E` is set to 2-5 after the area's first-room line (`$7AD3E`). Each such room counts it down; at 0 it plays `rand & 7` from A145, A146, A167, A165, A164, A134, A168, A155 and is reset to 1-4. There are no per-area pools.
- First-room lines come from the table at `$C03D6`; boss lines from `$C03E4`. Both match ours.

The spawn code (NG `$8ABBC`, MD `$11134`, nearly the same compiled code) picks a special formation in 1 room in 4 once the area's room count is above 1. The type is `(rand >> 8) & 3`:

| Type | Formation | NG sets `$107E6C` at | Line | MD hook |
|---|---|---|---|---|
| 0 | 1-3 corpses | `$8B2EA` / `$8BFE2` | A169 "What happened here?" | none (`mdp_hum` finds the bodies) |
| 1 | ring of 8 around the player (room flags `& $7F80` = 0) | `$8C48A` / `$8C7E8` | A148 "It's a trap!" | `$1249E` → `mdp_rtrap` |
| 1 | the other rooms' variant | `$8C6C4` | A133 "An ambush?" | `$12930` → `mdp_ramb` |
| 2 | a crowd | `$8C50E` | A162 "So many of them!" | `$128D8` → `mdp_rhorde` |
| 3 | 2-5 big enemies | `$8CAFA` | A139 "Danger!" | `$13534` → `mdp_rdanger` |

- Each hook replaces a 6-byte instruction with a `jsr`. The routine runs that instruction itself and stores the line in `MDP_RL` (VARS+$320).
- On substate 4→2 (a new room), `mdp_room` queues `MDP_RL` with a 45-frame delay: the end of the Mega Drive's substate 2, matching NG frame 50. It also sets `MDP_NOBODY` = 2, so waiting humans still call out but "Rescue the humans" isn't said.
- Otherwise `mdp_hum` speaks for humans or bodies. Failing that, chatter follows the Neo Geo countdown (`MDP_CNT`, VARS+$321), also delayed 45 frames.
- Every room's flags seen in testing have bits in `$7F80`, so the ring (A148) may never come up. The MD and NG code both check this.
- NG room-voice playback is gated by `$107E6A` (an options toggle) and skipped when `$108BBE` = 1.

Woman rescued: `$1B6EE` (`pea 3 / move.l d0,-(sp)`, d0 = `$80`, then `jsr $3E91C`) → `mdp_fres`. With MD+ and sound on, it skips the game's sample. That sample plays only on the touch path (d3 ≠ 0 at `$1B6DC`).

Build note: `build.py` measures blocks at `$1000000+` now. At `$600000+`, a block could land within 32 KB of `$A11100` and vasm made `btst #0,$A11100` pc-relative in the measuring pass only.

## Hostages (Voices v1.0 beta 10)

The Neo Geo human routine is `$80B8A` (the MD's is `$1B5DC`, nearly the same code). It plays hostage voices as sound ids through `$58DE0(id, 3)`.

How ids map to samples: sample = id − 33 in a combined index. Table 1 holds entries 0-199 (Annn); table 2 continues it, so index 200 + k is C(k+1). The MD's own rescue sounds use the same ids: `$80` = A095 and `$86` = A101.

| What | NG code | Choice | Clips |
|---|---|---|---|
| Woman waiting | `$80C68` | `$D4 + (rand & 7)` | A179-A186, 1/8 each (A182 and A185 are second takes) |
| Man waiting | `$811D6` | rand & 7 = 0-1 → `$F3`; else `$F2 +` | C011 2/8; C012, C013, C014, C015, C016, C017 1/8 each (C015 = take of C012, C017 = take of C016) |
| Woman rescued | `$80DE6` | rand & 3 = 0-1 → `$80`; else `$D0 +` | A095 1/2, A177 1/4, A178 1/4 |
| Man rescued | `$80FF2` | rand & 3 = 0 → `$86`; else `$EF +` | A101, C008, C009, C010 (take of C008), 1/4 each |

Call timing:
- Each human has its own timer at obj+$2E.
- It starts at 60-315 frames when the human appears (`$806B4`).
- After each call it resets to 300-1323 frames (`$80C84`).
- Calls run only while the human is waiting: obj+$15 bits 1-3 clear.

Rescue lines play only on the "reached by a player" path (d3 ≠ 0 at `$80DCE`). That is the same place the MD plays its own sample.
- Hostages collected automatically after the room is cleared take the other path (an obj+$3C countdown). They are silent on both versions.
- A094 is not used by the hostage code. A175 and A176 aren't either.

The patch follows this:
- `mdp_mres` (`$1B92E`) and `mdp_fres` (`$1B6EE`) pick the line with the Neo Geo's odds. They store it in `MDP_RESC` (VARS+$322).
- `mdp_game` plays it next frame at `P_EVENT`, which cuts in. Beta 9 polled the rescued bit instead. It deferred while another line played, and the human left before the line got its turn, so some rescues went unvoiced.
- `mdp_hcall` keeps a per-object timer in 8-frame units: `MDP_HT`, VARS+$330, 52 bytes. It is cleared at each room start.
- VBlank code may use only d0-d3/a0-a2. An early beta 10 used a3 in `mdp_hcall` and froze the player.
- `$FF4726` is not a frame counter. The voice code only mixes it into its random numbers.

## Rescue lines vs room lines (Voices v1.0 beta 11)

The problem in beta 10: reach the hostages within about 45 frames of entering a room that has a special formation, and the room line (`MDP_DLY`, `P_EVENT`) came due and cut the rescue line off. On the Neo Geo they don't clash, because rescue lines are sound effects on their own channel.

Beta 11 fixes it:
- Rescue lines play at `P_RESC` (3, the same level as `P_STORY`; gameplay has no narration).
- A delayed line waits while `MDP_PRI` ≥ `P_RESC` or `MDP_RESC` is pending.
- A second rescue waits until the first rescue line has finished.
- `mdp_rline` clears `MDP_HUM`, so "Rescue the humans" never follows a rescue.
- `mdp_hum` only counts humans that are still waiting (obj+$15 & $0E = 0).

Random picks now use the generator's top bits (`rol.w`), not bits 8-10. Beta 10 kept picking the same rescue line.

## Voice queue (Voices v1.0 beta 12)

Priorities:

| Level | Name | Used for | Behaviour |
|---|---|---|---|
| 1 | `P_CHAT` | waiting hostages' calls | only plays into silence |
| 2 | `P_QUEUE` | rescue lines, weapon names | waits in a 1-line queue (`MDP_Q`, VARS+$324) |
| 3 | `P_EVENT` | room and screen lines | plays at once and cuts anything below |
| 4 | `P_STORY` | narration | always plays |

How the queue works:
- In `mdp_play`, a `P_QUEUE` line that arrives while anything at `P_QUEUE` or above is playing goes into the queue if it's empty. Otherwise it's dropped.
- `mdp_queue` runs every frame from `mdp_tick`, after the delayed room line. It plays the queued line once only chatter or nothing is playing.
- A queued line is dropped after 120 frames (`MDP_QAGE`, VARS+$325).
- The queue is cleared on every screen change.
- `mdp_hum` now waits only while a `P_EVENT` line plays, so "Rescue the humans" cuts in on queued-class lines.
- Beta 11's rule that room lines wait for rescue lines is gone: room lines win. A rescue line cut off by a room line is lost.

## Options > AUDIO items (Enhanced v1.3.6 + Voices v1.0 beta 13)

Enhanced owns the menu and the saving. Voices owns the playing. They share RAM at VARS+$326-$329:

| Address | Name | Meaning |
|---|---|---|
| VARS+$326 | `AUD_X` | cursor on an added item |
| VARS+$327 | `CSV` | cutscene voices: 0 = ALL, 1 = INTRO, 2 = NONE |
| VARS+$328 | `MDP_REQ` | CD VOICE play request |
| VARS+$329 | `CDTRK` | CD VOICE track, 1-85 |

How the menu is built:
- The items appear only when `MDP_ON` = 1, meaning the Voices patch is present and MD+ was found. Otherwise the screen is the game's.
- The game's audio screen ($2D90C draw, $2DD04 loop) keeps its own item indices 0-5.
- Every row computation (`add.w d0,d0 / addi.w #9,d0`, 13 places plus one using d1) goes through `aud_row0`/`aud_row1`, mapping rows to 9, 11, 15, 17, 19, 23.
- The cursor y (`lsl.w #4,d4 / addi.w #$C7,d4`, 3 places) goes through `aud_cy4`.
- `aud_in` (at $2DDBE) puts the cursor between items: up/down between SOUNDS and BGM, or between VOICE and BACK, sets `AUD_X`. While `AUD_X` is set, `aud_ext` handles the input and skips the game's.
- `aud_draw` (at $2DBBC) redraws rows 13-23 in the new layout.
- The game draws values at x = $23 - length (ending at column 34), and `aud_right` matches it.
- `CSV` is saved at SRAM offset 210 as the value and the value EOR $5A, so older saves keep their options.

What Voices does with them:
- With `CSV` = 2 there is no intro track, and `mdp_intro_mus` leaves the Mega Drive's music on.
- With `CSV` ≠ 0 there is no story narration.
- `mdp_queue` plays `MDP_REQ` at `P_STORY`, so leaving the screen stops it.

The main Options screen:
- LANGUAGE and CONTROLS swap rows ($3729E, $372BC).
- The language's name comes from entry $178 of its own string table, drawn right-aligned by `opt_lname`.
- Index 2 runs the game's item 3 and index 3 runs item 2. `opt_reent` (at $373AA) swaps the cursor back when returning from a sub-screen.

