; Xeno Crisis (Genesis v1.0.0) - Roll priority + Pause HUD
; Assembled into the free area at the end of the ROM ($3FFE18-$3FFFFF).

VDP_DATA    equ $C00000
VDP_CTRL    equ $C00004
SAT         equ $DC00
SPRBUF      equ $FF1380         ; game's sprite table copy (DMA'd to SAT every unpaused frame)
LAST        equ 79              ; H40 mode: 80 sprites
ORIG_VSYNC  equ $519E6
PAUSED      equ $FF000A         ; 1 while paused
TWOPLAYER   equ $FF1604         ; 1 in a 2-player game

STATS       equ $FF3306         ; per-player stats block, 66 bytes each
P1_OBJ      equ $FF228C         ; player 1 object (P2 = +64)

ICON_ATTR   equ $E000           ; priority + palette 3 (same as the game's pop-up icons)
DIGIT_ATTR  equ $A000           ; priority + palette 1 (same as the game's pop-up digits)
TILE_HEART  equ $67
TILE_GREN   equ $70
TILE_TAGS   equ $79
TILE_ZERO   equ $29

ROW0        equ 24              ; y of first icon row
ROWSTEP     equ 44
NUMOFS      equ 26              ; number sits this far below the icon

        org $3FFE20

;----------------------------------------------------------------------------
; Roll priority hook (jumped to from $262A)
;----------------------------------------------------------------------------
roll_hook:
        move.w  a3,d0               ; roll button mask
        beq.s   .fire
        and.w   $3a(sp),d0          ; newly pressed
        cmp.w   a3,d0
        bne.s   .fire
        jmp     $730E               ; start roll (skip this frame's shot)
.fire:  tst.w   $46(sp)             ; fire held?
        bne.s   .shoot
        jmp     $26F4
.shoot: jmp     $2632

;----------------------------------------------------------------------------
; Pause HUD: replaces "jsr $519E6" in the paused loop at $3168A
;----------------------------------------------------------------------------
pause_hud:
        jsr     ORIG_VSYNC
        tst.b   PAUSED              ; only while the game is paused
        bne.s   .go
        rts
.go:    movem.l d0-d7/a0-a6,-(sp)
        move.w  sr,-(sp)
        ori.w   #$0700,sr
        lea     VDP_CTRL,a5
        lea     VDP_DATA,a6
        move.w  #$8F02,(a5)         ; auto-increment 2
        ; rebuild the sprite table from slot 0: HUD first, then the game's visible sprites
        move.l  #$40000000|(SAT&$3FFF)<<16|(SAT>>14),(a5)
        moveq   #0,d6               ; d6 = next slot

        lea     STATS,a0
        lea     P1_OBJ,a1
        moveq   #4,d5               ; column x for P1
        bsr     player
        lea     66(a0),a0
        lea     64(a1),a1
        tst.b   TWOPLAYER           ; 2-player game?
        beq.s   .game
        move.w  #292,d5
        bsr     player

.game:  ; walk the game's sprite chain in its RAM copy (restored by the game's DMA on unpause)
        lea     SPRBUF,a2
        moveq   #0,d1
.walk:  move.w  d1,d0
        lsl.w   #3,d0
        lea     0(a2,d0.w),a3
        move.w  (a3),d0
        andi.w  #$3FF,d0
        cmpi.w  #128-32,d0          ; skip sprites parked off-screen
        bcs.s   .next
        cmpi.w  #128+224,d0
        bcc.s   .next
        cmpi.w  #LAST+1,d6
        beq.s   .term
        move.w  (a3),(a6)           ; y
        moveq   #0,d2
        move.b  2(a3),d2            ; size
        lsl.w   #8,d2
        addq.w  #1,d6
        bsr     setlink
        move.w  d2,(a6)
        move.w  4(a3),(a6)          ; attr
        move.w  6(a3),(a6)          ; x
.next:  moveq   #$7F,d1
        and.b   3(a3),d1            ; next in chain (0 = end)
        bne.s   .walk
.term:  cmpi.w  #LAST+1,d6          ; terminate the chain with a hidden sprite
        beq.s   .done
        moveq   #0,d0
        move.w  d0,(a6)
        move.w  d0,(a6)
        move.w  d0,(a6)
        move.w  d0,(a6)
.done:
        move.w  (sp)+,sr
        movem.l (sp)+,d0-d7/a0-a6
        rts

; setlink: d2 |= link to slot d6 (0 if d6 is past the last slot)
setlink: cmpi.w  #LAST+1,d6
        beq.s   .end
        or.w    d6,d2
.end:   rts

;----------------------------------------------------------------------------
; player: a0 = stats block, a1 = player object, d5 = column x
;----------------------------------------------------------------------------
player:
        moveq   #ROW0,d4
        move.w  #ICON_ATTR|TILE_HEART,d3
        move.w  $28(a1),d0          ; health
        bsr     item
        move.w  $14(a0),d3          ; current weapon icon
        ori.w   #ICON_ATTR,d3
        moveq   #0,d0
        move.b  $0D(a0),d0          ; special weapon: seconds left
        bne.s   .spec
        move.b  $19(a0),d0          ; default weapon: ammo
.spec:  bsr     item
        move.w  #ICON_ATTR|TILE_GREN,d3
        moveq   #0,d0
        move.b  $1B(a0),d0          ; grenades
        bsr     item
        move.w  #ICON_ATTR|TILE_TAGS,d3
        move.w  $1C(a0),d0          ; dog tags
        ; fall through

;----------------------------------------------------------------------------
; item: d3 = icon attr, d0 = value, d4 = row y (advanced), d5 = column x
;----------------------------------------------------------------------------
item:
        move.w  d0,-(sp)
        move.w  d5,d0
        move.w  d4,d1
        moveq   #$0A,d2             ; 3x3 cells
        bsr     emit
        move.w  (sp)+,d0
        ; split value into digits (0..999)
        tst.w   d0
        bpl.s   .pos
        moveq   #0,d0
.pos:   cmpi.w  #999,d0
        bls.s   .ok
        move.w  #999,d0
.ok:    moveq   #0,d2               ; digit count
.split: ext.l   d0
        divu    #10,d0
        swap    d0
        move.w  d0,-(sp)            ; remainder = digit
        clr.w   d0
        swap    d0
        addq.w  #1,d2
        tst.w   d0
        bne.s   .split
        ; x = column + 12 - count*4
        move.w  d2,d0
        lsl.w   #2,d0
        neg.w   d0
        add.w   d5,d0
        addi.w  #12,d0
        move.w  d4,d1
        addi.w  #NUMOFS,d1
        move.w  d2,a3               ; a3 = digits left
.dig:   move.w  (sp)+,d3
        addi.w  #DIGIT_ATTR|TILE_ZERO,d3
        moveq   #0,d2               ; 1x1
        bsr     emit
        addq.w  #8,d0
        subq.w  #1,a3
        move.w  a3,d2
        bne.s   .dig
        addi.w  #ROWSTEP,d4
        rts

;----------------------------------------------------------------------------
; emit one sprite: d0 = x, d1 = y, d2 = size, d3 = attr. Uses d6 (slot), d7 (final link)
; Drops the sprite if all slots are used.
;----------------------------------------------------------------------------
emit:
        cmpi.w  #LAST+1,d6
        beq.s   .full
        move.w  d1,a2
        lea     128(a2),a2
        move.w  a2,(a6)             ; y (d1 preserved)
        lsl.w   #8,d2
        addq.w  #1,d6
        bsr     setlink
        move.w  d2,(a6)
        move.w  d3,(a6)
        move.w  d0,a2
        lea     128(a2),a2
        move.w  a2,(a6)             ; x (d0 preserved)
.full:  rts

end_of_code:
