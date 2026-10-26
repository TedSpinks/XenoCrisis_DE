; Xeno Crisis (Genesis v1.0.0) enhancement patch
;  - Roll priority (Dreamcast or Switch style)
;  - Pause screen HUD: health / weapon+ammo / grenades / dog tags per player,
;    combined score (top left) and high score (top right)
;
; Blocks are packed into free ROM space by build.py.

VDP_DATA    equ $C00000
VDP_CTRL    equ $C00004
SAT         equ $DC00
LAST        equ 79              ; H40 mode: 80 sprites
SPRBUF      equ $FF1380         ; game's sprite table copy (DMA'd to SAT every unpaused frame)
ORIG_VSYNC  equ $519E6
PAUSED      equ $FF000A         ; 1 while paused
TWOPLAYER   equ $FF1604         ; 1 in a 2-player game

STATS       equ $FF3306         ; per-player stats block, 66 bytes each
P1_OBJ      equ $FF228C         ; player 1 object (P2 = +64)

SCORE_U     equ $FF35DE         ; score = M*1000000 + K*1000 + U
SCORE_K     equ $FF36E6
SCORE_M     equ $FF10C4
HISCORE     equ $FF0FBC         ; game's own (single) high score, long

ICON_ATTR   equ $E000           ; priority + palette 3 (game's pop-up icons)
DIGIT_ATTR  equ $A000           ; priority + palette 1 (game's pop-up digits)
TILE_HEART  equ $67
TILE_GREN   equ $70
TILE_TAGS   equ $79
TILE_ZERO   equ $29
TILE_COMMA  equ $39             ; borrowed while paused (game re-uploads $33-$66 on unpause)
TILE_DIFF   equ $47             ; 4 tiles borrowed while paused: "EASY" / "HARD" (unused on screen then)
FONT8       equ $DD316          ; the game's 8x8 HUD font (digits and capitals, ASCII order from '0')

ROW0        equ 24
ROWSTEP     equ 44
NUMOFS      equ 26

; --- high score table ---
RUNNING     equ $FF46FC         ; screen loop keeps running while set
PAD1        equ $FF35E6         ; raw pads read by the VBlank handler (active high)
PAD2        equ $FF35E8
HISCORE2    equ $FF0FB8         ; the game keeps 3 copies of the high score
HISCORE3    equ $FF0468
TITLE_SCR   equ $37B44          ; screen 7
TITLE_INIT  equ $3A6E6          ; init for screen 7
SFX         equ $8CE82          ; play UI sound (id on stack)
SFX_MOVE    equ $47
SFX_OK      equ $6F
FONT        equ $DE926          ; 8x16 font, ASCII $20.., 64 bytes (2 tiles) per glyph
FONT_TILE   equ $300            ; where the table screen loads it (free on the title screen)
TITLE_PAL   equ $E8A38          ; title background palette (16 words)
TITLE_PAL_EASY equ $E8A12       ; ... on easy
PLANE_A     equ $E000
ATTRACT_DELAY equ 20*60         ; idle frames on the title before the table appears
ATTRACT_SHOW  equ 10*60
AFTER_SHOW    equ 5*60
ENTRY_TIME    equ 30*60
ARG           equ 4+11*4        ; my_dispatch: screen argument above the saved registers
PAL_WHITE   equ $A000           ; palettes 1-2 (palette 0 = title background), high priority
PAL_YELLOW  equ $C000
CH_HEART    equ '['             ; custom glyphs replace these font slots on the table screen
CH_BACK     equ '\'
CH_END      equ ']'
CH_RIGHT    equ '^'             ; right arrow (the left one is CH_BACK)
NCHARS      equ 28              ; A-Z back end (nothing entered: 68K)
SR_MAGIC    equ 0               ; save layout (odd bytes from $200001): 'XCH' + version
SR_VERSION  equ '2'             ; 2: easy / hard tables with areas
SR_TABLE    equ 4
SR_SUM      equ 84
SR_TEST     equ 100
SR_OPTS     equ 104             ; OPTS_LEN bytes + checksum
SR_TABLE2   equ 124             ; hard table, 80 bytes + checksum
SR_EXTRA    equ 210             ; cutscene voices setting, then it EOR $5A
SR_XTAB     equ 212             ; easy table details: 10 x (detail, tag) + checksum
SR_XTAB2    equ 234             ; hard table details

; work RAM: bottom of the 2KB stack zone ($FFF800-$FFFFFF, deepest use seen ~$FFFD80)
VARS        equ $FFF810
NUMBUF      equ VARS            ; 16 bytes: formatted number glyphs (0-9, 10=comma)
LINEBUF     equ VARS+$10        ; 48 bytes: one text line
TABLE       equ VARS+$40        ; easy table, 10 x 8 bytes: score.l, initials x3, area (AREA_*)
PENDING     equ VARS+$90        ; b: a game was started, check its score at the title
PEND2P      equ VARS+$91        ; b
ATTRACT     equ VARS+$92        ; b: title exited for the attract table
SRAM_OK     equ VARS+$93        ; b
IDLE        equ VARS+$94        ; w
PADOLD      equ VARS+$96        ; w
NEWIDX      equ VARS+$98        ; w: row being entered (-1 none)
ENTPOS      equ VARS+$9A        ; w
ENTCHR      equ VARS+$9C        ; w
TIMER       equ VARS+$9E        ; w
FRAMES      equ VARS+$A0        ; w
REPT        equ VARS+$A2        ; w
PRESSED     equ VARS+$A4        ; w
HELD        equ VARS+$A6        ; w
LANGSEEN    equ VARS+$A8        ; b: the boot language screen has been passed
HSCOL       equ VARS+$AA        ; w: table column offset
RAMMAGIC    equ VARS+$AC        ; l: 'XCHT' once the table has been set up this power-on
CURID       equ VARS+$C2        ; b: table shown: 0 easy, 1 hard
GCHEAT      equ VARS+$C3        ; b: cheat menu settings or a special mode: no table at all
ALTLABEL    equ VARS+$120       ; b: Options view: showing EASY / HARD, not the reset hint
AREAW       equ VARS+$121       ; b: width of the area column (1-4: the widest entry)
BESTD1      equ VARS+$122       ; b: detail (DET_*) of player 1's best credit
BESTD2      equ VARS+$123       ; b
GBOSS       equ VARS+$124       ; b: area (1-) whose boss fight was reached (0 none)
; each table row's detail: XOFS bytes past the row (rows are 8 bytes apart), detail then tag.
; Kept apart from the rows so older versions read the same tables; shown only if the tag
; (a sum of the row's score and area bytes) still matches the row.
XOFS        equ $340            ; TABLE+XOFS = VARS+$380, TABLE2+XOFS = VARS+$410
DET_B       equ $FE             ; detail: 0 none, 1-99 room n of the area, B = its boss fight,
DET_STAR    equ $FF             ;   star = died at the final boss, then won after continuing
CH_STAR     equ '*'             ; (blank in the game's font)
; ---- per-player scores (2-player games: who earned each point) ----
DMGBUF      equ VARS+$130       ; up to 52 words: pending damage (+$2C) of the listed enemies
LASTHIT     equ VARS+$1A0       ; 64 bytes: player (1/2) who last damaged each object
OWNER       equ VARS+$1E0       ; 64 bytes: owner of player projectiles (grenades) in slots 17-49
ACTV        equ VARS+$220       ; 64 bytes: object active at the start of this frame
ELIST       equ VARS+$260       ; up to 52 words: offsets (index*64) of live enemies
ECOUNT      equ VARS+$2C8       ; w: listed enemies - 1 (-1 = none)
LASTD2      equ VARS+$2CA       ; w: last object updated (frame start detection)
CUROBJ      equ VARS+$2CC       ; w: object being updated (-1 outside the update loop)
CURPL       equ VARS+$2CE       ; b: owner of the updates since the damage snapshot
ENTPAD      equ VARS+$2CF       ; b: initials entry pad: 0 = pad 1, 1 = pad 2
SPLIT1      equ VARS+$2D0       ; l: player 1's score this credit
SPLIT2      equ VARS+$2D4       ; l: player 2's
BEST1       equ VARS+$2D8       ; l: player 1's best finished credit this game
BEST2       equ VARS+$2DC       ; l
IDX3        equ VARS+$2E0       ; w: player 2's new row (-1 none)
GREN        equ VARS+$2E2       ; b: grenades before a player's update
OBJBASE     equ $FF160C         ; object table, 64 bytes each (players: 50, 51)
GAREA       equ VARS+$C4        ; b: area being played (1-), set at each area start
GCONT       equ VARS+$C5        ; b: a continue screen has appeared this game
GCLEAR      equ VARS+$C6        ; b: the ending (credits) was reached
GDIFF       equ VARS+$C7        ; b: difficulty at the start of the game (which table)
BESTA1      equ VARS+$C8        ; b: area code of player 1's best credit
BESTA2      equ VARS+$C9        ; b
IDX1        equ VARS+$CC        ; w: player 1's new row (-1 none)
TABLE2      equ VARS+$D0        ; hard table, as TABLE
AREA_ALL    equ 30              ; row byte: bits 0-4 area 1-29, ALL = finished after continuing,
AREA_1CC    equ 31              ;   1CC = finished on one credit; bits 5-7 marine + 1 (recorded, not shown)
AREA_MASK   equ $1F
GSKIN1      equ VARS+$CA        ; b: player 1's marine this credit, (0-3 + 1) << 5
GSKIN2      equ VARS+$CB        ; b
SKIN_P1     equ $FF000F         ; game: each player's marine (bit 1 = female, bit 0 = blue)
SKIN_P2     equ $FF000E
CURAREA     equ $FF3304         ; game: current area (0-)
ROLLMODE    equ VARS+$A9        ; b: 0 Genesis (original), 1 Dreamcast, 2 Modern (Switch/Steam)
ROLL_DEFAULT equ 2
OPTS        equ VARS+$B0        ; saved options (OPTS_LEN bytes):
OPTS_LEN    equ 18              ;  O marker, language, difficulty, music, sounds, pad type P1, P2, roll mode,
                                ;  controller config bytes $FF0158-$FF0161
LANGUAGE    equ $FF1608
DIFFICULTY  equ $FF340E
MUSIC_ON    equ $FF471C
SOUNDS_ON   equ $FF4720
PADTYPE1    equ $FF35F6         ; 1 = 6-button pad
PADTYPE2    equ $FF35F7
CTRL        equ $FF0158         ; P2 config, P1 config, P2 masks .w $15A, P1 $15C, P2 $15E, P1 $160

;============================================================================
;============================================================================

; ---- MD+ voice (MegaSD CD audio). Tracks come from the player's own Neo Geo ROM
; (mdplus/xc_voice_extract.py writes them in this order).
MDP_OVL     equ $3F7FA              ; overlay port: $CD54 opens the interface, 0 closes it
MDP_CMD     equ $3F7FE              ; command port: $11nn play track nn once, $13ff stop (ff = fade)
SCREEN_W    equ $FF01B4             ; game: current screen
SUBSTATE    equ $FF3410             ; game: screen's state (gameplay: 0 fight, 1 area name, 3 room
                                    ; clear, 5 game over, 7 boss room, 9 area clear)
CUT_LINE    equ $FF045D             ; game: story text line being typed (0 = new page)
CUT_PAGE    equ $FF045E             ; game: story page
CUT_CHAR    equ $FF0472             ; game: character within the line
MDP_ON      equ VARS+$300           ; b: 1 = MD+ interface found
MDP_SCR     equ VARS+$301           ; b: screen seen last frame
MDP_SUB     equ VARS+$302           ; b: substate seen last frame
MDP_PAGE    equ VARS+$303           ; b: story page already voiced (-1 none)
MDP_PRI     equ VARS+$304           ; b: priority of the clip playing (0 = none)
MDP_ALT     equ VARS+$305           ; b: alternates between two takes of a line
MDP_BUSY    equ VARS+$306           ; w: frames until the clip playing ends
MDP_RND     equ VARS+$308           ; w: random numbers for room chatter
MDP_HUM     equ VARS+$30A           ; b: frames left to look for humans in a new room
MDP_DTRK    equ VARS+$30B           ; b: track waiting for MDP_DLY
MDP_DLY     equ VARS+$310           ; w: frames until MDP_DTRK plays (0 = none)
MDP_SECS    equ VARS+$312           ; 2 b: each player's special weapon seconds last frame
MDP_NOBODY  equ VARS+$315           ; b: this room's first-room line was already "What happened here?"
MDP_MAGIC   equ VARS+$30C           ; l: 'MDP+' once the interface has been looked for
MDP_RL      equ VARS+$320           ; b: line the spawn code picked for the next room (0 = none)
MDP_CNT     equ VARS+$321           ; b: rooms until the next bit of chatter (as $107E6E on the Neo Geo)
MDP_RESC    equ VARS+$322           ; b: a rescue line for mdp_game to play (0 = none)
MDP_FRM     equ VARS+$323           ; b: frame count for mdp_hcall
MDP_Q       equ VARS+$324           ; b: the queued line (0 = none)
MDP_QAGE    equ VARS+$325           ; b: frames it has waited (dropped after 2 s)
; shared with Enhanced's Options > Audio (both patches use these; each works without the other)
AUD_X       equ VARS+$326           ; b: Enhanced: cursor on an added Audio item (1 cutscene voices, 2 CD voice)
CSV         equ VARS+$327           ; b: cutscene voices: 0 all, 1 intro only, 2 none (Enhanced saves it)
MDP_REQ     equ VARS+$328           ; b: a track Options > Audio > CD VOICE asks Voices to play (0 = none)
CDTRK       equ VARS+$329           ; b: the CD VOICE item's track, 1-85
MDP_HT      equ VARS+$330           ; 52 b: each object's call timer, 8-frame units (0 = not a waiting human yet)
P_CHAT      equ 1                   ; only when nothing else is playing (waiting hostages' calls)
P_QUEUE     equ 2                   ; rescue lines, weapon names: wait in a 1-line queue while anything plays
P_EVENT     equ 3                   ; room and screen lines: cut in on anything below
P_STORY     equ 4                   ; narration: always plays
T_INTRO     equ 1                   ; Neo Geo intro: music + narration
T_CUT1      equ 2                   ; cutscenes 1-6 (screen 4, one page each)
T_HERZOG    equ 8                   ; Dr. Herzog's scene (screen 5), pages 0-8
T_END       equ 17                  ; ending (screen 6), pages 0-2
V_A092      equ 20
V_A094      equ 21
V_A095      equ 22
V_A100      equ 23
V_A101      equ 24
V_A106      equ 25
V_A107      equ 26
V_A133      equ 27
V_A134      equ 28
V_A135      equ 29
V_A136      equ 30
V_A137      equ 31
V_A138      equ 32
V_A139      equ 33
V_A140      equ 34
V_A141      equ 35
V_A142      equ 36
V_A143      equ 37
V_A144      equ 38
V_A145      equ 39
V_A146      equ 40
V_A147      equ 41
V_A148      equ 42
V_A149      equ 43
V_A150      equ 44
V_A151      equ 45
V_A152      equ 46
V_A153      equ 47
V_A154      equ 48
V_A155      equ 49
V_A156      equ 50
V_A157      equ 51
V_A158      equ 52
V_A159      equ 53
V_A160      equ 54
V_A161      equ 55
V_A162      equ 56
V_A163      equ 57
V_A164      equ 58
V_A165      equ 59
V_A166      equ 60
V_A167      equ 61
V_A168      equ 62
V_A169      equ 63
V_A170      equ 64
V_A171      equ 65
V_A175      equ 66
V_A176      equ 67
V_A177      equ 68
V_A178      equ 69
V_A179      equ 70
V_A180      equ 71
V_A181      equ 72
V_A182      equ 73
V_A183      equ 74
V_A184      equ 75
V_A185      equ 76
V_A186      equ 77
V_C003      equ 78                  ; Herzog laughs (tracks 78-85 added in Voices beta 8)
V_C008      equ 79                  ; man: "Thank you!"
V_C009      equ 80                  ; man: "Thanks!"
V_C011      equ 81                  ; man: "Hey!"
V_C012      equ 82                  ; man: "Save me!"
V_C013      equ 83                  ; man: "Help!"
V_C014      equ 84                  ; man: "Over here!"
V_C016      equ 85                  ; man: "Hey!" (calling out)

        BLOCK roll_hook
; jumped to from $262A (after d-pad handling)
roll_hook:
        tst.b   ROLLMODE
        bne   .new
        tst.w   $46(sp)             ; Genesis: the original code (fire held blocks the roll)
        bne   .shoot
        jmp     $7302
.new:   move.w  a3,d0               ; roll beats fire: roll button mask
        beq   .fire
        and.w   $3a(sp),d0          ; newly pressed
        cmp.w   a3,d0
        bne   .fire
        jmp     $730E               ; start roll (skip this frame's shot)
.fire:  tst.w   $46(sp)             ; fire held?
        bne   .shoot
        jmp     $26F4
.shoot: jmp     $2632
; jumped to from $2EE0 during a roll: does fire cancel it?
roll_cancel:
        cmpi.b  #1,ROLLMODE
        beq   .cont                 ; Dreamcast: never
        bcs   .gen
        tst.w   $54(sp)             ; Modern: a new fire press does
        bra   .t
.gen:   tst.w   $46(sp)             ; Genesis: fire held does
.t:     beq   .cont
        jmp     $2EE8
.cont:  jmp     $41CE

        BLOCK pause_hud
; replaces "jsr $519E6" at $3168A (runs every gameplay frame)
pause_hud:
        jsr     ORIG_VSYNC
        move.l  d0,-(sp)
        move.w  SUBSTATE,d0         ; boss room camera (7) or boss intro (8): this area's boss
        subq.w  #7,d0
        cmpi.w  #1,d0
        bhi   .nb
        move.b  CURAREA,d0
        addq.b  #1,d0
        move.b  d0,GBOSS
.nb:    move.l  (sp)+,d0
        tst.b   PAUSED
        bne   .go
        rts
.go:    movem.l d0-d7/a0-a6,-(sp)
        move.w  sr,-(sp)
        ori.w   #$0700,sr
        lea     VDP_CTRL,a5
        lea     VDP_DATA,a6
        move.w  #$8F02,(a5)
        ; comma glyph into a borrowed tile
        move.l  #$40000000|((TILE_COMMA*32)&$3FFF)<<16|((TILE_COMMA*32)>>14),(a5)
        lea     comma_gfx,a0
        moveq   #7,d0
.c:     move.l  (a0)+,(a6)
        dbra    d0,.c
        jsr     diff_gfx            ; the difficulty's name into 4 more
        ; rebuild the sprite table from slot 0: HUD first, then the game's visible sprites
        move.l  #$40000000|(SAT&$3FFF)<<16|(SAT>>14),(a5)
        moveq   #0,d6
        jsr     hud_scores
        lea     STATS,a0
        lea     P1_OBJ,a1
        moveq   #4,d5
        jsr     player
        tst.b   TWOPLAYER
        beq   .game
        lea     STATS+66,a0
        lea     P1_OBJ+64,a1
        move.w  #292,d5
        jsr     player
.game:  jsr     diff_spr
        jsr     game_sprites
        move.w  (sp)+,sr
        movem.l (sp)+,d0-d7/a0-a6
        rts

;============================================================================
        BLOCK game_sprites
; append the game's on-screen sprites (from its RAM copy) and terminate the chain
game_sprites:
        lea     SPRBUF,a2
        moveq   #0,d1
        moveq   #LAST,d4            ; at most 80 links (never loop on a bad chain)
.walk:  move.w  d1,d0
        lsl.w   #3,d0
        lea     0(a2,d0.w),a3
        move.w  (a3),d0
        andi.w  #$3FF,d0
        cmpi.w  #128-32,d0          ; skip sprites parked off-screen
        bcs   .next
        cmpi.w  #128+224,d0
        bcc   .next
        cmpi.w  #LAST+1,d6
        beq   .term
        move.w  (a3),(a6)
        moveq   #0,d2
        move.b  2(a3),d2
        lsl.w   #8,d2
        addq.w  #1,d6
        jsr     setlink
        move.w  d2,(a6)
        move.w  4(a3),(a6)
        move.w  6(a3),(a6)
.next:  moveq   #$7F,d1
        and.b   3(a3),d1
        dbeq    d4,.walk
.term:  cmpi.w  #LAST+1,d6
        beq   .done
        moveq   #0,d0
        move.l  d0,(a6)
        move.l  d0,(a6)
.done:  rts

;============================================================================
        BLOCK emit
; emit one sprite: d0 = x, d1 = y, d2 = size, d3 = attr. d0/d1 preserved. Uses d6 (slot).
emit:
        cmpi.w  #LAST+1,d6
        beq   .full
        move.w  d1,a2
        lea     128(a2),a2
        move.w  a2,(a6)
        lsl.w   #8,d2
        addq.w  #1,d6
        bsr   setlink
        move.w  d2,(a6)
        move.w  d3,(a6)
        move.w  d0,a2
        lea     128(a2),a2
        move.w  a2,(a6)
.full:  rts
; d2 |= link to slot d6 (0 if past the last slot)
setlink:
        cmpi.w  #LAST+1,d6
        beq   .end
        or.w    d6,d2
.end:   rts

;============================================================================
        BLOCK player
; a0 = stats block, a1 = player object, d5 = column x
player:
        moveq   #ROW0,d4
        move.w  #ICON_ATTR|TILE_HEART,d3
        move.w  $28(a1),d0          ; health
        ext.l   d0
        bpl   .hp
        moveq   #0,d0
.hp:    jsr     item
        move.w  $14(a0),d3          ; current weapon icon slot
        ori.w   #ICON_ATTR,d3
        moveq   #0,d0
        move.b  $0D(a0),d0          ; special weapon: seconds left
        bne   .spec
        move.b  $19(a0),d0          ; default weapon: ammo
.spec:  jsr     item
        move.w  #ICON_ATTR|TILE_GREN,d3
        moveq   #0,d0
        move.b  $1B(a0),d0          ; grenades
        jsr     item
        move.w  #ICON_ATTR|TILE_TAGS,d3
        moveq   #0,d0
        move.w  $1C(a0),d0          ; dog tags
        jmp     item

;============================================================================
        BLOCK item
; d3 = icon attr, d0.l = value, d4 = row y (advanced), d5 = column x
item:
        movem.l d0/a0-a1,-(sp)
        move.w  d5,d0
        move.w  d4,d1
        moveq   #$0A,d2             ; 3x3 cells
        jsr     emit
        move.l  (sp),d0
        moveq   #0,d3               ; no commas
        jsr     fmtnum
        jsr     numwidth
        lsr.w   #1,d1
        move.w  d5,d0
        addi.w  #12,d0
        sub.w   d1,d0
        move.w  d4,d1
        addi.w  #NUMOFS,d1
        jsr     drawnum
        addi.w  #ROWSTEP,d4
        movem.l (sp)+,d0/a0-a1
        rts

;============================================================================
        BLOCK hud_scores
; Neo Geo layout: player 1's score top-left, player 2's top-right (2-player game), the high
; score in the middle
hud_scores:
        move.l  SPLIT1,d0
        moveq   #1,d3
        jsr     fmtnum
        moveq   #8,d0
        moveq   #8,d1
        jsr     drawnum
        tst.b   TWOPLAYER
        beq   .hi
        move.l  SPLIT2,d0
        moveq   #1,d3
        jsr     fmtnum
        jsr     numwidth
        move.w  #312,d0
        sub.w   d1,d0
        moveq   #8,d1
        jsr     drawnum
.hi:    jsr     hs_top              ; high score: top of this difficulty's table, or a player beating it
        cmp.l   SPLIT1,d0
        bcc   .a
        move.l  SPLIT1,d0
.a:     cmp.l   SPLIT2,d0
        bcc   .b
        move.l  SPLIT2,d0
.b:     moveq   #1,d3
        jsr     fmtnum
        jsr     numwidth
        lsr.w   #1,d1
        move.w  #160,d0
        sub.w   d1,d0
        moveq   #8,d1
        jmp     drawnum

;============================================================================
        BLOCK live_score
; d0.l = current combined score. clobbers d1
live_score:
        moveq   #0,d0
        move.w  SCORE_M,d0
        mulu.w  #1000,d0
        moveq   #0,d1
        move.w  SCORE_K,d1
        add.l   d1,d0
        move.l  d0,d1               ; d0 *= 1000 (32-bit)
        swap    d1
        mulu.w  #1000,d1
        swap    d1
        clr.w   d1
        mulu.w  #1000,d0
        add.l   d1,d0
        moveq   #0,d1
        move.w  SCORE_U,d1
        add.l   d1,d0
        rts
; d0.l = max(d0, high score)
best_score:
        cmp.l   HISCORE,d0
        bcc   .ok
        move.l  HISCORE,d0
.ok:    rts

;============================================================================
        BLOCK fmtnum
; d0.l value (0..99999999), d3 = 1 for thousands commas
; out: NUMBUF filled, a0 = end. clobbers d0-d2,d7,a1
fmtnum:
        movem.l d4-d5,-(sp)
        lea     NUMBUF,a0
        lea     pow10,a1
        moveq   #7,d7
        moveq   #0,d2               ; started
.pos:   move.l  (a1)+,d1
        moveq   #0,d4
.sub:   cmp.l   d1,d0
        bcs   .got
        sub.l   d1,d0
        addq.w  #1,d4
        bra   .sub
.got:   tst.w   d2
        bne   .out
        tst.w   d4
        bne   .out
        tst.w   d7                  ; always print the last digit
        bne   .skip
.out:   moveq   #1,d2
        move.b  d4,(a0)+
        tst.w   d3
        beq   .skip
        cmpi.w  #6,d7
        beq   .com
        cmpi.w  #3,d7
        bne   .skip
.com:   move.b  #10,(a0)+
.skip:  dbra    d7,.pos
        movem.l (sp)+,d4-d5
        rts

;============================================================================
        BLOCK drawnum
; numwidth: a0 = end of NUMBUF data -> d1 = width in pixels. clobbers d0,a1
numwidth:
        lea     NUMBUF,a1
        moveq   #0,d1
.l:     cmpa.l  a0,a1
        beq   .d
        moveq   #8,d0
        cmpi.b  #10,(a1)+
        bne   .a
        moveq   #4,d0
.a:     add.w   d0,d1
        bra   .l
.d:     rts
; drawnum: d0 = x, d1 = y, a0 = end of NUMBUF data. emits sprites. keeps d4/d5
drawnum:
        lea     NUMBUF,a1
.l:     cmpa.l  a0,a1
        beq   .d
        moveq   #0,d3
        move.b  (a1)+,d3
        moveq   #0,d2
        cmpi.b  #10,d3
        beq   .com
        addi.w  #DIGIT_ATTR|TILE_ZERO,d3
        jsr     emit
        addq.w  #8,d0
        bra   .l
.com:   move.w  #DIGIT_ATTR|TILE_COMMA,d3
        jsr     emit
        addq.w  #4,d0
        bra   .l
.d:     rts

;============================================================================
        BLOCK data_hud
pow10:  dc.l    10000000,1000000,100000,10000,1000,100,10,1
;============================================================================
        BLOCK diff_hud
; pause screen: the difficulty, bottom left (the game shows the seed bottom right)
diff_gfx:                           ; (VDP write address free to change: before the sprite table)
        move.l  #$40000000|((TILE_DIFF*32)&$3FFF)<<16|((TILE_DIFF*32)>>14),(a5)
        lea     diff_easy,a1
        tst.b   DIFFICULTY
        beq   .e
        lea     diff_hard,a1
.e:     moveq   #3,d1
.ch:    moveq   #0,d0
        move.b  (a1)+,d0
        subi.w  #'0',d0
        lsl.w   #5,d0
        lea     FONT8,a0
        adda.w  d0,a0
        moveq   #7,d0
.c:     move.l  (a0)+,(a6)
        dbra    d0,.c
        dbra    d1,.ch
        rts
diff_spr:
        moveq   #8,d0
        move.w  #208,d1
        moveq   #$0C,d2             ; 4x1 cells
        move.w  #DIGIT_ATTR|TILE_DIFF,d3
        jmp     emit
diff_easy:
        dc.b    'EASY'
diff_hard:
        dc.b    'HARD'

;============================================================================
        BLOCK pause_data
comma_gfx:                          ; same colours as the game's digits (1 = white, F = shadow)
        dc.l    $00000000,$00000000,$00000000,$00000000
        dc.l    $00000000,$01100000,$011F0000,$001F0000

;============================================================================
;  HIGH SCORE TABLE
;============================================================================
        BLOCK dispatch
; replaces "movea.l 0(a2,d0.l),a0 / jsr (a0)" in the screen dispatcher at $F3A
; d0 = screen*4, a2 = screen table, 4(sp) = argument for the screen
my_dispatch:
        movem.l d2-d7/a2-a6,-(sp)   ; the dispatcher keeps its tables in a2/a3 (C callee-saved regs)
        move.l  d0,d2
        movea.l 0(a2,d0.l),a0
        cmpi.w  #7*4,d0
        beq     .title
        cmpi.w  #2*4,d0             ; language select
        bne     .n2
        jsr     opts_skip_lang      ; skipped at boot if the language was saved
        tst.w   d0
        bne     .ret
        movea.l 0(a2,d2.l),a0
.n2:    move.l  a0,-(sp)
        jsr     game_track          ; d2 = screen*4
        movea.l (sp)+,a0
.call:  move.l  ARG(sp),-(sp)
        jsr     (a0)
        addq.l  #4,sp
        jsr     opts_after
        bra     .ret
.title: clr.w   IDLE
        tst.b   PENDING
        beq     .run
        clr.b   PENDING
        jsr     hs_game_over        ; table + initials if the score qualifies
        tst.w   d0
        bne     .reinit
.run:   move.l  ARG(sp),-(sp)
        jsr     TITLE_SCR
        addq.l  #4,sp
        tst.b   ATTRACT
        bne     .attr
.ret:   movem.l (sp)+,d2-d7/a2-a6
        rts
.attr:  clr.b   ATTRACT
        jsr     hs_attract
.reinit:
        jsr     free_objs           ; the title's init runs again: free what the last one made
        clr.w   $FF3410             ; the dispatcher's fresh-entry resets
        clr.w   $FF4362
        clr.w   $FF36D0
        clr.w   $FF10BA
        clr.w   IDLE
        clr.l   ARG(sp)             ; as a fresh entry (not "back from Options", which skips the intro)
        move.l  ARG(sp),-(sp)
        jsr     TITLE_INIT
        addq.l  #4,sp
        bra     .run

;============================================================================
        BLOCK title_vsync
; replaces the title loop's vsync routine: count idle frames, leave for the attract table
title_vsync:
        jsr     ORIG_VSYNC
        move.w  PAD1,d0
        or.w    PAD2,d0
        bne   .act
        addq.w  #1,IDLE
        cmpi.w  #ATTRACT_DELAY,IDLE
        bcs   .r
        clr.w   IDLE
        move.b  #1,ATTRACT
        clr.b   RUNNING             ; title loop exits at the end of this frame
.r:     rts
.act:   clr.w   IDLE
        rts

;============================================================================
        BLOCK hs_init
; boot (replaces the game's "high score = 68000" setup at $730)
hs_init:
        movem.l d0-d7/a0-a6,-(sp)
        cmpi.l  #'XCHT',RAMMAGIC    ; a soft reset keeps RAM: keep this session's table
        beq   .keep
        jsr     hs_defaults
        move.l  #'XCHT',RAMMAGIC
        move.b  #ROLL_DEFAULT,ROLLMODE
.keep:  clr.b   LANGSEEN
        clr.b   PENDING
        clr.b   ATTRACT
        clr.w   IDLE
        jsr     sram_load
        jsr     hs_fixdefs
        jsr     hs_sync
        jsr     opts_apply
        movem.l (sp)+,d0-d7/a0-a6
        rts
hs_defaults:
        lea     TABLE,a1
        bsr   hs_def
        lea     TABLE2,a1
; a1 = table <- the Neo Geo defaults
hs_def:
        lea     hs_default_tab,a0
        moveq   #9,d1
.c:     move.l  (a0)+,(a1)
        move.l  (a0)+,4(a1)
        jsr     hs_one1
        addq.l  #8,a1
        dbra    d1,.c
        rts
; d0.l = top score of the table for the difficulty set
hs_top:
        move.l  TABLE,d0
        tst.b   DIFFICULTY
        beq   .e
        move.l  TABLE2,d0
.e:     rts
; game's own high score copies = top of the table for the difficulty set
hs_sync:
        bsr   hs_top
        move.l  d0,HISCORE
        move.l  d0,HISCORE2
        move.l  d0,HISCORE3
        rts

;============================================================================
        BLOCK hs_game_over
; d0.w = 1 if a table screen was shown. Each player's best credit goes on the table for the
; game's difficulty (arcade rules: a continue starts a new score).
hs_game_over:
        movem.l d2-d7,-(sp)
        move.w  #-1,IDX1
        move.w  #-1,IDX3
        move.b  GDIFF,CURID         ; (1 = hard)
        tst.b   GCHEAT              ; cheats / special modes: no table
        bne   .go
        move.l  SPLIT1,d0           ; player 1
        move.l  BEST1,d1
        move.b  GSKIN1,d2
        moveq   #0,d3
        move.b  BESTA1,d3
        move.b  BESTD1,d4
        jsr     hs_final
        jsr     hs_tabptr
        movea.l a1,a0
        jsr     hs_insert
        move.w  d0,IDX1
        tst.b   PEND2P
        beq   .go
        move.l  SPLIT2,d0           ; player 2
        move.l  BEST2,d1
        move.b  GSKIN2,d2
        moveq   #0,d3
        move.b  BESTA2,d3
        move.b  BESTD2,d4
        jsr     hs_final
        jsr     hs_tabptr
        movea.l a1,a0
        jsr     hs_insert
        move.w  d0,IDX3
        bmi   .go
        move.w  IDX1,d1             ; player 1's row moved down (or off the table)?
        bmi   .go
        cmp.w   d0,d1
        bcs   .go
        addq.w  #1,d1
        cmpi.w  #10,d1
        bcs   .s1
        moveq   #-1,d1
.s1:    move.w  d1,IDX1
.go:    movem.l (sp)+,d2-d7
        jmp     hs_show_new

;============================================================================
        BLOCK hs_final
; d0 = last credit's score (0 if it ended at a continue screen: already in d1), d2 = its
; marine bits, d1 = best earlier credit, d3 = its row byte, d4 = its detail
; -> d0 = score, d1 = row byte, d4 = detail
hs_final:
        cmp.l   d0,d1
        bhi   .b
        jsr     cur_detail          ; (ended without a continue screen)
        move.b  d1,d4
        move.b  GAREA,d1
        tst.b   GCLEAR
        beq   .x
        moveq   #0,d4
        move.b  #AREA_1CC,d1        ; the ending: on one credit, or after continuing
        tst.b   GCONT
        beq   .x
        move.b  #AREA_ALL,d1
.x:     or.b    d2,d1
        rts
.b:     move.l  d1,d0
        move.l  d3,d1
        rts

;============================================================================
        BLOCK hs_show_new
; after a game: initials for player 1, then player 2 (own pads), on the table for its
; difficulty (CURID); then save and show it
hs_show_new:
        move.w  IDX1,d0
        and.w   IDX3,d0
        bmi   .none                 ; (neither is a row)
        move.w  #-1,NEWIDX
        jsr     hs_screen_on
        move.w  IDX1,d1
        bmi   .p2
        clr.b   ENTPAD
        jsr     hs_entry_at
.p2:    move.w  IDX3,d1
        bmi   .sv
        move.b  #1,ENTPAD
        jsr     hs_entry_at
        clr.b   ENTPAD
.sv:    jsr     hs_sync
        jsr     sram_save
        move.w  #-1,NEWIDX
        jsr     hs_draw_all
        move.w  #AFTER_SHOW,d0
        jsr     hs_wait
        clr.b   CURID
        jsr     hs_screen_off
        moveq   #1,d0
        rts
.none:  clr.b   CURID
        moveq   #0,d0
        rts

;============================================================================
        BLOCK hs_insert
; a0 = table, d0.l = score, d1.b = flags, d4.b = detail -> d0.w = new row, or -1 (no place)
hs_insert:
        cmp.l   9*8(a0),d0          ; must beat 10th place
        bls   .no
        movea.l a0,a1
        moveq   #0,d2
.f:     cmp.l   (a1),d0
        bhi   .ins
        addq.l  #8,a1
        addq.w  #1,d2
        bra   .f
.ins:   lea     9*8(a0),a0          ; shift lower entries down
.s:     cmpa.l  a1,a0
        beq   .put
        move.l  -8(a0),(a0)
        move.l  -4(a0),4(a0)
        move.w  -8+XOFS(a0),XOFS(a0)
        subq.l  #8,a0
        bra   .s
.put:   move.l  d0,(a1)
        move.l  #$20202000,4(a1)
        move.b  d1,7(a1)
        move.b  d4,XOFS(a1)
        jsr     hs_tag
        move.b  d0,XOFS+1(a1)
        move.w  d2,d0
        rts
.no:    moveq   #-1,d0
        rts
; a1 = the table being shown
hs_tabptr:
        lea     TABLE,a1
        tst.b   CURID
        beq   .x
        lea     TABLE2,a1
.x:     rts

;============================================================================
        BLOCK game_track
; called by the dispatcher before each screen (d2 = screen*4): follow the game for the tables
game_track:
        cmpi.w  #14*4,d2            ; marine select: a new game (unless continuing one)
        bne   .n14
        tst.b   PENDING
        bne   .x
        clr.b   GCONT
        clr.b   GCLEAR
        clr.b   GBOSS
        clr.b   BESTD1
        clr.b   BESTD2
        move.b  DIFFICULTY,GDIFF
        jsr     split_reset
        jmp     game_rules
.n14:   cmpi.w  #15*4,d2            ; gameplay begins / next area
        bne   .n15
        move.b  #1,PENDING          ; check this game's score when the title is next entered
        move.b  TWOPLAYER,PEND2P
        move.b  CURAREA,d0
        addq.b  #1,d0
        move.b  d0,GAREA
        jmp     split_skins
.n15:   tst.b   PENDING
        beq   .x
        cmpi.w  #1*4,d2             ; continue screen: a credit is over
        bne   .n1
        st      GCONT
        move.b  CURAREA,d0          ; the area it ended in (later areas start without
        addq.b  #1,d0               ; screen 15)
        move.b  d0,GAREA
        jmp     split_credit_end
.n1:    cmpi.w  #5*4,d2             ; Dr. Herzog's scene: the final boss encounter
        bne   .n5
        move.b  CURAREA,d0
        addq.b  #1,d0
        move.b  d0,GBOSS
        rts
.n5:    cmpi.w  #18*4,d2            ; credits during a game: the game was finished
        bne   .x
        st      GCLEAR
        jmp     game_star
.x:     rts

;============================================================================
        BLOCK hs_xtra
; d1.b = where in the current area the credit ended: DET_B in its boss fight, else the room
; it was on (rooms cleared + 1, at most 99). Uses d1 only.
cur_detail:
        move.b  CURAREA,d1
        addq.b  #1,d1
        cmp.b   GBOSS,d1
        bne   .r
        moveq   #-2,d1              ; DET_B
        rts
.r:     move.b  $FF4B3C,d1          ; the game's rooms cleared in this area
        cmpi.b  #98,d1
        bls   .k
        moveq   #98,d1
.k:     addq.b  #1,d1
        rts
; a1 = row -> d0.b = its tag. Uses d0 only.
hs_tag:
        moveq   #$5A,d0
        add.b   (a1),d0
        add.b   1(a1),d0
        add.b   2(a1),d0
        add.b   3(a1),d0
        add.b   7(a1),d0
        rts
; a1 = row -> d0.b = its detail, 0 if none or the tag doesn't match. Uses d0-d1.
hs_det:
        jsr     hs_tag
        move.b  d0,d1
        moveq   #0,d0
        cmp.b   XOFS+1(a1),d1
        bne   .x
        move.b  XOFS(a1),d0
.x:     rts
; credits after a continue: a best credit that died at this final boss gets the star, if the
; player is still in the game
game_star:
        tst.b   GCONT
        beq   .x
        move.b  CURAREA,d1
        addq.b  #1,d1
        lea     BESTA1,a0
        lea     P1_OBJ+$28,a1
        bsr   .p
        tst.b   PEND2P
        beq   .x
        lea     BESTA2,a0
        lea     P1_OBJ+64+$28,a1
.p:     move.b  (a0),d0
        andi.b  #AREA_MASK,d0
        cmp.b   d1,d0
        bne   .x
        cmpi.b  #DET_B,BESTD1-BESTA1(a0)
        bne   .x
        tst.b   PEND2P              ; 2 players: only one still playing
        beq   .s
        tst.w   (a1)
        beq   .x
.s:     move.b  #DET_STAR,BESTD1-BESTA1(a0)
.x:     rts
;============================================================================
        BLOCK hs_xtra3
; a1 = row: detail "1-1" (the default rows). Uses d0.
hs_one1:
        move.b  #1,XOFS(a1)
        jsr     hs_tag
        move.b  d0,XOFS+1(a1)
        rts
; after loading: default rows without a detail (saves from older versions) get "1-1"
hs_fixdefs:
        movem.l d1-d3/a0-a2,-(sp)
        lea     TABLE,a1
        bsr   .t
        lea     TABLE2,a1
        bsr   .t
        movem.l (sp)+,d1-d3/a0-a2
        rts
.t:     moveq   #9,d3
.r:     jsr     hs_det
        tst.b   d0
        bne   .nx
        lea     hs_default_tab,a0
        moveq   #9,d2
.d:     move.l  (a1),d0
        cmp.l   (a0),d0
        bne   .dn
        move.l  4(a1),d0
        cmp.l   4(a0),d0
        bne   .dn
        bsr   hs_one1
        bra   .nx
.dn:    addq.l  #8,a0
        dbra    d2,.d
.nx:    addq.l  #8,a1
        dbra    d3,.r
        rts

;============================================================================
        BLOCK hs_xtra2 LOW
; save copies: a1 = table <-> LINEBUF (10 x detail, tag). Uses d0/a1-a2.
xpack:  lea     LINEBUF,a2
        moveq   #9,d0
.p:     move.b  XOFS(a1),(a2)+
        move.b  XOFS+1(a1),(a2)+
        addq.l  #8,a1
        dbra    d0,.p
        rts
xunpack:
        lea     LINEBUF,a2
        moveq   #9,d0
.u:     move.b  (a2)+,XOFS(a1)
        move.b  (a2)+,XOFS+1(a1)
        addq.l  #8,a1
        dbra    d0,.u
        rts
; a0 = $200001: both tables' details from save RAM
sr_xall:
        lea     TABLE,a1
        lea     SR_XTAB*2(a0),a0
        bsr   sr_xget
        lea     TABLE2,a1
        lea     SR_XTAB2*2(a0),a0
; a1 = table, a0 = its details in save RAM -> the details (cleared if the copy is bad);
; a0 = $200001 after. Uses d0-d2/a2.
sr_xget:
        move.l  a1,-(sp)
        bsr   xclear
        movea.l a0,a1
        lea     LINEBUF,a2
        moveq   #19,d1
        jsr     sr_get
        movea.l (sp)+,a1
        bra   xunpack
; a0 = $200001: both tables' details to save RAM. Uses d0-d1/a1-a2.
sr_xput:
        lea     TABLE,a1
        lea     SR_XTAB*2(a0),a2
        bsr   .one
        lea     TABLE2,a1
        lea     SR_XTAB2*2(a0),a2
.one:   move.l  a2,-(sp)
        bsr   xpack
        movea.l (sp)+,a2
        lea     LINEBUF,a1
        moveq   #19,d1
        jmp     sr_put
; LINEBUF[0-19] = 0. Uses d0/a2.
xclear: lea     LINEBUF,a2
        moveq   #4,d0
.c:     clr.l   (a2)+
        dbra    d0,.c
        rts

;============================================================================
        BLOCK game_rules
; at the start of a game: anything set in the cheat menu, or a special mode -> no table
game_rules:
        st      GCHEAT
        tst.b   $FF36E0             ; special modes (title button combos)
        bne   .x
        tst.b   $FF0FED             ; cheat menu: seed
        bne   .x
        tst.b   $FF470D             ;   start area
        bne   .x
        tst.b   $FF0015             ;   infinite health
        bne   .x
        tst.b   $FF0001             ;   infinite continues
        bne   .x
        tst.b   $FF000C             ;   infinite ammo
        bne   .x
        tst.b   $FF014E             ;   infinite grenades
        bne   .x
        tst.b   $FF0000             ;   infinite dog tags
        bne   .x
        clr.b   GCHEAT
.x:     rts

;============================================================================
        BLOCK hs_attract
; idle on the title: the easy table, then the hard one (a button press skips back to the title)
hs_attract:
        move.b  #1,RUNNING
        move.w  #-1,NEWIDX
        clr.b   CURID
        jsr     hs_screen_on
        move.w  #ATTRACT_SHOW,d0
        jsr     hs_wait
        tst.w   TIMER
        bne   .x
        move.b  #1,CURID
        jsr     hs_screen_on
        move.w  #ATTRACT_SHOW,d0
        jsr     hs_wait
.x:     clr.b   CURID
        jmp     hs_screen_off

;============================================================================
        BLOCK hs_screen
; take over the display: clear planes/sprites/scroll, load palette + font, draw the table
hs_screen_on:
        movem.l d0-d7/a0-a6,-(sp)
        move.w  sr,-(sp)
        ori.w   #$0700,sr
        lea     VDP_CTRL,a5
        lea     VDP_DATA,a6
        lea     hs_vdpregs,a0       ; the title's layout (its init sets it again afterwards)
.r:     move.w  (a0)+,d0
        beq     .rd
        move.w  d0,(a5)
        bra     .r
.rd:    moveq   #0,d0
        move.l  #$60000003,(a5)     ; plane A $E000-$FFFF (128x32): clear logo/text layer
        move.w  #2047,d1
.v:     move.l  d0,(a6)
        dbra    d1,.v
        clr.l   SPRBUF              ; a sprite-table DMA queued by the title uploads this
        clr.l   SPRBUF+4
        move.l  #$7C000002,(a5)     ; sprite table $BC00: no sprites
        move.l  d0,(a6)
        move.l  d0,(a6)
        move.w  #$8F04,(a5)         ; line scroll table $B800: plane A entries = 0
        move.l  #$78000002,(a5)
        move.w  #223,d1
.h:     move.w  d0,(a6)
        dbra    d1,.h
        move.w  #$8F02,(a5)
        move.l  #$40000010,(a5)     ; VSRAM plane A
        move.w  d0,(a6)
        move.l  #$C0000000,(a5)     ; CRAM: title background palette + our 3 text palettes
        lea     TITLE_PAL_EASY,a0   ; each table on its difficulty's background
        tst.b   CURID
        beq   .pd
        lea     TITLE_PAL,a0
.pd:    moveq   #7,d1
.p0:    move.l  (a0)+,(a6)
        dbra    d1,.p0
        lea     hs_palette,a0
        moveq   #15,d1
.p:     move.l  (a0)+,(a6)
        dbra    d1,.p
        jsr     hs_font
        move.w  (sp)+,sr
        jsr     hs_draw_all
        move.w  #$8174,VDP_CTRL     ; display on
        movem.l (sp)+,d0-d7/a0-a6
        rts

;============================================================================
        BLOCK hs_screen_off
hs_screen_off:
        move.w  sr,-(sp)
        ori.w   #$0700,sr
        move.w  #$8174,VDP_CTRL     ; screens expect the display left on (palette black)
        lea     hs_regnums,a0       ; restore the VDP registers we changed from the game's
.r:     moveq   #0,d0               ; RAM copies ($FF4B26 + register number)
        move.b  (a0)+,d0
        bmi     .rd
        lea     $FF4B26,a1
        move.b  (a1,d0.w),d1
        lsl.w   #8,d0
        move.b  d1,d0
        ori.w   #$8000,d0
        move.w  d0,VDP_CTRL
        bra     .r
.rd:    move.l  #$C0000000,VDP_CTRL
        moveq   #31,d0
        moveq   #0,d1               ; (not clr.l: a 68000 CLR reads first, and reading the VDP
.c:     move.l  d1,VDP_DATA         ;  data port in write mode locks up a real console)
        dbra    d0,.c
        move.w  (sp)+,sr
        rts

;============================================================================
        BLOCK hs_font
; font glyphs $20-$5F -> tiles FONT_TILE.., then the custom glyphs over [ \ ]
hs_font:
        move.l  #$40000000|((FONT_TILE*32)&$3FFF)<<16|((FONT_TILE*32)>>14),(a5)
        lea     FONT,a0
        move.w  #64*16-1,d1
.f:     move.l  (a0)+,(a6)
        dbra    d1,.f
        move.l  #$40000000|(((FONT_TILE+(CH_HEART-$20)*2)*32)&$3FFF)<<16|(((FONT_TILE+(CH_HEART-$20)*2)*32)>>14),(a5)
        lea     hs_glyphs,a0
        moveq   #4*16-1,d1
.g:     move.l  (a0)+,(a6)
        dbra    d1,.g
        move.l  #$40000000|(((FONT_TILE+(CH_STAR-$20)*2)*32)&$3FFF)<<16|(((FONT_TILE+(CH_STAR-$20)*2)*32)>>14),(a5)
        moveq   #15,d1
.s:     move.l  (a0)+,(a6)          ; (the star follows the 4 glyphs)
        dbra    d1,.s
        rts

;============================================================================
        BLOCK draw_line
; a0 = string, d0 = column, d1 = row (8x16 text uses rows r and r+1), d3 = palette bits
draw_line:
        movem.l d0-d4/a0-a1,-(sp)
        move.w  sr,-(sp)
        ori.w   #$0700,sr
        moveq   #0,d4
.pass:  move.w  d1,d2
        add.w   d4,d2
        lsl.w   #7,d2
        add.w   d0,d2
        add.w   d2,d2
        addi.w  #PLANE_A,d2
        bsr   setvram
        movea.l a0,a1
.ch:    moveq   #0,d2
        move.b  (a1)+,d2
        beq   .eol
        subi.w  #$20,d2
        add.w   d2,d2
        add.w   d4,d2
        addi.w  #FONT_TILE,d2
        or.w    d3,d2
        move.w  d2,VDP_DATA
        bra   .ch
.eol:   addq.w  #1,d4
        cmpi.w  #2,d4
        bne   .pass
        move.w  (sp)+,sr
        movem.l (sp)+,d0-d4/a0-a1
        rts
; d2.w = VRAM address -> write command
setvram:
        andi.l  #$FFFF,d2
        lsl.l   #2,d2
        lsr.w   #2,d2
        swap    d2
        ori.l   #$40000000,d2
        move.l  d2,VDP_CTRL
        rts

;============================================================================
        BLOCK hs_draw_all
; header, 10 rows, footer
hs_draw_all:
        movem.l d0-d7/a0-a1,-(sp)
        jsr     hs_layout
        jsr     hs_title
        moveq   #0,d7
.r:     jsr     hs_row
        addq.w  #1,d7
        cmpi.w  #10,d7
        bne   .r
        jsr     hs_footer
        movem.l (sp)+,d0-d7/a0-a1
        rts

;============================================================================
        BLOCK hs_footer
; bottom line. Yellow = something to do (initials entry, the reset hint); white = information
; (EASY / HARD, which takes turns with the reset hint in the Options view: ALTLABEL)
hs_footer:
        movem.l d0-d3/a0-a1,-(sp)
        move.w  NEWIDX,d0
        bmi   .o
        cmpi.w  #3,ENTPOS
        bcc   .lab
        lea     str_enter,a0        ; initials entry (2-player game: which player)
        tst.b   PEND2P
        beq   .y
        lea     str_enter1,a0
        tst.b   ENTPAD
        beq   .y
        lea     str_enter2,a0
        bra   .y
.o:     addq.w  #1,d0
        beq   .lab
        tst.b   ALTLABEL            ; Options view (-2): the reset hint, or EASY / HARD
        bne   .lab
        lea     str_reset,a0
.y:     move.w  #PAL_YELLOW,d3
        bra   .f
.lab:   lea     str_easy,a0
        tst.b   CURID
        beq   .w
        lea     str_hard,a0
.w:     move.w  #PAL_WHITE,d3
.f:     moveq   #0,d0
        moveq   #25,d1
        jsr     draw_line
        movem.l (sp)+,d0-d3/a0-a1
        rts

;============================================================================
        BLOCK hs_layout
; row: rank (5-8), score (to 19), area (22.., AREAW wide: "1", "12", ALL / 1CC), initials
; (24+AREAW..). The area column is as wide as its widest entry and the rows are centred on
; what they hold.
hs_layout:
        movem.l d4-d5,-(sp)
        jsr     hs_tabptr
        moveq   #1,d4
        moveq   #9,d5
.t:     move.b  7(a1),d2
        andi.b  #AREA_MASK,d2
        moveq   #1,d3
        cmpi.b  #10,d2
        bcs   .a
        moveq   #2,d3
        cmpi.b  #AREA_ALL,d2
        bcs   .a
        moveq   #3,d3
        bra   .w
.a:     tst.b   d2
        beq   .w
        jsr     hs_det              ; "-n", "-nn", "-B", "-*"
        tst.b   d0
        beq   .w
        addq.w  #2,d3
        cmpi.b  #10,d0
        bcs   .w
        cmpi.b  #DET_B,d0
        bcc   .w
        addq.w  #1,d3
.w:     cmp.w   d3,d4
        bcc   .n
        move.w  d3,d4
.n:     addq.l  #8,a1
        dbra    d5,.t
        move.w  d4,d0
        movem.l (sp)+,d4-d5
        move.b  d0,AREAW
        neg.w   d0                  ; columns 5 to 26+AREAW, centred under the title: (18 - AREAW) / 2 - 6
        addi.w  #18,d0
        asr.w   #1,d0
        subq.w  #6,d0
        move.w  d0,HSCOL
        rts
; a0 = LINEBUF -> a2 = the initials field (column 24 + AREAW)
hs_inifld:
        moveq   #24,d0
        add.b   AREAW,d0
        lea     0(a0,d0.w),a2
        rts

;============================================================================
        BLOCK hs_title
; table title (with an arrow towards the other table in the Options view)
hs_title:
        lea     str_top,a0
        movea.l a0,a1               ; centre it
        moveq   #40,d0
.l:     tst.b   (a1)+
        beq   .c
        subq.w  #1,d0
        bra   .l
.c:     lsr.w   #1,d0
        moveq   #1,d1
        move.w  #PAL_WHITE,d3
        jsr     draw_line
        cmpi.w  #-2,NEWIDX          ; Options view: an arrow towards the other table
        bne   .r
        lea     str_right,a0        ; first table shown: top right (inside the TV-safe area)
        moveq   #36,d0
        move.b  CURID,d3
        cmp.b   DIFFICULTY,d3       ; (the first is the one for the difficulty set)
        beq   .ar
        lea     str_left,a0         ; second: top left
        moveq   #3,d0
.ar:    move.w  #PAL_YELLOW,d3
        jsr     draw_line
.r:     rts

;============================================================================
        BLOCK hs_row
; draw table row d7 (0-9). The row being entered is yellow, with a blinking cursor.
hs_row:
        movem.l d0-d7/a0-a1,-(sp)
        jsr     hs_format_row       ; -> LINEBUF, a1 = entry
        move.w  #PAL_WHITE,d3
        cmp.w   NEWIDX,d7
        bne   .draw
        move.w  #PAL_YELLOW,d3
        lea     LINEBUF,a0          ; initials field
        jsr     hs_inifld
        movea.l a2,a0
        moveq   #0,d0
.u:     cmp.w   ENTPOS,d0           ; slots past the cursor: underscore
        bls   .n
        move.b  #'-',(a0,d0.w)
.n:     addq.w  #1,d0
        cmpi.w  #3,d0
        bne   .u
        move.w  ENTPOS,d0
        cmpi.w  #3,d0
        bcc   .draw
        move.b  #' ',(a0,d0.w)      ; cursor: current choice, blinking
        btst    #4,FRAMES+1
        bne   .draw
        move.w  ENTCHR,d1
        lea     hs_charset,a1
        move.b  (a1,d1.w),(a0,d0.w)
.draw:  lea     LINEBUF,a0
        move.w  HSCOL,d0
        bpl   .c
        suba.w  d0,a0               ; (left of column 0: start one character in)
        moveq   #0,d0
.c:
        move.w  d7,d1
        add.w   d1,d1
        addq.w  #4,d1               ; rows 4,6,...,22
        jsr     draw_line
        movem.l (sp)+,d0-d7/a0-a1
        rts

;============================================================================
        BLOCK hs_area
; hs_format_row: the area, right-aligned to column 21+AREAW (d2 = row byte, a0 = LINEBUF)
hs_area:
        moveq   #0,d1
        move.b  AREAW,d1
        lea     22(a0,d1.w),a2      ; just past its last column
        andi.b  #AREA_MASK,d2
        tst.b   d2
        beq   .x
        cmpi.b  #AREA_ALL,d2
        bne   .c
        move.b  #'L',-(a2)
        move.b  #'L',-(a2)
        move.b  #'A',-(a2)
        rts
.c:     cmpi.b  #AREA_1CC,d2
        bne   .n
        move.b  #'C',-(a2)
        move.b  #'C',-(a2)
        move.b  #'1',-(a2)
        rts
.n:     jsr     hs_det              ; a detail: "-n", "-nn", "-B" or "-*" first
        tst.b   d0
        beq   .nd
        cmpi.b  #DET_B,d0
        bcs   .rm
        bne   .st
        move.b  #'B',-(a2)
        bra   .ds
.st:    move.b  #CH_STAR,-(a2)
        bra   .ds
.rm:    andi.l  #$FF,d0
        divu    #10,d0
        swap    d0
        addi.b  #'0',d0
        move.b  d0,-(a2)
        swap    d0
        tst.w   d0
        beq   .ds
        addi.b  #'0',d0
        move.b  d0,-(a2)
.ds:    move.b  #'-',-(a2)
.nd:    andi.l  #$FF,d2
        divu    #10,d2              ; 1-29
        swap    d2
        addi.b  #'0',d2
        move.b  d2,-(a2)
        swap    d2
        tst.w   d2
        beq   .x
        addi.b  #'0',d2
        move.b  d2,-(a2)
.x:     rts

;============================================================================
        BLOCK hs_format_row
; LINEBUF <- "     1ST   512,000  3  BIT" for row d7; a1 = entry
hs_format_row:
        lea     LINEBUF,a0
        moveq   #39,d0
.sp:    move.b  #' ',(a0)+
        dbra    d0,.sp
        clr.b   (a0)
        lea     LINEBUF,a0
        ; rank, right-aligned to column 8
        move.w  d7,d0
        add.w   d0,d0
        lea     rank_sfx,a1
        move.b  (a1,d0.w),7(a0)
        move.b  1(a1,d0.w),8(a0)
        move.w  d7,d0
        addq.w  #1,d0
        cmpi.w  #10,d0
        bne   .one
        move.b  #'1',5(a0)
        moveq   #0,d0
.one:   addi.b  #'0',d0
        move.b  d0,6(a0)
        ; entry
        move.w  d7,d0
        lsl.w   #3,d0
        jsr     hs_tabptr
        adda.w  d0,a1
        jsr     hs_inifld
        move.b  4(a1),(a2)+
        move.b  5(a1),(a2)+
        move.b  6(a1),(a2)
        move.b  7(a1),d2
        jsr     hs_area
        ; score, right-aligned to column 19
        movem.l d7/a1,-(sp)
        move.l  (a1),d0
        moveq   #1,d3
        jsr     fmtnum              ; a0 = end of NUMBUF data
        lea     LINEBUF+20,a1
        lea     NUMBUF,a2
.cp:    cmpa.l  a2,a0
        beq   .done
        move.b  -(a0),d0
        addi.b  #'0',d0
        cmpi.b  #'0'+10,d0
        bne   .dg
        move.b  #',',d0
.dg:    move.b  d0,-(a1)
        bra   .cp
.done:  movem.l (sp)+,d7/a1
        rts

;============================================================================
        BLOCK hs_entry
; initials entry for row NEWIDX
hs_entry:
        clr.w   ENTPOS
        clr.w   ENTCHR
        clr.w   FRAMES
        clr.w   REPT
        move.w  #ENTRY_TIME,TIMER
        move.w  PAD1,PADOLD
        tst.b   ENTPAD
        beq   .p
        move.w  PAD2,PADOLD
.p:
.loop:  jsr     hs_frame
        addq.w  #1,FRAMES
        subq.w  #1,TIMER
        beq   .done
        move.w  PRESSED,d1
        btst    #7,d1               ; START: done
        bne   .done
        jsr     hs_updown           ; d1 preserved
        andi.w  #$70,d1             ; A/B/C: confirm
        beq   .draw
        move.w  #SFX_OK,d0
        jsr     hs_sfx
        jsr     hs_confirm
        tst.w   d0
        bne   .done
.draw:  move.w  NEWIDX,d7
        jsr     hs_row
        jsr     hs_timer
        bra   .loop
.done:  jsr     hs_blank
        move.w  #3,ENTPOS
        rts

;============================================================================
        BLOCK hs_updown
; up/down with auto-repeat: change the current character. d1 = PRESSED (kept)
hs_updown:
        move.w  HELD,d2
        andi.w  #3,d2
        beq     .x
        move.w  d1,d3
        andi.w  #3,d3
        beq     .rep
        move.w  #16,REPT
        bra     .move
.rep:   subq.w  #1,REPT
        bne     .x
        move.w  #4,REPT
.move:  move.w  ENTCHR,d0
        btst    #0,d2               ; up = next
        beq     .dn
        addq.w  #1,d0
        cmpi.w  #NCHARS,d0
        bne     .set
        moveq   #0,d0
        bra     .set
.dn:    subq.w  #1,d0
        bpl     .set
        moveq   #NCHARS-1,d0
.set:   move.w  d0,ENTCHR
.x:     rts

;============================================================================
        BLOCK hs_blank
; nothing entered: initials "68K" (the game's original default high score)
hs_blank:
        tst.w   ENTPOS
        bne     .k
        move.w  NEWIDX,d0
        lsl.w   #3,d0
        jsr     hs_tabptr
        lea     4(a1),a0
        move.b  #'6',0(a0,d0.w)
        move.b  #'8',1(a0,d0.w)
        move.b  #'K',2(a0,d0.w)
.k:     rts

;============================================================================
        BLOCK hs_confirm
; apply the current choice; d0 = 1 when entry is finished
hs_confirm:
        move.w  NEWIDX,d0
        lsl.w   #3,d0
        jsr     hs_tabptr
        lea     4(a1,d0.w),a0       ; initials of the new row
        move.w  ENTCHR,d0
        lea     hs_charset,a1
        move.b  (a1,d0.w),d0
        move.w  ENTPOS,d1
        cmpi.b  #CH_END,d0
        beq   .fin
        cmpi.b  #CH_BACK,d0
        bne   .put
        tst.w   d1                  ; back: previous slot
        beq   .no
        subq.w  #1,d1
        move.w  d1,ENTPOS
        move.b  #' ',(a0,d1.w)
.no:    moveq   #0,d0
        rts
.put:   move.b  d0,(a0,d1.w)
        addq.w  #1,d1
        move.w  d1,ENTPOS
        cmpi.w  #3,d1
        beq   .fin
        moveq   #0,d0
        rts
.fin:   moveq   #1,d0
        rts

;============================================================================
        BLOCK hs_misc
; wait one frame and read player 1's pad
hs_frame:
        jsr     ORIG_VSYNC
        move.w  PAD1,d0
        tst.b   ENTPAD              ; player 2 entering: pad 2
        beq   .p
        move.w  PAD2,d0
.p:
        move.w  PADOLD,d1
        move.w  d0,PADOLD
        move.w  d0,HELD
        not.w   d1
        and.w   d0,d1
        move.w  d1,PRESSED
        rts
; show for d0 frames, or until START/A/B/C
hs_wait:
        move.w  d0,TIMER
        move.w  PAD1,PADOLD
.w:     jsr     hs_frame
        move.w  PRESSED,d0
        andi.w  #$F0,d0
        bne   .x
        subq.w  #1,TIMER
        bne   .w
.x:     rts
; play UI sound d0
hs_sfx:
        movem.l d0-d7/a0-a6,-(sp)
        ext.l   d0
        move.l  d0,-(sp)
        jsr     SFX
        addq.l  #4,sp
        movem.l (sp)+,d0-d7/a0-a6
        rts
; seconds left, bottom right
hs_timer:
        moveq   #0,d0
        move.w  TIMER,d0
        divu    #60,d0
        andi.l  #$FFFF,d0
        moveq   #0,d3
        jsr     fmtnum
        lea     LINEBUF,a1
        move.b  #' ',(a1)
        move.b  #' ',1(a1)
        clr.b   2(a1)
        lea     NUMBUF,a2
        lea     LINEBUF+2,a1
.c:     cmpa.l  a2,a0
        beq   .d
        move.b  -(a0),d0
        addi.b  #'0',d0
        move.b  d0,-(a1)
        bra   .c
.d:     lea     LINEBUF,a0
        moveq   #29,d0
        tst.b   PEND2P              ; "1P/2P ENTER YOUR INITIALS" is 3 longer, centred
        beq   .e
        moveq   #31,d0
.e:     moveq   #25,d1
        move.w  #PAL_YELLOW,d3
        jmp     draw_line

;============================================================================
        BLOCK sram LOW
; Save memory ($200001.., odd bytes) is switched in with $A130F1 and overlaps the upper
; 2MB of ROM, so this block lives below $200000 and the Z80 is held off the bus.
; Uses d0 (both callers save it).
sram_on:
        move.w  #$100,$A11100       ; Z80 bus request,
        move.w  #$100,$A11200       ;  with the Z80 out of reset (as the game always does)
        move.w  #$3FFF,d0           ; wait for the bus, but never forever (~60 ms at most)
.w:     btst    #0,$A11100
        dbeq    d0,.w
        move.b  #1,$A130F1
        lea     $200001,a0
        rts
sram_off:
        move.b  #0,$A130F1
        move.w  #0,$A11100
        rts

;============================================================================
        BLOCK sram_ld LOW
; detect + load (keeps defaults if there is no valid save)
sram_load:
        movem.l d0-d2/a0-a2,-(sp)
        move.w  sr,-(sp)
        ori.w   #$0700,sr
        jsr     sram_on
        move.b  #$5A,SR_TEST*2(a0)
        cmpi.b  #$5A,SR_TEST*2(a0)
        bne   .out
        move.b  #$A5,SR_TEST*2(a0)
        cmpi.b  #$A5,SR_TEST*2(a0)
        bne   .out
        st      SRAM_OK
        cmpi.b  #'X',(a0)
        bne   .out
        cmpi.b  #'C',2(a0)
        bne   .out
        cmpi.b  #'H',4(a0)
        bne   .out
        lea     SR_OPTS*2(a0),a1
        lea     OPTS,a2
        moveq   #OPTS_LEN-1,d1
        bsr   sr_get
        move.b  SR_EXTRA*2(a0),d0   ; cutscene voices (Options > Audio, with MD+)
        move.b  SR_EXTRA*2+2(a0),d1
        eori.b  #$5A,d1
        cmp.b   d0,d1
        bne   .nx
        cmpi.b  #3,d0
        bcc   .nx
        move.b  d0,CSV
.nx:    cmpi.b  #SR_VERSION,6(a0)   ; tables: only in this version's format
        bne   .out
        lea     SR_TABLE*2(a0),a1
        lea     TABLE,a2
        moveq   #79,d1
        bsr   sr_get
        lea     SR_TABLE2*2(a0),a1
        lea     TABLE2,a2
        moveq   #79,d1
        bsr   sr_get
        jsr     sr_xall             ; the rows' details (none in older saves)
.out:   jsr     sram_off
        move.w  (sp)+,sr
        movem.l (sp)+,d0-d2/a0-a2
        rts
; copy d1+1 bytes from save (a1) to RAM (a2) if the checksum byte after them matches
sr_get: movea.l a1,a0
        move.w  d1,d2
        moveq   #0,d0
.s:     add.b   (a0),d0
        addq.l  #2,a0
        dbra    d2,.s
        cmp.b   (a0),d0
        bne   .x
.c:     move.b  (a1),(a2)+
        addq.l  #2,a1
        dbra    d1,.c
.x:     lea     $200001,a0
        rts

;============================================================================
        BLOCK sram_sv LOW
sram_save:
        movem.l d0-d2/a0-a2,-(sp)
        jsr     opts_capture        ; (kept in RAM too: a soft reset reuses it)
        tst.b   SRAM_OK
        beq   .y
        move.w  sr,-(sp)
        ori.w   #$0700,sr
        jsr     sram_on
        move.b  #'X',(a0)
        move.b  #'C',2(a0)
        move.b  #'H',4(a0)
        move.b  #SR_VERSION,6(a0)
        lea     TABLE,a1
        lea     SR_TABLE*2(a0),a2
        moveq   #79,d1
        bsr   sr_put
        lea     OPTS,a1
        lea     SR_OPTS*2(a0),a2
        moveq   #OPTS_LEN-1,d1
        bsr   sr_put
        move.b  CSV,d0
        move.b  d0,SR_EXTRA*2(a0)
        eori.b  #$5A,d0
        move.b  d0,SR_EXTRA*2+2(a0)
        lea     TABLE2,a1
        lea     SR_TABLE2*2(a0),a2
        moveq   #79,d1
        bsr   sr_put
        jsr     sr_xput
        jsr     sram_off
        move.w  (sp)+,sr
.y:     movem.l (sp)+,d0-d2/a0-a2
        rts
; write d1+1 bytes from RAM (a1) to save (a2), then their checksum
sr_put: moveq   #0,d0
.c:     move.b  (a1),(a2)
        add.b   (a1)+,d0
        addq.l  #2,a2
        dbra    d1,.c
        move.b  d0,(a2)
        rts

;============================================================================
        BLOCK opts
; boot: restore saved options (after the game's defaults; controls come later)
opts_apply:
        cmpi.b  #'O',OPTS
        bne   .x
        move.b  OPTS+1,LANGUAGE
        move.b  OPTS+2,DIFFICULTY
        move.b  OPTS+3,MUSIC_ON
        move.b  OPTS+4,SOUNDS_ON
        cmpi.b  #3,OPTS+7
        bcc   .x
        move.b  OPTS+7,ROLLMODE
.x:     rts
; after a screen returns (d2 = screen*4): leaving language select / options saves them
opts_after:
        cmpi.w  #2*4,d2
        beq   .s
        cmpi.w  #8*4,d2
        bne   .x
.s:     jsr     sram_save
        move.l  d0,-(sp)            ; (d0 = the screen's result: the next screen)
        jsr     hs_sync             ; the game's high score: the difficulty may have changed
        move.l  (sp)+,d0
.x:     rts
opts_capture:
        lea     OPTS,a0
        move.b  #'O',(a0)+
        move.b  LANGUAGE,(a0)+
        move.b  DIFFICULTY,(a0)+
        move.b  MUSIC_ON,(a0)+
        move.b  SOUNDS_ON,(a0)+
        move.b  PADTYPE1,(a0)+
        move.b  PADTYPE2,(a0)+
        move.b  ROLLMODE,(a0)+
        lea     CTRL,a1
        moveq   #9,d0
.c:     move.b  (a1)+,(a0)+
        dbra    d0,.c
        rts
;============================================================================
        BLOCK opts_skip
; in place of the boot language screen (its init has run): d0 = 0 not skipped, else next screen
opts_skip_lang:
        moveq   #0,d0
        tst.b   LANGSEEN
        bne   .x
        st      LANGSEEN
        cmpi.b  #'O',OPTS
        bne   .x
        movem.l d2-d3/a2,-(sp)
        jsr     $8CFF4              ; what the screen does on exit: fade out,
        jsr     opts_ctrl           ; controller defaults,
        jsr     free_objs           ; free its objects,
        move.w  $FF35FE,d1          ; and seed the random number generator
        move.w  $C00008,d2          ; (from the HV counter; it stays 0 otherwise)
        move.w  d1,d0
        lsr.w   #1,d0
        eor.w   d2,d0
        eor.w   d1,d0
        move.w  d0,d1
        add.w   d1,d1
        eor.w   d1,d0
        move.w  d0,$FF35FE
        moveq   #0,d1
        move.b  $FF3304,d1
        add.l   d1,d1
        lea     $3FC536,a0
        move.w  0(a0,d1.l),d1
        cmp.w   d1,d0
        bne   .m
        move.w  #$1337,d1
        moveq   #0,d0
.m:     eor.w   d0,d1
        move.w  d1,$FF1602
        movem.l (sp)+,d2-d3/a2
        moveq   #3,d0               ; ... and go on to screen 3
.x:     rts

;============================================================================
        BLOCK opts_ctrl
; free the screen's objects (cursor etc.) as screens do when they exit (d0-d1/a0-a1 used)
free_objs:
        move.l  a2,-(sp)
        lea     $FF2C8C,a2
.f:     move.l  (a2),d0
        beq   .n
        move.l  d0,-(sp)
        jsr     $504BA
        addq.l  #4,sp
        clr.l   (a2)
.n:     addq.l  #4,a2
        cmpa.l  #$FF2CB0,a2
        bne   .f
        jsr     $4FD64
        jsr     $50360
        movea.l (sp)+,a2
        rts
; controller configs: the saved ones if the pad type matches, else the game's defaults
opts_ctrl:
        lea     CTRL,a0
        move.b  PADTYPE1,d0
        cmp.b   OPTS+5,d0
        bne   .d1
        move.b  OPTS+8+1,1(a0)
        move.w  OPTS+8+4,4(a0)
        move.w  OPTS+8+8,8(a0)
        bra   .p2
.d1:    bsr   .def
        move.b  d1,1(a0)
        move.w  d2,4(a0)
        move.w  d3,8(a0)
.p2:    move.b  PADTYPE2,d0
        cmp.b   OPTS+6,d0
        bne   .d2
        move.b  OPTS+8,(a0)
        move.w  OPTS+8+2,2(a0)
        move.w  OPTS+8+6,6(a0)
        rts
.d2:    bsr   .def
        move.b  d1,(a0)
        move.w  d2,2(a0)
        move.w  d3,6(a0)
        rts
.def:   moveq   #0,d1               ; the game's defaults: 3-button config 0, 6-button config 2
        moveq   #$20,d2
        moveq   #$40,d3
        cmpi.b  #1,d0
        bne   .r
        moveq   #2,d1
        move.w  #$100,d2
        moveq   #$20,d3
.r:     rts
;============================================================================
        BLOCK opt_menu
; Options screen: LANGUAGE (with the language shown) and CONTROLS swap rows; "CANCEL RULES"
; at row 17 (index 4), HIGH SCORES row 19 (index 5), BACK row 21 (index 6)
DRAWTEXT    equ $51686          ; (string, x.l, y.l)
OPT_LOOP    equ $37854          ; options loop: next frame
; from the options init (replaces "move.w $FF4FB4,d0" at $372FC)
opt_draw:
        movem.l d0-d1/a0-a1,-(sp)
        jsr     opt_lang            ; d0 = language * 4
        lea     lng_cancel,a0
        pea     17.w
        pea     5.w
        move.l  0(a0,d0.w),-(sp)
        jsr     DRAWTEXT
        jsr     opt_lang
        lea     lng_hs,a0
        pea     19.w
        pea     5.w
        move.l  0(a0,d0.w),-(sp)
        jsr     DRAWTEXT
        lea     24(sp),sp
        jsr     opt_val
        jsr     opt_lname
        movem.l (sp)+,d0-d1/a0-a1
        move.w  $FF4FB4,d0
        rts
opt_val:
        moveq   #0,d0
        move.b  ROLLMODE,d0
        mulu    #11,d0
        lea     str_modes,a0
        adda.w  d0,a0
        cmpi.b  #2,ROLLMODE         ; MODERN: translated
        bne   .p
        jsr     opt_lang
        lea     lng_modern,a0
        movea.l 0(a0,d0.w),a0
.p:     pea     17.w
        pea     25.w
        move.l  a0,-(sp)
        jsr     DRAWTEXT
        lea     12(sp),sp
        rts
;============================================================================
        BLOCK opt_confirm
; replaces the options loop's "A/START pressed? BACK?" check at $378C8 (d0 = pressed, d3 = index)
opt_confirm:
        cmpi.w  #4,d3
        bne   .n
        andi.w  #$CC,d0             ; left / right / A / START cycle the mode
        beq   .loop
        moveq   #1,d1
        btst    #2,d0
        beq   .a
        moveq   #2,d1
.a:     add.b   ROLLMODE,d1
        cmpi.b  #3,d1
        bcs   .s
        subq.b  #3,d1
.s:     move.b  d1,ROLLMODE
        pea     $6F.w
        jsr     SFX
        addq.l  #4,sp
        jsr     opt_val
.loop:  jmp     OPT_LOOP
.n:     andi.w  #$C0,d0
        beq   .loop
        cmpi.w  #6,d3
        beq   .back
        cmpi.w  #5,d3
        bne   .o
        jmp     opt_hs_go
.o:     cmpi.w  #2,d3               ; LANGUAGE now shows above CONTROLS: index 2 runs the
        bne   .o3                   ; game's item 3 and 3 runs item 2 (opt_reent swaps the
        move.w  #3,$FF10BA          ; cursor back on return)
        bra   .o1
.o3:    cmpi.w  #3,d3
        bne   .o1
        move.w  #2,$FF10BA
.o1:    jmp     $378D6              ; AUDIO / LANGUAGE / CONTROLS
.back:  pea     $6C.w               ; BACK, as the original did for index 4
        jsr     SFX
        addq.l  #4,sp
        moveq   #5,d0
        move.w  d0,$FF3410
        jmp     $378F0

;============================================================================
        BLOCK opt_menu3
; LANGUAGE's row shows the language, as DIFFICULTY does its setting: the name from the
; language's own string table (entry $178, the language screen's), right-aligned to col 34
opt_lname:
        moveq   #0,d0
        move.b  $FF1608,d0
        cmpi.b  #8,d0
        bcs   .k
        moveq   #0,d0
.k:     lsl.w   #2,d0
        lea     $3F7528,a0
        movea.l 0(a0,d0.w),a0
        movea.l $178(a0),a0
        movea.l a0,a1
        moveq   #35,d1
.n:     tst.b   (a1)+
        beq   .d
        subq.w  #1,d1
        bra   .n
.d:     pea     13.w
        move.l  d1,-(sp)
        move.l  a0,-(sp)
        jsr     DRAWTEXT
        lea     12(sp),sp
        rts
; options init, coming back from a sub-screen: the cursor index the game left (CONTROLS 2,
; LANGUAGE 3) to their new rows (replaces "move.w $FF10BA,d0" at $373AA)
opt_reent:
        move.w  $FF10BA,d0
        cmpi.w  #2,d0
        beq   .to3
        cmpi.w  #3,d0
        bne   .x
        moveq   #2,d0
        bra   .s
.to3:   moveq   #3,d0
.s:     move.w  d0,$FF10BA
.x:     rts

;============================================================================
        BLOCK aud_menu
; Options > AUDIO with MD+ voices (Voices patch present and MD+ found): two added items,
; CUTSCENE VOICES (row 13) and CD VOICE (row 21); BGM / SE / VOICE / BACK move to rows
; 15 / 17 / 19 / 23. The game's own items keep their indices (0-5); the added ones are
; "between" them (AUD_X), handled here. Without MD+ the screen is the game's.
AUD_LOOP    equ $2DE32          ; audio loop: end of frame
AUD_EXIT    equ $2E496          ; leave the screen (as B/C does)
AUD_GAME    equ $2DDC6          ; the game's handling, UP pressed
AUD_DOWN    equ $2E4EA          ; ... not UP
AUD_RELD    equ $2E4CC          ; ... reload the index and place the cursor
; row of game item d0 (replaces "add.w d0,d0 / addi.w #9,d0"; d0's low byte = index)
aud_row0:
        cmpi.b  #1,MDP_ON
        bne   .id
        move.b  aud_rows(pc,d0.w),d0
        andi.w  #$FF,d0
        rts
.id:    add.w   d0,d0
        addi.w  #9,d0
        rts
aud_row1:
        cmpi.b  #1,MDP_ON
        bne   .id
        move.b  aud_rows(pc,d1.w),d1
        andi.w  #$FF,d1
        rts
.id:    add.w   d1,d1
        addi.w  #9,d1
        rts
aud_rows:   dc.b    9,11,15,17,19,23
; cursor y for game item d4 (replaces "lsl.w #4,d4 / addi.w #$C7,d4")
aud_cy4:
        cmpi.b  #1,MDP_ON
        bne   .id
        move.b  aud_rows(pc,d4.w),d4
        andi.w  #$FF,d4
        subi.w  #9,d4
        lsl.w   #3,d4
        addi.w  #$C7,d4
        rts
.id:    lsl.w   #4,d4
        addi.w  #$C7,d4
        rts
;============================================================================
        BLOCK aud_menu1
; the frame's input (replaces "btst #0,d1 / beq.w $2E4EA" at $2DDBE; d1 = pressed,
; d0 = the move repeat timer, a3 = object pointers, a6 = SFX)
aud_in:
        cmpi.b  #1,MDP_ON
        bne   .orig
        tst.b   AUD_X
        bne   aud_ext
        tst.w   d0                  ; (moves wait for the repeat timer, as the game's)
        bne   .orig
        move.w  $FF10BA,d4
        btst    #0,d1               ; up from BGM / BACK: onto an added item
        beq   .dn
        cmpi.w  #2,d4
        beq   .to1
        cmpi.w  #5,d4
        beq   .to2
        bra   .orig
.dn:    btst    #1,d1               ; down from SOUNDS / VOICE
        beq   .orig
        cmpi.w  #1,d4
        beq   .to1
        cmpi.w  #4,d4
        beq   .to2
.orig:  btst    #0,d1
        beq   .d
        jmp     AUD_GAME
.d:     jmp     AUD_DOWN
.to1:   move.b  #1,AUD_X
        bra   .mv
.to2:   move.b  #2,AUD_X
.mv:    jsr     aud_move
        jmp     AUD_LOOP
; move sound, repeat timer, cursor on the added item
aud_move:
        pea     $6E.w
        jsr     (a6)
        addq.l  #4,sp
        move.w  #$14,$FF36D0
        movea.l (a3),a0
        moveq   #13,d4
        cmpi.b  #1,AUD_X
        beq   .r
        moveq   #21,d4
.r:     subi.w  #9,d4
        lsl.w   #3,d4
        addi.w  #$C7,d4
        move.w  #$90,$18(a0)
        move.w  d4,$1A(a0)
        ori.w   #2,(a0)
        rts

;============================================================================
        BLOCK aud_menu2
; input with the cursor on an added item
aud_ext:
        move.w  d1,d4
        andi.w  #$30,d4             ; B / C: leave, as on the game's items
        beq   .k
        clr.b   AUD_X
        jmp     AUD_EXIT
.k:     tst.w   d0
        bne   .tl
        moveq   #0,d4
        btst    #0,d1               ; up: back onto SOUNDS / VOICE
        beq   .dn
        moveq   #1,d4
        cmpi.b  #1,AUD_X
        beq   .go
        moveq   #4,d4
        bra   .go
.dn:    btst    #1,d1               ; down: BGM / BACK
        beq   .tl
        moveq   #2,d4
        cmpi.b  #1,AUD_X
        beq   .go
        moveq   #5,d4
.go:    move.w  d4,$FF10BA
        clr.b   AUD_X
        pea     $6E.w
        jsr     (a6)
        addq.l  #4,sp
        move.w  #$14,$FF36D0
        jmp     AUD_RELD
.tl:    jmp     aud_lr
;============================================================================
        BLOCK aud_menu2b
aud_lr: cmpi.b  #1,AUD_X
        bne   .cd
        move.w  d1,d4               ; CUTSCENE VOICES: left = back, right / A / START = on
        andi.w  #$CC,d4
        beq   .x
        moveq   #1,d4
        btst    #2,d1
        beq   .c1
        moveq   #2,d4
.c1:    add.b   CSV,d4
        cmpi.b  #3,d4
        bcs   .c2
        subq.b  #3,d4
.c2:    move.b  d4,CSV
        pea     $6F.w
        jsr     (a6)
        addq.l  #4,sp
        jsr     aud_vcsv
        bra   .x
.cd:    moveq   #0,d4               ; CD VOICE: left / right = track, A / START = play it
        move.b  CDTRK,d4
        btst    #2,d1
        beq   .r
        subq.b  #1,d4
        bne   .s
        moveq   #85,d4
        bra   .s
.r:     btst    #3,d1
        beq   .a
        addq.b  #1,d4
        cmpi.b  #85,d4
        bls   .s
        moveq   #1,d4
.s:     move.b  d4,CDTRK
        pea     $6E.w
        jsr     (a6)
        addq.l  #4,sp
        jsr     aud_vcd
        bra   .x
.a:     andi.w  #$C0,d1
        beq   .x
        move.b  d4,MDP_REQ
.x:     jmp     AUD_LOOP

;============================================================================
        BLOCK aud_menu3
; screen drawn (replaces "move.w $FF4FB4,d0" at $2DBBC): with MD+, the added items and the
; game's lower ones on their new rows
aud_draw:
        movem.l d0-d2/a0-a2,-(sp)
        clr.b   AUD_X
        cmpi.b  #1,MDP_ON
        bne   .x
        move.b  CDTRK,d0
        beq   .t0
        cmpi.b  #85,d0
        bls   .t1
.t0:    move.b  #1,CDTRK
.t1:    moveq   #13,d2              ; clear rows 13-19 (the game's BGM, SE, VOICE, BACK)
.cl:    move.l  d2,d1
        jsr     aud_blank
        addq.w  #2,d2
        cmpi.w  #19,d2
        bls   .cl
        lea     aud_s_csv,a0
        moveq   #13,d1
        jsr     aud_label
        jsr     aud_vcsv
        move.w  #$13C,d0            ; BGM, SE, VOICE: the game's labels and values
        moveq   #15,d1
        jsr     aud_glabel
        lea     $21A3F8,a1
        move.b  $FF0472,d0
        moveq   #15,d1
        jsr     aud_gval
        move.w  #$140,d0
        moveq   #17,d1
        jsr     aud_glabel
        lea     $1643F4,a1
        move.b  $FF0471,d0
        moveq   #17,d1
        jsr     aud_gval
        move.w  #$144,d0
        moveq   #19,d1
        jsr     aud_glabel
        lea     $3AC38C,a1
        move.b  $FF0470,d0
        moveq   #19,d1
        jsr     aud_gval
        lea     aud_s_cd,a0
        moveq   #21,d1
        jsr     aud_label
        jsr     aud_vcd
        move.w  #$20C,d0            ; BACK
        moveq   #23,d1
        jsr     aud_glabel
.x:     movem.l (sp)+,d0-d2/a0-a2
        move.w  $FF4FB4,d0
        rts

;============================================================================
        BLOCK aud_menu4
; text helpers: DRAWTEXT(string, x, y)
aud_label:                          ; a0 = string, d1 = row, at column 5
        moveq   #5,d0
aud_text:                           ; a0 = string, d0 = column, d1 = row
        movem.l d0-d1/a0-a1,-(sp)
        move.l  d1,-(sp)
        move.l  d0,-(sp)
        move.l  a0,-(sp)
        jsr     DRAWTEXT
        lea     12(sp),sp
        movem.l (sp)+,d0-d1/a0-a1
        rts
aud_right:                          ; a0 = string, d1 = row: right-aligned to column 34, as the game
        movea.l a0,a1
        moveq   #35,d0
.n:     tst.b   (a1)+
        beq   aud_text
        subq.w  #1,d0
        bra   .n
aud_blank:                          ; d1 = row: blank columns 5-36
        lea     aud_s_sp,a0
        bra   aud_label
aud_glabel:                         ; d0.w = offset in the language's string table, d1 = row
        moveq   #0,d2
        move.b  $FF1608,d2
        lsl.w   #2,d2
        lea     $3F7528,a0
        movea.l 0(a0,d2.w),a0
        movea.l 0(a0,d0.w),a0
        bra   aud_label
aud_gval:                           ; a1 = the game's name table, d0.b = entry, d1 = row
        andi.w  #$FF,d0
        lsl.w   #2,d0
        movea.l 0(a1,d0.w),a0
        bra   aud_right
aud_s_sp:   dc.b    '                                ',0
aud_s_csv:  dc.b    'CUTSCENE VOICES',0
aud_s_cd:   dc.b    'CD VOICE',0
        even

;============================================================================
        BLOCK aud_menu5
; values of the added items, redrawn
aud_vcsv:
        movem.l d0-d1/a0-a1,-(sp)
        lea     aud_s_v6,a0         ; (blank the old value first)
        moveq   #30,d0
        moveq   #13,d1
        jsr     aud_text
        moveq   #0,d0
        move.b  CSV,d0
        cmpi.b  #2,d0
        bls   .k
        moveq   #0,d0
.k:     mulu    #6,d0
        lea     aud_s_all,a0
        adda.w  d0,a0
        moveq   #13,d1
        jsr     aud_right
        movem.l (sp)+,d0-d1/a0-a1
        rts
aud_s_all:  dc.b    'ALL',0,0,0
            dc.b    'INTRO',0
            dc.b    'NONE',0,0
aud_s_v6:   dc.b    '      ',0
        even
;============================================================================
        BLOCK aud_menu6
; CD VOICE: "NN NAME"
aud_vcd:
        movem.l d0-d2/a0-a2,-(sp)
        lea     aud_s_sp,a0         ; blank columns 15-35
        moveq   #15,d0
        moveq   #21,d1
        lea     11(a0),a0
        jsr     aud_text
        moveq   #0,d0
        move.b  CDTRK,d0
        lea     LINEBUF,a2
        divu    #10,d0
        addi.b  #'0',d0
        move.b  d0,(a2)+
        swap    d0
        addi.b  #'0',d0
        move.b  d0,(a2)+
        move.b  #' ',(a2)+
        moveq   #0,d0
        move.b  CDTRK,d0
        subq.w  #1,d0
        moveq   #0,d1               ; label block (15 each) and entry in it
.b:     cmpi.w  #15,d0
        bcs   .f
        subi.w  #15,d0
        addq.w  #1,d1
        bra   .b
.f:     lsl.w   #2,d1
        lea     aud_lbls,a0
        movea.l 0(a0,d1.w),a0
.sk:    subq.w  #1,d0
        bmi   .cp
.z:     tst.b   (a0)+
        bne   .z
        bra   .sk
.cp:    move.b  (a0)+,(a2)+
        bne   .cp
        lea     LINEBUF,a0
        moveq   #21,d1
        jsr     aud_right
        movem.l (sp)+,d0-d2/a0-a2
        rts
aud_lbls:   dc.l    aud_lbl0,aud_lbl1,aud_lbl2,aud_lbl3,aud_lbl4,aud_lbl5
        even

;============================================================================
        BLOCK aud_lbl0
aud_lbl0:
        dc.b    'INTRO',0
        dc.b    'STORY_1',0
        dc.b    'STORY_2',0
        dc.b    'STORY_3',0
        dc.b    'STORY_4',0
        dc.b    'STORY_5',0
        dc.b    'STORY_6',0
        dc.b    'HERZOG_1',0
        dc.b    'HERZOG_2',0
        dc.b    'HERZOG_3',0
        dc.b    'HERZOG_4',0
        dc.b    'HERZOG_5',0
        dc.b    'HERZOG_6',0
        dc.b    'HERZOG_7',0
        dc.b    'HERZOG_8',0
        even
;============================================================================
        BLOCK aud_lbl1
aud_lbl1:
        dc.b    'HERZOG_9',0
        dc.b    'ENDING_1',0
        dc.b    'ENDING_2',0
        dc.b    'ENDING_3',0
        dc.b    'AREA_CLEAR',0
        dc.b    'HEY',0
        dc.b    'THANKS_W',0
        dc.b    'GAME_OVER_1',0
        dc.b    'YEAH_M',0
        dc.b    'ROOM_CLEAR_1',0
        dc.b    'XENO_CRISIS',0
        dc.b    'AMBUSH',0
        dc.b    'BE_CAREFUL',0
        dc.b    'BELOW_SURF',0
        dc.b    'BFG',0
        even
;============================================================================
        BLOCK aud_lbl2
aud_lbl2:
        dc.b    'COMMENCING',0
        dc.b    'CONTINUE',0
        dc.b    'DANGER',0
        dc.b    'NOT_GOOD',0
        dc.b    'IN_FOR_FIGHT',0
        dc.b    'FLAMETHROWER',0
        dc.b    'GAME_OVER_2',0
        dc.b    'GOOD_LUCK',0
        dc.b    'HERE_COME_1',0
        dc.b    'HERE_COME_2',0
        dc.b    'HOMING',0
        dc.b    'ITS_A_TRAP',0
        dc.b    'KEEP_COOL',0
        dc.b    'LASER',0
        dc.b    'SIZE_OF_IT',0
        even
;============================================================================
        BLOCK aud_lbl3
aud_lbl3:
        dc.b    'SELECTION',0
        dc.b    'MISSION',0
        dc.b    'MONSTER',0
        dc.b    'OVER_THERE',0
        dc.b    'REBOUND',0
        dc.b    'RESCUE_1',0
        dc.b    'RESCUE_2',0
        dc.b    'ROCKET',0
        dc.b    'ROOM_CLEAR_2',0
        dc.b    'SHOTGUN',0
        dc.b    'SO_MANY',0
        dc.b    'SPREAD',0
        dc.b    'STAY_ALERT',0
        dc.b    'THE_ENEMY',0
        dc.b    'VULKAN',0
        even
;============================================================================
        BLOCK aud_lbl4
aud_lbl4:
        dc.b    'WATCH_OUT',0
        dc.b    'WATCH_BACK',0
        dc.b    'WHAT_HAPPEN',0
        dc.b    'WHAT_IS_IT',0
        dc.b    'WHAT_IS_THIS',0
        dc.b    'YOU',0
        dc.b    'STOP',0
        dc.b    'OUTTA_HERE_W',0
        dc.b    'THANK_YOU_W',0
        dc.b    'OVER_HERE_W',0
        dc.b    'HELP_W',0
        dc.b    'HEY_W',0
        dc.b    'HEY_W2',0
        dc.b    'QUICKLY_W',0
        dc.b    'SAVE_ME_W',0
        even
;============================================================================
        BLOCK aud_lbl5
aud_lbl5:
        dc.b    'SAVE_ME_W2',0
        dc.b    'HURRY_UP_W',0
        dc.b    'LAUGH',0
        dc.b    'THANK_YOU_M',0
        dc.b    'THANKS_M',0
        dc.b    'HEY_M',0
        dc.b    'SAVE_ME_M',0
        dc.b    'HELP_M',0
        dc.b    'OVER_HERE_M',0
        dc.b    'HEY_M2',0
        even

;============================================================================
        BLOCK opt_menu2
; HIGH SCORES item: show the tables; START+A+B+C (all held) resets the one shown.
; Leaves with a fresh press-and-release of START/A/B/C. Jumped to at the options loop level.
opt_hs_go:
        pea     $6F.w
        jsr     SFX
        addq.l  #4,sp
        move.w  #-2,NEWIDX
        jsr     opt_hs_init
        move.w  PAD1,PADOLD
        moveq   #0,d4               ; a button was pressed on this screen
        moveq   #0,d5               ; the reset combo is (still) held
.l:     jsr     hs_frame
        jsr     opt_hs_lr           ; left / right: the other table
        move.w  PRESSED,d0
        andi.w  #$F0,d0
        beq   .h
        st      d4
.h:     move.w  HELD,d0
        andi.w  #$F0,d0
        cmpi.w  #$F0,d0
        bne   .nc
        tst.b   d5
        bne   .l
        st      d5
        jsr     opt_hs_reset
        jsr     hs_sync
        move.w  #SFX_OK,d0
        jsr     hs_sfx
        jsr     hs_draw_all
        bra   .l
.nc:    tst.w   d0
        bne   .l
        tst.b   d5                  ; all released
        beq   .e
        moveq   #0,d4
        moveq   #0,d5
        bra   .l
.e:     tst.b   d4
        beq   .l
        clr.b   CURID
        jsr     hs_screen_off
        jsr     opt_hscroll
        lea     $FF364C,a0          ; the options screen doesn't reload its palette:
        move.l  #$C0000000,VDP_CTRL ; put back the game's copy of it
        moveq   #31,d0
.k:     move.l  (a0)+,VDP_DATA
        dbra    d0,.k
        clr.w   $FF3410             ; re-enter the options screen, as its sub-screens do
        clr.w   $FF4362
        clr.w   $FF36D0
        move.w  #5,$FF10BA          ; cursor on HIGH SCORES
        moveq   #-$58,d0            ; $A8
        movem.l (sp)+,d2-d5/a2-a6
        rts

;============================================================================
        BLOCK opt_strings
; the title's logo line scroll (we cleared it), as the title leaves it: lines 16-63 = 32
opt_hscroll:
        move.w  #$8F04,VDP_CTRL
        move.l  #$78000002,VDP_CTRL ; VRAM $B800
        moveq   #0,d1
.l:     moveq   #0,d0
        cmpi.w  #16,d1
        bcs   .w
        cmpi.w  #64,d1
        bcc   .w
        moveq   #32,d0
.w:     move.w  d0,VDP_DATA
        addq.w  #1,d1
        cmpi.w  #224,d1
        bne   .l
        moveq   #0,d0               ; autoincrement back to the game's setting
        move.b  $FF4B26+$F,d0
        ori.w   #$8F00,d0
        move.w  d0,VDP_CTRL
        rts
str_reset: dc.b '       HOLD A+B+C+START TO RESET        ',0
str_modes: dc.b 'MD/GENESIS',0
           dc.b ' DREAMCAST',0
           dc.b '    MODERN',0
        even

;============================================================================
        BLOCK opt_hs2
; Options > HIGH SCORES: left / right switch tables (redraws the whole screen)
opt_hs_lr:
        addq.w  #1,FRAMES           ; reset hint / EASY or HARD take turns every 3 s
        cmpi.w  #3*60,FRAMES
        bcs   .k
        clr.w   FRAMES
        eori.b  #1,ALTLABEL
        jsr     hs_footer
.k:     move.w  PRESSED,d0
        andi.w  #$0C,d0
        beq   .x
        eori.b  #1,CURID
        clr.w   FRAMES              ; the other table, starting with the reset hint
        clr.b   ALTLABEL
        jsr     hs_screen_on
.x:     rts
; first table: the one for the difficulty set, reset hint first
opt_hs_init:
        move.b  DIFFICULTY,CURID
        clr.b   ALTLABEL
        clr.w   FRAMES
        jmp     hs_screen_on
; START+A+B+C: reset the table being shown
opt_hs_reset:
        jsr     hs_tabptr
        jmp     hs_def
; d0.w = language * 4 (0-6; anything else = English)
opt_lang:
        moveq   #0,d0
        move.b  LANGUAGE,d0
        cmpi.b  #7,d0
        bcs   .k
        moveq   #0,d0
.k:     add.w   d0,d0
        add.w   d0,d0
        rts

;============================================================================
        BLOCK opt_lang_str
;                    EN, FR, IT, DE, ES, PT, NL
lng_cancel: dc.l    lc0,lc1,lc2,lc3,lc4,lc5,lc6
lng_hs:     dc.l    lh0,lh1,lh2,lh3,lh1,lh4,lh1
lng_modern: dc.l    lm0,lm1,lm2,lm0,lm2,lm2,lm0
lc0:  dc.b 'CANCEL RULES',0
lc1:  dc.b 'ANNULATIONS',0
lc2:  dc.b 'ANNULLAMENTI',0
lc3:  dc.b 'ABBRUCHREGELN',0
lc4:  dc.b 'CANCELACIONES',0
lc5:  dc.b 'CANCELAMENTOS',0
lc6:  dc.b 'ANNULEERREGELS',0
        even

;============================================================================
        BLOCK opt_lang_str2
lh0:  dc.b 'HIGH SCORES',0
lh1:  dc.b 'RECORDS',0
lh2:  dc.b 'RECORD',0
lh3:  dc.b 'REKORDE',0
lh4:  dc.b 'RECORDES',0
lm0:  dc.b '    MODERN',0
lm1:  dc.b '   MODERNE',0
lm2:  dc.b '   MODERNO',0
        even

;============================================================================
        BLOCK split_entry
; initials for row d1 of the table on screen (ENTPAD = which pad)
hs_entry_at:
        move.w  d1,NEWIDX
        clr.w   ENTPOS
        jsr     hs_draw_all         ; highlight this row (and un-highlight the last one)
        jmp     hs_entry
; a credit ends (continue screen): keep each player's best credit, start again from 0
split_credit_end:
        jsr     cur_detail          ; d1 = where in the area it ended
        move.l  SPLIT1,d0
        cmp.l   BEST1,d0
        bls   .a
        move.l  d0,BEST1
        move.b  GAREA,d0            ; (the area this credit ended in, and the marine)
        or.b    GSKIN1,d0
        move.b  d0,BESTA1
        move.b  d1,BESTD1
.a:     move.l  SPLIT2,d0
        cmp.l   BEST2,d0
        bls   .b
        move.l  d0,BEST2
        move.b  GAREA,d0
        or.b    GSKIN2,d0
        move.b  d0,BESTA2
        move.b  d1,BESTD2
.b:     clr.l   SPLIT1
        clr.l   SPLIT2
        rts
;============================================================================
        BLOCK split_entry2
; a credit starts: the marines the players chose
split_skins:
        move.b  SKIN_P1,d0
        bsr   .b
        move.b  d0,GSKIN1
        move.b  SKIN_P2,d0
        bsr   .b
        move.b  d0,GSKIN2
        rts
.b:     andi.b  #3,d0               ; -> (marine + 1) << 5
        addq.b  #1,d0
        lsl.b   #5,d0
        rts
; a new game
split_reset:
        clr.l   SPLIT1
        clr.l   SPLIT2
        clr.l   BEST1
        clr.l   BEST2
        lea     LASTHIT,a0
        moveq   #(64*3)/4-1,d0      ; LASTHIT, OWNER, ACTV
.c:     clr.l   (a0)+
        dbra    d0,.c
        move.w  #-1,CUROBJ
        move.w  #$7FFF,LASTD2
        clr.b   CURPL
        rts

;============================================================================
        BLOCK split_score
; replaces "addi.w #n,$FF35DE" at every kill / pickup: jsr score_u + dc.w n
score_u:
        movem.l d0-d1/a0-a1,-(sp)
        movea.l 16(sp),a0
        moveq   #0,d1
        move.w  (a0)+,d1
        move.l  a0,16(sp)
        add.w   d1,SCORE_U          ; what the game did
        jsr     credit
        movem.l (sp)+,d0-d1/a0-a1
        rts
; replaces "addi.w #n,$FF36E6" (boss bonus, n thousand): every player still standing gets it all
score_k:
        movem.l d0-d1/a0-a1,-(sp)
        movea.l 16(sp),a0
        moveq   #0,d1
        move.w  (a0)+,d1
        move.l  a0,16(sp)
        add.w   d1,SCORE_K
        mulu    #1000,d1
        tst.b   TWOPLAYER
        beq   .p1
        tst.w   P1_OBJ+$28          ; player 1 alive?
        ble   .n1
        add.l   d1,SPLIT1
.n1:    tst.w   P1_OBJ+64+$28
        ble   .x
        add.l   d1,SPLIT2
        bra   .x
.p1:    add.l   d1,SPLIT1
.x:     movem.l (sp)+,d0-d1/a0-a1
        rts
; d1.l points: 1 player -> player 1; 2 players -> the player who last hit the object being
; updated, else the nearer player (pickups)
credit:
        tst.b   TWOPLAYER
        beq   .p1
        move.w  CUROBJ,d0
        bmi   .p1
        lea     LASTHIT,a0
        move.b  0(a0,d0.w),d0
        bne   .who
        jsr     nearer_player
.who:   cmpi.b  #2,d0
        bne   .p1
        add.l   d1,SPLIT2
        rts
.p1:    add.l   d1,SPLIT1
        rts

;============================================================================
        BLOCK split_near
; d0.b = 1 or 2: the living player nearer to object CUROBJ (uses d0, a0-a1)
nearer_player:
        movem.l d2-d3,-(sp)
        move.w  CUROBJ,d0
        lsl.w   #6,d0
        lea     OBJBASE,a0
        adda.w  d0,a0               ; the object
        lea     P1_OBJ,a1
        bsr   .dist
        move.w  d0,d3
        lea     P1_OBJ+64,a1
        bsr   .dist
        moveq   #2,d2
        tst.w   P1_OBJ+$28          ; player 1 down: player 2
        ble   .r
        tst.w   P1_OBJ+64+$28       ; player 2 down: player 1
        ble   .one
        cmp.w   d3,d0
        bcs   .r
.one:   moveq   #1,d2
.r:     move.b  d2,d0
        movem.l (sp)+,d2-d3
        rts
.dist:  move.w  2(a0),d0            ; |dx| + |dy| (unsigned, saturating)
        sub.w   2(a1),d0
        bpl   .x
        neg.w   d0
.x:     move.w  4(a0),d2
        sub.w   4(a1),d2
        bpl   .y
        neg.w   d2
.y:     add.w   d2,d0
        bcc   .z
        moveq   #-1,d0
.z:     rts

;============================================================================
        BLOCK split_loop
; replaces "move.l d2,-(sp) / jsr (a0) / addq.l #4,sp" in the gameplay object loop ($31FE2)
; (d2 = object 1-51, a0 = its update routine). 2-player games only: damage added to enemies
; (pending damage at +$2C) while a player or one of its bullets/grenades updates is recorded
; as LASTHIT[enemy]. Only the enemies alive this frame are checked, and only when the owner
; of the updates changes.
obj_wrap:
        tst.b   TWOPLAYER
        bne   .two
        move.l  d2,-(sp)
        jsr     (a0)
        addq.l  #4,sp
        rts
.two:   move.l  a0,-(sp)
        cmp.w   LASTD2,d2           ; a new frame (the loop started again)
        bhi   .k
        jsr     flush_grp
        jsr     build_elist
.k:     move.w  d2,LASTD2
        jsr     owner_of            ; d0 = 0 / 1 / 2
        tst.b   d0
        bne   .t
        jsr     flush_grp           ; an enemy (or anything else): it handles its own damage
        bra   .call
.t:     cmp.b   CURPL,d0
        beq   .call                 ; same owner as the updates just before
        move.b  d0,-(sp)
        jsr     flush_grp
        move.b  (sp)+,CURPL
        jsr     snap_dmg
.call:  movea.l (sp)+,a0
        move.w  d2,CUROBJ
        cmpi.w  #50,d2
        bcc   .pl
        move.l  d2,-(sp)
        jsr     (a0)
        addq.l  #4,sp
        move.w  #-1,CUROBJ
        rts
.pl:    move.w  d2,d0               ; a player: grenades thrown during its update?
        jsr     stats_of
        move.b  $1B(a1),GREN
        move.l  d2,-(sp)
        jsr     (a0)
        addq.l  #4,sp
        move.w  #-1,CUROBJ
        move.w  d2,d0
        jsr     stats_of
        move.b  $1B(a1),d0
        cmp.b   GREN,d0
        bcc   .x
        jmp     learn_grenade
.x:     rts

;============================================================================
        BLOCK split_loop2
flush_grp:
        tst.b   CURPL
        beq   .x
        jsr     cmp_dmg
        clr.b   CURPL
.x:     rts
; d2 = object -> d0.b = owner (players 50/51 themselves, bullets 1-8 / 9-16, learnt grenades)
owner_of:
        moveq   #0,d0
        cmpi.w  #50,d2
        bcs   .p
        move.w  d2,d0
        subi.w  #49,d0
        rts
.p:     moveq   #1,d0
        cmpi.w  #9,d2
        bcs   .r
        moveq   #2,d0
        cmpi.w  #17,d2
        bcs   .r
        lea     OWNER,a1
        move.b  0(a1,d2.w),d0
.r:     rts
; d0 = player object (50/51) -> a1 = its stats block
stats_of:
        lea     STATS,a1
        cmpi.w  #50,d0
        beq   .x
        lea     STATS+66,a1
.x:     rts
; the player just threw a grenade: objects 17-49 that came to life this frame are its
learn_grenade:
        movem.l d1-d2/a0-a3,-(sp)
        move.w  d2,d1
        subi.w  #49,d1              ; 1 / 2
        lea     $FF2C8C+17*4,a0
        lea     ACTV+17,a1
        lea     OWNER+17,a2
        moveq   #49-17,d2
.l:     move.l  (a0)+,d0
        beq   .n
        movea.l d0,a3
        tst.l   $2A(a3)
        beq   .n
        tst.b   (a1)
        bne   .n
        move.b  d1,(a2)
.n:     addq.l  #1,a1
        addq.l  #1,a2
        dbra    d2,.l
        movem.l (sp)+,d1-d2/a0-a3
        rts

;============================================================================
        BLOCK split_elist
; once per frame: live enemies (objects 17-49 that are not grenades). Objects that came to
; life lose any old LASTHIT; objects that died lose their grenade owner.
build_elist:
        movem.l d1-d3/a1-a5,-(sp)
        lea     $FF2C8C+17*4,a0
        lea     OWNER+17,a1
        lea     ELIST,a2
        lea     ACTV+17,a3
        lea     LASTHIT+17,a4
        moveq   #-1,d1
        moveq   #17,d2
.l:     moveq   #0,d3               ; active now?
        move.l  (a0)+,d0
        beq   .s
        movea.l d0,a5
        tst.l   $2A(a5)
        sne     d3
.s:     tst.b   d3
        bne   .on
        tst.b   (a3)                ; died: no grenade owner any more
        beq   .n
        clr.b   (a1)
        bra   .n
.on:    tst.b   (a3)                ; came to life: nobody has hit it yet
        bne   .a
        clr.b   (a4)
.a:     tst.b   (a1)
        bne   .n
        move.w  d2,d0
        lsl.w   #6,d0
        move.w  d0,(a2)+
        addq.w  #1,d1
.n:     move.b  d3,(a3)+
        addq.l  #1,a1
        addq.l  #1,a4
        addq.w  #1,d2
        cmpi.w  #50,d2
        bne   .l
        move.w  d1,ECOUNT
        movem.l (sp)+,d1-d3/a1-a5
        rts

;============================================================================
        BLOCK split_dmg
snap_dmg:
        move.l  a2,-(sp)
        move.w  ECOUNT,d1
        bmi   .x
        lea     ELIST,a0
        lea     DMGBUF,a1
        lea     OBJBASE+$2C,a2
.s:     move.w  (a0)+,d0
        move.w  0(a2,d0.w),(a1)+
        dbra    d1,.s
.x:     movea.l (sp)+,a2
        rts
cmp_dmg:
        movem.l d0-d1/a0-a3,-(sp)
        move.w  ECOUNT,d1
        bmi   .x
        lea     ELIST,a0
        lea     DMGBUF,a1
        lea     OBJBASE+$2C,a2
        lea     LASTHIT,a3
.c:     move.w  (a0)+,d0
        move.w  0(a2,d0.w),d0
        cmp.w   (a1)+,d0
        ble   .n
        move.w  -2(a0),d0           ; offset -> object
        lsr.w   #6,d0
        move.b  CURPL,0(a3,d0.w)
.n:     dbra    d1,.c
.x:     movem.l (sp)+,d0-d1/a0-a3
        rts

;============================================================================
        BLOCK ac_text
; Area Clear: the game's text-sprite call ($8D606: string, x, y, attributes on the stack),
; patched at its entry. The result screen's combined SCORE and HIGH SCORE give way to each
; player's own score: 1 player under the rank, 2 players under each player's rank (the
; P1 / P2 columns moved apart to sit over them). The game's "HIGH SCORE" label goes under
; the best score, as "NEW HIGH SCORE", when it beats the table. Other calls pass straight through.
AC_SCORE    equ $32A3C          ; return addresses: the score
AC_SCORELBL equ $32836          ;   "SCORE"
AC_HILBL    equ $32A90          ;   "HIGH SCORE"
AC_P1       equ $34014          ;   "P1" (2 players)
AC_P2       equ $340C2          ;   "P2"
AC_RANK     equ $326A0          ;   "RANK"
AC_HI_SMALL equ $32C5E          ;   the high score (one call per digit count: under 10 here,
AC_HI_LO    equ $34700          ;   the others in this range)
AC_HI_HI    equ $34F00
ACBUF       equ VARS+$2E4       ; 2 x 12 bytes: each player's score as text
ac_blank:   dc.b    ' ',0
ac_text:
        move.l  (sp),d0
        cmpi.l  #AC_SCORELBL,d0
        beq   .hide
        cmpi.l  #AC_HILBL,d0
        beq   ac_hilbl
        cmpi.l  #AC_SCORE,d0
        beq   .p1
        cmpi.l  #AC_P1,d0
        beq   ac_p1
        cmpi.l  #AC_P2,d0
        beq   ac_p2
        cmpi.l  #AC_RANK,d0
        beq   ac_rank
        cmpi.l  #AC_HI_SMALL,d0
        beq   .hi
        cmpi.l  #AC_HI_LO,d0
        bcs   .go
        cmpi.l  #AC_HI_HI,d0
        bcc   .go
.hi:    tst.b   TWOPLAYER           ; the high score: player 2's score instead, or nothing
        beq   .hide
        move.l  SPLIT2,d0
        move.w  #220,d1
        lea     ACBUF+12,a0
        bra   .num
.p1:    move.l  SPLIT1,d0
        lea     ACBUF,a0
        move.w  #160,d1             ; centre x
        tst.b   TWOPLAYER
        beq   .num
        move.w  #100,d1
.num:   jsr     ac_number
        bra   .go
.hide:  move.l  #ac_blank,4(sp)     ; a blank in its place (the call must still make its
        bra   .go                   ; sprite: off-screen positions make it fail)
.go:    movem.l d2-d4/a2-a5,-(a7)   ; (the instructions the patch replaced)
        movea.l $20(a7),a5
        jmp     $8D60E

;============================================================================
        BLOCK ac_hilbl
ac_hilbl:
        tst.b   GCHEAT              ; "HIGH SCORE" under the best score, if it beats the
        bne   .hide                 ; top of this difficulty's table (no table: never)
        jsr     hs_top
        move.l  SPLIT1,d1
        tst.b   TWOPLAYER
        beq   .h1
        cmp.l   SPLIT2,d1
        bcc   .h2
        move.l  SPLIT2,d1           ; player 2 ahead
        cmp.l   d0,d1
        bls   .hide
        move.w  #220-56,10(sp)
        bra   .hy
.h2:    cmp.l   d0,d1               ; player 1 ahead (2 players)
        bls   .hide
        move.w  #100-56,10(sp)
        bra   .hy
.h1:    cmp.l   d0,d1               ; 1 player
        bls   .hide
        move.w  #160-56,10(sp)
.hy:    addi.w  #18,14(sp)          ; down into the line the numbers used
        tst.b   TWOPLAYER
        beq   .hz
        subi.w  #20,14(sp)
.hz:        move.l  #ac_newhi,4(sp)
        bra   .go
.hide:  move.l  #ac_blank,4(sp)
.go:    movem.l d2-d4/a2-a5,-(a7)   ; (the instructions the patch replaced)
        movea.l $20(a7),a5
        jmp     $8D60E
ac_newhi:   dc.b    'NEW HIGH SCORE',0
        even

;============================================================================
        BLOCK ac_plbl
; 2 players: "P1 RANK" / "P2 RANK" over each player's rank, in the RANK line (which goes)
ac_rank:
        tst.b   TWOPLAYER
        beq   acx_go
        bra   acx_hide
; (7 characters = 14 tiles, more than "P1" had before the rank's: they go in the tiles the
; RANK line and "P1" used, base + $B4 and + $C2; the call's tile/attribute word is 18(sp))
ac_p1:  move.l  #ac_p1r,4(sp)
        move.w  #100-28,10(sp)
        moveq   #-$4C,d0            ; ($B4 - $100: the base is added below)
        bra   acx_up
ac_p2:  move.l  #ac_p2r,4(sp)
        move.w  #220-28,10(sp)
        moveq   #-$3E,d0            ; ($C2)
acx_up: addi.w  #$A100,d0
        add.w   $FF36E2,d0
        move.w  d0,18(sp)
        move.w  #110,14(sp)         ; (where the RANK line is, as with 1 player)
        bra   acx_go
acx_hide:
        move.l  #ac_blank,4(sp)
acx_go: movem.l d2-d4/a2-a5,-(a7)
        movea.l $20(a7),a5
        jmp     $8D60E
ac_p1r:     dc.b    'P1 RANK',0
ac_p2r:     dc.b    'P2 RANK',0
        even

;============================================================================
        BLOCK ac_number
; d0.l = score, d1.w = centre x, a0 = buffer <- "12,345"; the call's string / x (4(sp) /
; 10(sp) of the caller's frame, here 8(sp) / 14(sp)) are pointed at it
ac_number:
        movem.l d1-d3/d7/a2,-(sp)
        move.l  a0,-(sp)
        moveq   #1,d3
        jsr     fmtnum              ; NUMBUF..a0: digits (10 = comma)
        lea     NUMBUF,a1
        movea.l (sp),a2
        moveq   #0,d2
.c:     cmpa.l  a0,a1
        beq   .e
        move.b  (a1)+,d0
        addi.b  #'0',d0
        cmpi.b  #'0'+10,d0
        bne   .d
        move.b  #',',d0
.d:     move.b  d0,(a2)+
        addq.w  #1,d2
        bra   .c
.e:     clr.b   (a2)
        move.w  d2,d0               ; (length)
        movea.l (sp)+,a0
        movem.l (sp)+,d1-d3/d7/a2
        move.l  a0,8(sp)
        lsl.w   #2,d0               ; x = centre - length * 4
        sub.w   d0,d1
        move.w  d1,14(sp)
        subi.w  #18,18(sp)          ; up into the line the labels used
        tst.b   TWOPLAYER
        beq   .r
        subi.w  #20,18(sp)          ; (2 players: everything a line higher, no RANK line)
.r:        rts

;============================================================================
        BLOCK hs_data
hs_default_tab:                     ; Neo Geo defaults
        dc.l    512000
        dc.b    'BIT',1|(0+1)<<5
        dc.l    256000
        dc.b    'MAP',1|(3+1)<<5
        dc.l    128000
        dc.b    'BUR',1|(1+1)<<5
        dc.l    64000
        dc.b    'EAU',1|(2+1)<<5
        dc.l    32000
        dc.b    'M.C',1|(3+1)<<5
        dc.l    16000
        dc.b    'MMT',1|(0+1)<<5
        dc.l    8000
        dc.b    'HNK',1|(2+1)<<5
        dc.l    4000
        dc.b    'HPM',1|(1+1)<<5
        dc.l    2000
        dc.b    'S.R',1|(0+1)<<5
        dc.l    1000
        dc.b    'C.M',1|(3+1)<<5             ; (the Neo Geo version's 10th entry)

;============================================================================
        BLOCK hs_strings
rank_sfx:   dc.b    'STNDRDTHTHTHTHTHTHTH'
hs_charset: dc.b    'ABCDEFGHIJKLMNOPQRSTUVWXYZ',CH_BACK,CH_END
        even

;============================================================================
        BLOCK hs_strings2
str_top:    dc.b    'TOP MARINES',0
str_right:  dc.b    CH_RIGHT,0          ; Options view: which way the other table is
str_left:   dc.b    CH_BACK,0
str_easy:   dc.b    '                  EASY                  ',0
str_hard:   dc.b    '                  HARD                  ',0
        even
;============================================================================
        BLOCK hs_strings3
str_enter:  dc.b    '        ENTER YOUR INITIALS             ',0
str_enter1: dc.b    '       1P ENTER YOUR INITIALS           ',0
str_enter2: dc.b    '       2P ENTER YOUR INITIALS           ',0
        even

;============================================================================
        BLOCK hs_gfx
hs_vdpregs:                         ; display off, title layout: A=$E000 B=$C000 SAT=$BC00 HS=$B800 128x32 line scroll
        dc.w    $8134,$8238,$8406,$855E,$8700,$8B03,$8C81,$8D2E,$8F02,$9003,$9100,$9200,0
hs_regnums: dc.b  2,3,4,5,7,$B,$C,$D,$F,$10,$11,$12,-1
        even
hs_palette:                         ; BGR: 0000BBB0GGG0RRR0
        dc.w    $0000,$0EEE,0,0,0,0,0,0,0,0,0,0,0,0,0,$0444   ; white
        dc.w    $0000,$00EE,0,0,0,0,0,0,0,0,0,0,0,0,0,$0024   ; yellow
hs_glyphs:                          ; 8x16, same style as the font (1 = fill, F = outline)
        ; heart
        dc.l    $00000000,$00000000,$00000000,$0FF00FF0,$F11FF11F,$F111111F,$F111111F,$F111111F
        dc.l    $F111111F,$0F1111F0,$00F11F00,$000FF000,$00000000,$00000000,$00000000,$00000000
        ; left arrow (backspace)
        dc.l    $00000000,$00000000,$00000000,$0000F000,$000FF000,$00F1F000,$0F11FFFF,$F111111F
        dc.l    $F111111F,$0F11FFFF,$00F1F000,$000FF000,$0000F000,$00000000,$00000000,$00000000
        ; check mark (end)
        dc.l    $00000000,$00000000,$00000000,$000000FF,$00000F11,$0000F11F,$FF00F11F,$F1FF11F0
        dc.l    $F11F11F0,$0F111F00,$00F11F00,$000FF000,$00000000,$00000000,$00000000,$00000000
        ; right arrow
        dc.l    $00000000,$00000000,$00000000,$000F0000,$000FF000,$000F1F00,$FFFF11F0,$F111111F
        dc.l    $F111111F,$FFFF11F0,$000F1F00,$000FF000,$000F0000,$00000000,$00000000,$00000000
        ; star (over '*')
        dc.l    $00000000,$00000000,$000FF000,$00F11F00,$00F11F00,$FFF11FFF,$F111111F,$F111111F
        dc.l    $0F1111F0,$00F11F00,$0F1111F0,$0F1FF1F0,$F11FF11F,$F1F00F1F,$FF0000FF,$00000000

;============================================================================
; MD+ voice. The interface is used only from VBlank (or with interrupts masked), and while
; it is open the overlay hides ROM $3F7F6-$3FFFF: all of this code and data is LOW.
        BLOCK mdp_io LOW
; d0.w = command
mdp_cmd:
        move.w  #$CD54,MDP_OVL
        move.w  d0,MDP_CMD
        move.w  #0,MDP_OVL
        rts
; d0 = track, d1 = priority (d0-d1/a0 used)
mdp_play:
        tst.b   SOUNDS_ON           ; voices follow the sound effects option
        beq   .no
        cmpi.b  #P_CHAT,d1
        bne   .p
        tst.b   MDP_PRI             ; chatter waits for silence
        bne   .no
.p:     cmpi.b  #P_QUEUE,d1
        bne   .p2
        cmp.b   MDP_PRI,d1          ; queue class and something playing: into the queue
        bhi   .p2                   ; (if it's empty; else this one is dropped)
        tst.b   MDP_Q
        bne   .no
        move.b  d0,MDP_Q
        clr.b   MDP_QAGE
        rts
.p2:    cmp.b   MDP_PRI,d1
        blo   .no
        move.b  d1,MDP_PRI
        andi.w  #$FF,d0
        lea     mdp_len-1,a0
        moveq   #0,d1
        move.b  0(a0,d0.w),d1
        lsl.w   #3,d1
        move.w  d1,MDP_BUSY
        ori.w   #$1100,d0
        bra   mdp_cmd
.no:    rts
mdp_stop:
        clr.b   MDP_PRI
        clr.w   MDP_BUSY
        move.w  #$1308,d0           ; stop, fading out over 8/75 s
        bra   mdp_cmd
; first VBlank after power-on, and the boot screen after a reset: find the interface
mdp_detect:
        clr.l   MDP_ON              ; ON SCR SUB PAGE
        clr.l   MDP_PRI             ; PRI ALT BUSY
        clr.w   MDP_SECS
        clr.w   MDP_DLY
        move.l  #'MDP+',MDP_MAGIC
        move.w  #$CD54,MDP_OVL
        cmpi.w  #$CD54,MDP_OVL      ; a plain cartridge reads its own ROM here
        bne   .none
        move.w  #$1300,MDP_CMD      ; silence anything left from before a reset
        move.b  #1,MDP_ON
.none:  move.w  #0,MDP_OVL
        rts

;============================================================================
        BLOCK mdp_vint LOW
; replaces "movea.l $FF4F4E,a0 / jsr (a0)" in the VBlank handler (d0-d1/a0-a1 saved by it)
mdp_vint:
        movea.l $FF4F4E,a0
        jsr     (a0)
        cmpi.l  #'MDP+',MDP_MAGIC
        bne   .d
        tst.w   SCREEN_W            ; boot screen (power-on or reset)
        bne   .on
        tst.b   MDP_SCR
        beq   .on
.d:     jsr     mdp_detect
.on:    cmpi.b  #1,MDP_ON
        bne   .x
        movem.l d2-d3/a2,-(sp)
        jsr     mdp_tick
        movem.l (sp)+,d2-d3/a2
.x:     rts
; screen 3 (intro) starts its music with "jmp $3E530": with MD+ the CD track carries the
; Neo Geo intro music, so the Mega Drive's is stopped instead
mdp_intro_mus:
        cmpi.b  #1,MDP_ON
        bne   .md
        tst.b   SOUNDS_ON
        beq   .md
        tst.b   MUSIC_ON
        beq   .md
        cmpi.b  #2,CSV              ; (no intro track: keep the Mega Drive's music)
        beq   .md
        move.w  #$100,$A11100       ; Z80 bus
        move.w  #$100,$A11200
.w:     btst    #0,$A11100
        bne   .w
        move.b  #$80,$A00100        ; sound driver: no music
        move.b  #0,$A00113
        move.w  #0,$A11100
        rts
.md:    jmp     $3E530

;============================================================================
        BLOCK mdp_tick LOW
; once per frame: voice what the game is doing (d0-d3/a0-a2 free)
mdp_tick:
        move.w  MDP_BUSY,d0
        beq   .idle
        subq.w  #1,d0
        move.w  d0,MDP_BUSY
        bne   .t
.idle:  clr.b   MDP_PRI
.t:     move.w  MDP_DLY,d0          ; a line waiting for its moment
        beq   .t2
        subq.w  #1,d0
        move.w  d0,MDP_DLY
        bne   .t2
        moveq   #0,d0
        move.b  MDP_DTRK,d0
        moveq   #P_EVENT,d1
        jsr     mdp_play
.t2:    jsr     mdp_queue
        moveq   #$1F,d2
        and.w   SCREEN_W,d2         ; d2 = screen
        move.b  MDP_SCR,d3          ; d3 = last frame's screen
        cmp.b   d2,d3
        beq   mdp_sub
        move.b  d2,MDP_SCR
        clr.w   MDP_DLY
        clr.b   MDP_Q
        st      MDP_SUB
        st      MDP_PAGE
        cmpi.b  #P_STORY,MDP_PRI    ; leaving the intro or a story page: stop it
        bne   .ent
        jsr     mdp_stop
.ent:   moveq   #P_EVENT,d1
        cmpi.b  #3,d2
        bne   .tit
        tst.b   MUSIC_ON
        beq   .r
        cmpi.b  #2,CSV              ; cutscene voices: none
        beq   .r
        moveq   #T_INTRO,d0
        moveq   #P_STORY,d1
        bra   .go
.tit:
.sel:   moveq   #V_A152,d0          ; "Make your selection"
        cmpi.b  #14,d2              ; marine select
        beq   .go
        cmpi.b  #17,d2              ; shop
        beq   .go
        moveq   #V_A138,d0          ; "Continue?"
        cmpi.b  #1,d2
        bne   .r
        tst.b   $FF36E0             ; (only when the game offers one - its own tests at
        bne   .r                    ;  $1AF12: not in a special mode, a continue left,
        tst.b   $FF46FD             ;  and not Dr. Herzog's ending, play state 10)
        beq   .r
        cmpi.w  #10,$FF0012
        beq   .r
.go:    jmp     mdp_play
.r:     rts

;============================================================================
        BLOCK mdp_sub LOW
; d2 = screen (unchanged since last frame)
mdp_sub:
        move.b  SUBSTATE+1,d1
        move.b  MDP_SUB,d3          ; d3 = last frame's substate
        cmp.b   d1,d3
        beq   mdp_story
        move.b  d1,MDP_SUB
        moveq   #0,d0
        cmpi.b  #15,d2              ; drop-off
        beq   mdp_drop
.s16:   cmpi.b  #16,d2
        bne   .x
        moveq   #0,d0
        move.b  CURAREA,d0
        cmpi.b  #6,d0
        bhi   .x
        lea     mdp_first,a0
        cmpi.b  #1,d1               ; area name: the area's line halfway through showing it
        bne   .r2
        move.b  0(a0,d0.w),MDP_DTRK
        move.w  #60,MDP_DLY
        jmp     mdp_rarea
.r2:    cmpi.b  #2,d1               ; a room starts
        bne   .go
        move.b  #240,MDP_HUM        ; look for humans in it
        jsr     mdp_htclr
        clr.b   MDP_NOBODY
        cmpi.b  #1,d3               ; first room (its line came with the area name)
        bne   .rm
        cmpi.b  #V_A169,0(a0,d0.w)
        seq     MDP_NOBODY
        rts
.rm:    cmpi.b  #4,d3               ; a new room (not back into a clear one)
        bne   .x
        jmp     mdp_room
.go:    jmp     mdp_sub2               ; (room clear, area clear, game over: the game says those)
.ev:    moveq   #P_EVENT,d1
        jmp     mdp_play
.x:     rts

;============================================================================
        BLOCK mdp_queue LOW
; the 1-line queue: plays when only chatter (or nothing) is playing; dropped after 2 s
mdp_queue:
        move.b  MDP_REQ,d0          ; Options > Audio > CD VOICE: play that track
        beq   .q
        clr.b   MDP_REQ
        moveq   #P_STORY,d1         ; (stopped like a story page when the screen changes)
        jmp     mdp_play
.q:     move.b  MDP_Q,d0
        beq   .x
        addq.b  #1,MDP_QAGE
        cmpi.b  #120,MDP_QAGE
        bhi   .drop
        cmpi.b  #P_QUEUE,MDP_PRI
        bhs   .x
        clr.b   MDP_Q
        moveq   #P_QUEUE,d1
        jmp     mdp_play
.drop:  clr.b   MDP_Q
.x:     rts

;============================================================================
        BLOCK mdp_story LOW
; story screens: 4 = between areas, 5 = Dr. Herzog, 6 = ending. As on the Neo Geo, a page's
; narration starts with its first typed character.
mdp_story:
        cmpi.b  #16,d2
        beq   mdp_game
        tst.b   CSV                 ; cutscene voices: intro only / none
        bne   .x
        cmpi.b  #4,d2
        blo   .x
        cmpi.b  #6,d2
        bhi   .x
        tst.b   CUT_LINE
        bne   .x
        tst.b   CUT_CHAR
        beq   .x
        moveq   #0,d1
        move.b  CUT_PAGE,d1
        cmpi.b  #4,d2
        bne   .p5
        tst.b   MDP_PAGE            ; one page, once
        bpl   .x
        moveq   #0,d1
        moveq   #0,d0
        move.b  CURAREA,d0
        cmpi.b  #5,d0
        bhi   .x
        addq.b  #T_CUT1,d0
        bra   .pg
.p5:    cmp.b   MDP_PAGE,d1
        beq   .x
        cmpi.b  #5,d2
        bne   .p6
        cmpi.b  #8,d1               ; 0-1, then 2-6 (a continue was used) or 7-8
        bhi   .x
        moveq   #T_HERZOG,d0
        add.b   d1,d0
        bra   .pg
.p6:    cmpi.b  #2,d1
        bhi   .x
        moveq   #T_END,d0
        add.b   d1,d0
.pg:    move.b  d1,MDP_PAGE
        moveq   #P_STORY,d1
        jmp     mdp_play
.x:     rts
; each area (0-6): first room, boss room (0 = none)
mdp_first:
        dc.b    V_A153,V_A141,V_A135,V_A169,V_A164,V_A164,V_A144
mdp_boss:
        dc.b    V_A151,V_A149,0,V_A154,V_A170,V_A140,0  ; (area 7: mdp_sub2 plays the laugh)
        even

;============================================================================
        BLOCK mdp_lens LOW
; length of each track in 8-frame units (track 1 first)
mdp_len:
        dc.b    241,49,50,49,68,46,70,66,73,98,65,34,87,126,86,60
        dc.b    79,63,53,10,4,7,15,6,9,15,9,9,14,10,14,9
        dc.b    7,12,14,10,13,8,9,9,8,8,11,8,16,12,18,11
        dc.b    8,11,13,14,10,8,10,13,10,9,8,8,8,10,11,10
        dc.b    12,5,6,9,8,8,7,6,6,6,9,8,7
        dc.b    18,6,6,6,7,5,7,5
        even

;============================================================================
        BLOCK mdp_room LOW
; Room lines, as the Neo Geo does them (its substate 2, frame 50 = here, the end of the
; Mega Drive's 45-frame substate 2, when the fight starts):
; 1. a line the spawn code picked with its formation (hooks below): "It's a trap!", "An ambush?",
;    "So many of them!", "Danger!" (bodies, "What happened here?", are found by mdp_hum);
; 2. else "Rescue the humans" if any are waiting (mdp_hum);
; 3. else chatter: every 1-4 such rooms (2-5 after the area's first room), one of 8 lines.
mdp_room:
        move.b  MDP_RL,d0
        beq   .nr
        clr.b   MDP_RL
        move.b  d0,MDP_DTRK
        move.w  #45,MDP_DLY
        move.b  #2,MDP_NOBODY       ; humans here: their calls, but no "rescue the humans"
        rts
.nr:    jsr     mdp_hum             ; humans or bodies here: that line instead of chatter
        tst.b   MDP_HUM
        beq   .x
        jsr     mdp_rnd
        move.b  MDP_CNT,d0
        beq   .pk
        subq.b  #1,d0
        move.b  d0,MDP_CNT
        bne   .x
.pk:    move.w  d1,d0
        lsr.w   #8,d0
        andi.w  #3,d0
        addq.b  #1,d0
        move.b  d0,MDP_CNT
        rol.w   #3,d1
        andi.w  #7,d1
        lea     mdp_pool,a0
        move.b  0(a0,d1.w),MDP_DTRK
        move.w  #45,MDP_DLY
.x:     rts
        even
;============================================================================
        BLOCK mdp_rarea LOW
; the area name: a new count, no line left over (d1 = random)
mdp_rarea:
        clr.b   MDP_RL
        bsr   mdp_rnd
        moveq   #3,d0
        and.w   d1,d0
        addq.b  #2,d0
        move.b  d0,MDP_CNT
        rts
mdp_rnd:
        move.w  MDP_RND,d1
        mulu    #$6255,d1
        addi.w  #$3619,d1
        add.w   $FF4726,d1          ; (a game timer: adds some variety)
        move.w  d1,MDP_RND
        rts
; the Neo Geo's 8 (random & 7): here they come, A146, watch out, the enemy, stay alert,
; be careful, watch your back, over there
mdp_pool:
        dc.b    V_A145,V_A146,V_A167,V_A165,V_A164,V_A134,V_A168,V_A155
        even
;============================================================================
        BLOCK mdp_rhook LOW
; spawn-code hooks (main loop, not VBlank): the formation's line for mdp_room
mdp_rtrap:                          ; $1249E: ring of 8 around the player
        move.b  $FF35DC,d7
        move.b  #V_A148,MDP_RL      ; "It's a trap!"
        rts
mdp_ramb:                           ; $12930: the room-shaped variant
        move.b  $FF35DC,d7
        move.b  #V_A133,MDP_RL      ; "An ambush?"
        rts
mdp_rhorde:                         ; $128D8: a crowd
        jsr     $EE92
        move.b  #V_A162,MDP_RL      ; "So many of them!"
        rts
mdp_rdanger:                        ; $13534: big ones
        move.b  $FF3304,d0
        move.b  #V_A139,MDP_RL      ; "Danger!"
        rts

;============================================================================
        BLOCK mdp_hum LOW
; gameplay: in a new room's first seconds, "Rescue the humans" if any are waiting there
; (their objects run the game's routine at $1B5DC)
mdp_hum:
        tst.b   MDP_HUM
        beq   .x
        subq.b  #1,MDP_HUM
        cmpi.b  #P_QUEUE,MDP_PRI    ; (cuts in on queue lines; lets a room line finish)
        bhi   .x
        lea     $FF2C8C,a0
        moveq   #51,d1
        moveq   #0,d2               ; a body here?
.l:     move.l  (a0)+,d0
        beq   .n
        movea.l d0,a1
        move.l  $2A(a1),d0
        cmpi.l  #$1B5DC,d0          ; human
        beq   .hc
        cmpi.l  #$526C0,d0          ; body (the game's 4 kinds of corpse: $53172 sets them up,
        beq   .b                    ; then they keep this do-nothing routine)
        cmpi.l  #$53172,d0
        bne   .n
.b:     moveq   #1,d2
.n:     dbra    d1,.l
        bra   .e
.hc:    moveq   #51,d0              ; (only one still waiting: not reached, rescued or leaving)
        sub.w   d1,d0
        lsl.w   #6,d0
        lea     OBJBASE,a1
        move.b  $15(a1,d0.w),d0
        andi.b  #$0E,d0
        bne   .n
        bra   .h
.e:        tst.b   d2
        beq   .x
        tst.b   MDP_NOBODY
        bne   .x
        clr.b   MDP_HUM
        moveq   #V_A169,d0          ; "What happened here?"
        bra   .p
.x:     rts
.h:     clr.b   MDP_HUM
        cmpi.b  #2,MDP_NOBODY       ; the room's own line instead
        beq   .x
        moveq   #V_A157,d0
        bchg    #2,MDP_ALT
        beq   .p
        moveq   #V_A158,d0
.p:     clr.w   MDP_DLY             ; (no chatter after it)
        moveq   #P_EVENT,d1
        jmp     mdp_play

;============================================================================
        BLOCK mdp_sub2 LOW
; area 1's drop-off: as the ship takes off (d1 = new substate)
mdp_drop:
        cmpi.b  #3,d1
        bne   .x
        tst.b   CURAREA
        bne   .x
        move.b  #V_A137,MDP_DTRK    ; "Commencing operations"
        move.w  #10,MDP_DLY
.x:     rts
; mdp_sub continued: d0 = area (0-6), d1 = new substate
mdp_sub2:
        cmpi.b  #7,d1               ; boss room: as the boss's name appears (1 s in)
        bne   .tf
        cmpi.b  #6,d0               ; area 7: Dr. Herzog laughs straight away (his scene
        beq   .hz                   ;  follows)
        lea     mdp_boss,a0
        move.b  0(a0,d0.w),d0
        beq   .x
        move.b  d0,MDP_DTRK
        move.w  #62,MDP_DLY
        rts
.hz:    moveq   #V_C003,d0
        bra   .ev
.tf:    cmpi.b  #6,d1               ; area 7: back from Dr. Herzog's scene, he transforms
        bne   .ac
        cmpi.b  #6,d0
        bne   .x
        moveq   #V_A171,d0          ; "What is this?"
        bra   .ev
.ac:    bra   .x
.ev:    moveq   #P_EVENT,d1
        jmp     mdp_play
.x:     rts

;============================================================================
        BLOCK mdp_game LOW
; gameplay, every frame
mdp_game:
        jsr     mdp_wpn
        move.b  MDP_RESC,d0         ; a hostage just rescued (mdp_mres / mdp_fres)
        beq   .h
        clr.b   MDP_RESC
        moveq   #P_QUEUE,d1
        jsr     mdp_play
.h:     jsr     mdp_hcall
        jmp     mdp_hum
; a special weapon picked up (its seconds jump up): its name
mdp_wpn:
        lea     STATS,a2
        lea     MDP_SECS,a1
        moveq   #1,d3               ; 2 players
.l:     moveq   #0,d0
        move.b  $0D(a2),d0          ; seconds left
        moveq   #0,d2
        move.b  (a1),d2
        move.b  d0,(a1)+
        addq.w  #1,d2
        cmp.w   d2,d0
        bls   .n
        moveq   #0,d0
        move.b  8(a2),d0            ; weapon 1-9
        beq   .n
        cmpi.b  #9,d0
        bhi   .n
        lea     mdp_wpns-1,a0
        move.b  0(a0,d0.w),d0
        moveq   #P_QUEUE,d1
        jsr     mdp_play            ; (d0-d1/a0 used)
.n:     lea     66(a2),a2
        dbra    d3,.l
        rts
; weapons 1-9: flamethrower, rocket launcher, spread, homing, laser, rebound, shotgun,
; vulcan, BFG
mdp_wpns:
        dc.b    V_A142,V_A159,V_A163,V_A147,V_A150,V_A156,V_A161,V_A166,V_A136
        even

;============================================================================
        BLOCK mdp_hcall LOW
; Waiting hostages call out, as on the Neo Geo ($80C46): each one on its own timer, first
; 60-315 frames after it appears, then every 300-1323 frames, until a player reaches it.
; Women: one of A179-A186 (rand & 7). Men: $F3 for rand & 7 = 0-1, else $F2 + rand & 7,
; i.e. C011 C011 C012 C013 C014 C015 C016 C017 (C015, C017 = takes of C012, C016).
mdp_hcall:
        moveq   #7,d0               ; timers count every 8th frame
        and.b   MDP_FRM,d0
        addq.b  #1,MDP_FRM
        tst.b   d0
        bne   .x
        lea     $FF2C8C,a2
        moveq   #0,d3               ; object 0-51 (only d0-d3/a0-a2 are free here)
.l:     move.l  (a2)+,d0
        beq   .no
        movea.l d0,a1
        cmpi.l  #$1B5DC,$2A(a1)     ; a human
        bne   .no
        move.w  d3,d0
        lsl.w   #6,d0
        lea     OBJBASE,a1
        adda.w  d0,a1
        moveq   #$0E,d0             ; reached, rescued or leaving: quiet
        and.b   $15(a1),d0
        bne   .no
        lea     MDP_HT,a0
        adda.w  d3,a0
        move.b  (a0),d0
        bne   .t
        jsr     mdp_rnd             ; new: first call in 60-315 frames
        moveq   #31,d0
        and.w   d1,d0
        addq.b  #8,d0
        move.b  d0,(a0)
        bra   .n
.t:     subq.b  #1,d0
        move.b  d0,(a0)
        cmpi.b  #1,d0
        bne   .n
        jsr     mdp_rnd             ; call, and the next in 300-1323 frames
        moveq   #127,d0
        and.w   d1,d0
        addi.b  #38,d0
        move.b  d0,(a0)
        rol.w   #3,d1
        andi.w  #7,d1
        lea     mdp_wline,a0
        cmpi.b  #$7C,(a1)
        beq   .w
        lea     mdp_wman,a0
.w:     move.b  0(a0,d1.w),d0
        moveq   #P_CHAT,d1
        movem.l d3/a2,-(sp)
        jsr     mdp_play
        movem.l (sp)+,d3/a2
        bra   .n
.no:    lea     MDP_HT,a0
        clr.b   0(a0,d3.w)
.n:     addq.w  #1,d3
        cmpi.w  #52,d3
        bne   .l
.x:     rts
mdp_htclr:
        lea     MDP_HT,a0
        moveq   #12,d0
.c:     clr.l   (a0)+
        dbra    d0,.c
        rts
mdp_wline:
        dc.b    V_A179,V_A180,V_A181,V_A182,V_A183,V_A184,V_A185,V_A186
mdp_wman:
        dc.b    V_C011,V_C011,V_C012,V_C013,V_C014,V_C012,V_C016,V_C016
        even

;============================================================================
        BLOCK mdp_mres LOW
; replaces the man's rescue sound ("moveq #$79,d0 / not.b d0 / pea 3.w / ... jsr $3E91C",
; then bra $1B6FC): with MD+ voices on, one of his Neo Geo lines instead (via MDP_RESC)
mdp_mres:
        cmpi.b  #1,MDP_ON
        bne   .md
        tst.b   SOUNDS_ON
        beq   .md
        lea     mdp_mline,a0
        bra   mdp_rline
.md:    pea     $3.w
        pea     $86.w
        jsr     $3E91C
        addq.l  #8,sp
        jmp     $1B6FC
; the Neo Geo's rescue lines ($80DE6 / $80FF2), rand & 3: women $80 $80 $D2 $D3, men $86 $F0
; $F1 $F2 (sound id - 33 = sample: A095 A095 A177 A178 / A101 C008 C009 C010 = take of C008)
mdp_rline:
        clr.b   MDP_HUM             ; (no "rescue the humans" after a rescue)
        jsr     mdp_rnd
        rol.w   #2,d1               ; (the top bits: the low ones of this generator repeat)
        andi.w  #3,d1
        move.b  0(a0,d1.w),MDP_RESC
        jmp     $1B6FC
mdp_fline:
        dc.b    V_A095,V_A095,V_A177,V_A178
mdp_mline:
        dc.b    V_A101,V_C008,V_C009,V_C008

;============================================================================
        BLOCK mdp_fres LOW
; replaces the woman's rescue sound ("pea 3.w / move.l d0,-(sp)", d0 = $80, then the jsr
; $3E91C): with MD+ voices on, one of her Neo Geo lines instead (via MDP_RESC)
mdp_fres:
        cmpi.b  #1,MDP_ON
        bne   .md
        tst.b   SOUNDS_ON
        beq   .md
        lea     mdp_fline,a0
        jmp     mdp_rline
.md:    pea     $3.w
        move.l  d0,-(sp)
        jsr     $3E91C
        addq.l  #8,sp
        jmp     $1B6FC
