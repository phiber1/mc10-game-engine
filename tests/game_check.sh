#!/bin/sh
# game_check.sh: headless checks of the game prototype (bench/game.asm).
# Run from the repository root with "make check".  Loads build/game.bin
# with LOADM from an SD folder, as a player would.  Needs the VMC10 for
# Linux emulator's headless harness and ROMs (VMC10=..., default
# ~/vmc10-linux).
set -u
VMC10=${VMC10:-$HOME/vmc10-linux}
H=$VMC10/build/headless
R=$VMC10/roms
BIN=build/game.bin
LST=build/game.lst
SD=build/sd-check
mkdir -p $SD && cp $BIN $SD/GAME.BIN
for n in 1 2 3 4; do cp build/ovl$n.bin $SD/BOSS$n.BIN; done   # the boss overlays
pass=0; fail=0
check() {   # name, condition (shell test)
    if eval "$2"; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}
sym() { printf '%04X' 0x$(awk '/Symbol Table/{p=1} p' $LST | tr '|' '\n' | awk -v n=$1 '$1==n{print $3}'); }
# load the game the way a player does: LOADM from the SD card, then EXEC
# (past the colour check with SPACE, so a test's own SPACE starts a game from the title)
run() { $H $R/MC10.BIN mcx32sd:$R/mcx32sd_flash.bin 8k sd:$SD frames:200 'type:LOADM"GAME"\nEXEC\n' frames:120 'type: ' frames:30 "$@"; }
memval() { grep "^mem $1" | sed -n "${2:-1}p" | awk '{print strtonum("0x"$3)}'; }

SHIP=$(sym ship); MODE=$(sym mode); WARPF=$(sym warpf); AREA=$(sym area)
ALIENS=$(sym aliens); SHOTS_END=$(sym shots_end); AREA_DONE=$(sym area_done); ALIVE=$(sym alive)

# 1. In play, the ship answers the controls (A = left) and the game is in
#    play mode with normal star speed.
out=$(run frames:30 'type: ' frames:220 mem:$SHIP,1 'type:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' frames:60 mem:$SHIP,1 mem:$MODE,1 mem:$WARPF,1)
x0=$(echo "$out" | memval $SHIP 1); x1=$(echo "$out" | memval $SHIP 2)
check "ship moves left when A is held (x $x0 -> $x1)" "[ $x1 -lt $x0 ]"
check "play mode with normal stars" "[ $(echo "$out" | memval $MODE) -eq 0 ] && [ $(echo "$out" | memval $WARPF) -eq 1 ]"

# 1a. The colour check comes once, right after loading: an orange block
#     (C swaps it to blue), then SPACE leads to the title, without it.
BLK=48CE    # TXT_AT(70,14): the block's first byte
raw() { $H $R/MC10.BIN mcx32sd:$R/mcx32sd_flash.bin 8k sd:$SD frames:200 'type:LOADM"GAME"\nEXEC\n' frames:120 "$@"; }
out=$(raw mem:$BLK,4 type:C frames:90 mem:$BLK,4 'type: ' frames:60 mem:$BLK,4 mem:$SHIP,1)
b0=$(echo "$out" | grep "^mem $BLK" | sed -n 1p | cut -d: -f2 | tr -d ' ')
b1=$(echo "$out" | grep "^mem $BLK" | sed -n 2p | cut -d: -f2 | tr -d ' ')
b2=$(echo "$out" | grep "^mem $BLK" | sed -n 3p | cut -d: -f2 | tr -d ' ')
check "colour check after loading: orange block ($b0), C swaps it ($b1), SPACE goes to the title ($b2)" "[ $b0 = AAAAAAAA ] && [ $b1 = 55555555 ] && [ $b2 = 00000000 ]"

# 1b. The status bar is on screen: rows 0-6 match status_buf (sampled a
#     few times during play, as sprites cross it).
SB=$(sym status_buf); BAND_BYTES=224
bad=0
for t in 300 900 1500; do
    out=$(run frames:30 'type: ' frames:$t mem:4000,224 mem:$SB,224)
    scr=$(echo "$out" | grep '^mem 4000' | cut -d: -f2); buf=$(echo "$out" | grep "^mem $SB" | cut -d: -f2)
    [ -n "$scr" ] && [ "$scr" = "$buf" ] || bad=$((bad+1))
done
check "the status bar is on screen and intact ($bad of 3 samples wrong)" "[ $bad -le 1 ]"
out=$(run frames:30 'type: ' frames:400 mem:$(printf '%04X' $((0x$SB + 32))),32)
check "the status bar has text in it" "[ \"\$(echo \"$out\" | grep '^mem' | cut -d: -f2 | tr -d ' 0')\" != '' ]"

# 2. Normal play: the area's waves come one after another, and neither
#    the area's end nor the boss comes before the last wave (area 1 has
#    3).  Sampled every second over a minute of firing while sweeping.
WVI=$(sym wv_index); BSTATE=$(sym boss_state)
mv=""; for i in $(seq 1 20); do mv="$mv A A A A A A A A A A S S S S S S S S S S S S S S S S S S S S A A A A A A A A A A"; done
samples=""; for i in $(seq 1 60); do samples="$samples frames:60 mem:$WVI,1 mem:$AREA_DONE,1 mem:$BSTATE,1 mem:$AREA,1"; done
early=$(run frames:30 'type: ' frames:200 poke:$(sym lives),09 "type:$mv$mv" $samples | grep '^mem' | paste - - - - | \
        awk '{w=strtonum("0x"$3); d=strtonum("0x"$6); b=strtonum("0x"$9); a=strtonum("0x"$12); if(a==0 && (d||b) && w<3) e++} END{print e+0}')
check "no early area end or boss in normal play (bad samples: $early)" "[ $early -eq 0 ]"

# 2a. At most 8 live aliens fly at once (a sliding window: the rest of a
#     wave waits its turn), sampled every 10 frames over two minutes.
samples=""; for i in $(seq 1 700); do samples="$samples frames:10 mem:$ALIVE,1"; done
mv2=""; for i in $(seq 1 60); do mv2="$mv2 A A A A A A A A A A S S S S S S S S S S S S S S S S S S S S A A A A A A A A A A"; done
most=$(run frames:30 'type: ' frames:250 poke:$(sym lives),09 "type:$mv2" $samples | grep '^mem' | awk '{a=strtonum("0x"$3); if(a>m)m=a} END{print m+0}')
check "never more than 8 aliens flying (most seen: $most)" "[ $most -le 8 ] && [ $most -ge 6 ]"

# 2c. Staggered-lane waves never put an alien off the side, even when
#     more aliens launch than the wave has lanes (relaunched survivors):
#     area 2's dart wave (lanes from x 103, step -12) is given 14
#     launches with the alive counter held open so all 10 slots fill.
#     (The bug: lane 10 entered at x 251 and stuck, wrapping onto the
#     next rows, unshootable.)
A2=$(sym area2); W2=$(printf '%04X' $((0x$A2 + 8)))
samples=""; for i in $(seq 1 40); do samples="$samples frames:15 poke:$ALIVE,00 mem:$ALIENS,200"; done
offside=$(run frames:30 'type: ' frames:300 poke:$(sym lives),09 poke:$(sym wv_ptr),$W2 poke:$(sym wv_x),67 poke:$(sym wv_left),0E poke:$(sym wv_timer),01 $samples | \
    grep "^mem $ALIENS" | awk '{for(i=0;i<10;i++){b=3+i*20; x=strtonum("0x"$(b)); s=$(b+8)$(b+9); f=strtonum("0x"$(b+16)); if(s!="0000" && x>=118 && !(f%2)) o++}} END{print o+0}')
check "aliens stay on screen when launches outnumber lanes (samples off: $offside)" "[ $offside -eq 0 ]"

# 2d. Wrap-around paths: area 1's sweep wave (saucers drifting right
#     through the edge) is forced; aliens are seen crossing from the right
#     edge to the left, and none is left stuck straddling the edge.
W4=$(printf '%04X' $((0x$(sym area1) + 3*8)))
samples=""; for i in $(seq 1 600); do samples="$samples frames:1 mem:$ALIENS,200"; done
res=$(run frames:30 'type: ' frames:300 poke:$(sym lives),09 poke:$(sym wv_ptr),$W4 poke:$(sym wv_x),14 poke:$(sym wv_left),06 poke:$(sym wv_timer),01 $samples | \
    grep "^mem $ALIENS" | awk '{for(i=0;i<10;i++){b=3+i*20; x=strtonum("0x"$(b)); s=$(b+8)$(b+9); f=strtonum("0x"$(b+16)); if(s!="0000" && f%2){ if(px[i]>110 && x<15) cr++; if(x>=118){st[i]++; if(st[i]>mx) mx=st[i]} else st[i]=0; px[i]=x } else {px[i]=0; st[i]=0} }} END{printf "%d %d", cr+0, mx+0}')
set -- $res
check "wrapping aliens cross from one side to the other ($1 crossings)" "[ $1 -ge 2 ]"
check "none stays straddling the edge (longest: $2 frames)" "[ $2 -le 30 ]"

# 2e. Circling aliens (area 1's orbiter wave, forced) come back in from
#     the top at a new random x after each dive (owner: they used to dive
#     in the same columns, so a player could wait them out), stay on
#     screen, and wait out of sight first (an instant jump looked like a
#     glitch) until the whole column has left the screen.
W3=$(printf '%04X' $((0x$(sym area1) + 2*8)))
samples=""; for i in $(seq 1 1800); do samples="$samples frames:1 mem:$ALIENS,200"; done
res=$(run frames:30 'type: ' frames:300 poke:$(sym lives),09 poke:$(sym wv_ptr),$W3 poke:$(sym wv_x),23 poke:$(sym wv_left),06 poke:$(sym wv_timer),01 $samples | \
    grep "^mem $ALIENS" | awk '{nv=0; for(i=0;i<10;i++){b=3+i*20; if($(b+8)$(b+9)!="0000" && int(strtonum("0x"$(b+16))/2)%4 && strtonum("0x"$(b+2))<190) nv++} if(!nv) le=NR;
      for(i=0;i<10;i++){b=3+i*20; x=strtonum("0x"$(b)); y=strtonum("0x"$(b+2)); s=$(b+8)$(b+9); f=strtonum("0x"$(b+16)); if(s!="0000" && int(f/2)%4){ if(py[i]!="" && py[i]<200 && y>=224){n++; if(!mn||x<mn)mn=x; if(x>mx)mx=x} if(y<192 && x>=118) off++; v=(y<190); if(pv[i]=="1" && !v) g[i]=NR; if(pv[i]=="0" && v && g[i]){d=NR-g[i]; if(!gm||d<gm)gm=d; if(le<g[i]) ov++; g[i]=0} pv[i]=v } else {pv[i]=""; g[i]=0} py[i]=(s!="0000")?y:""}} END{printf "%d %d %d %d %d", n+0, mx-mn, off+0, gm+0, ov+0}')
set -- $res
check "circling aliens re-enter at new spots ($1 re-entries spread over $2 pixels)" "[ $1 -ge 8 ] && [ $2 -ge 50 ]"
check "and stay on screen (samples off: $3)" "[ $3 -eq 0 ]"
check "they stay out of sight a moment before coming back (shortest: $4 frames)" "[ $4 -ge 40 ]"
check "and only after the whole column has left the screen (early: $5)" "[ $5 -eq 0 ]"

# 2b. Losing a ship clears the field: with aliens flying, the ship is
#     lost (dead set, its countdown about to end); right after the respawn
#     no alien is left, and later the survivors come back.
DEAD=$(sym dead); DEADT=$(sym dead_t); LIVESV=$(sym lives); ALIVEV=$(sym alive)
out=$(run frames:30 'type: ' frames:400 poke:$LIVESV,09 mem:$ALIVEV,1 poke:$DEAD,01 poke:$DEADT,02 frames:10 mem:$ALIVEV,1 frames:300 mem:$ALIVEV,1 mem:$DEAD,1)
a0=$(echo "$out" | memval $ALIVEV 1); a1=$(echo "$out" | memval $ALIVEV 2); a2=$(echo "$out" | memval $ALIVEV 3)
check "aliens flying ($a0) are cleared when the ship is lost ($a1 after the respawn)" "[ $a0 -gt 0 ] && [ $a1 -eq 0 ] && [ $(echo "$out" | memval $DEAD) -eq 0 ]"
check "and they come back afterwards ($a2)" "[ $a2 -gt 0 ]"

# 3. A won area (waves cleared, boss defeated) goes through salute, warp,
#    map and arrival to the next area, back in play mode.
n=$(( 0x$SHOTS_END - 0x$ALIENS ))
z=$(printf '0%.0s' $(seq 1 $((n*2))))
out=$(run frames:30 'type: ' frames:300 "poke:$ALIENS,$z" poke:$AREA_DONE,01 poke:$ALIVE,00 poke:$(sym boss_state),04 frames:700 mem:$AREA,1 mem:$MODE,1 mem:$WARPF,1)
check "area clear leads to area 2, back in play" "[ $(echo "$out" | memval $AREA) -eq 1 ] && [ $(echo "$out" | memval $MODE) -eq 0 ] && [ $(echo "$out" | memval $WARPF) -eq 1 ]"

# 3a. Boss overlays: area 1's boss is loaded from BOSS1.BIN before play,
#     and the warp to area 2 loads BOSS2.BIN during the map screen (its
#     header names boss2's hull).  Without the boss files the game stops
#     with a message (CANNOT LOAD...) instead of running on.
OC=$(sym ovl_cur); B2D=$(awk '/Symbol Table/{p=1} p' build/ovl2.lst | tr '|' '\n' | awk '$1=="boss2_dsc"{print $3}')
out=$(run frames:30 'type: ' frames:200 mem:$OC,1 "poke:$ALIENS,$z" poke:$AREA_DONE,01 poke:$ALIVE,00 poke:$(sym boss_state),04 frames:700 mem:$OC,1 mem:A200,2)
o1=$(echo "$out" | memval $OC 1); o2=$(echo "$out" | memval $OC 2); hd=$(echo "$out" | grep "^mem A200" | cut -d: -f2 | tr -d ' ')
check "boss overlays load: area 1 ($o1), then area 2 ($o2, header $hd = boss2 $B2D)" "[ $o1 -eq 1 ] && [ $o2 -eq 2 ] && [ $hd = $B2D ]"
NB=build/sd-noboss; mkdir -p $NB && rm -f $NB/BOSS*.BIN && cp $BIN $NB/GAME.BIN
out=$($H $R/MC10.BIN mcx32sd:$R/mcx32sd_flash.bin 8k sd:$NB frames:200 'type:LOADM"GAME"\nEXEC\n' frames:120 'type: ' frames:30 'type: ' frames:200 mem:$OC,1 mem:$(sym ld_t),1 mem:$MODE,1 frames:200 mem:$(sym ld_t),1)
e1=$(echo "$out" | memval $(sym ld_t) 1); e2=$(echo "$out" | memval $(sym ld_t) 2)
check "missing boss file: the game stops with a message (BIOS error $e1, still $e2)" "[ $(echo "$out" | memval $OC 1) -eq 0 ] && [ $e1 -gt 4 ] && [ $e1 -eq $e2 ]"

# 4. The boss: with the waves cleared it arrives; shots up the channel
#    into its core (boss held still, ship lined up) destroy it, and the
#    victory warp leads to area 2.
BS=$(sym boss_state); HP=$(sym boss_hp); LIVES=$(sym lives); BOSS=$(sym boss)
BDX=$(printf '%04X' $((0x$BOSS + 4)))
sp=$(printf '%*s' 200 '')
out=$(run frames:30 'type: ' frames:300 "poke:$ALIENS,$z" poke:$AREA_DONE,01 poke:$ALIVE,00 frames:200 mem:$BS,1 poke:$HP,03 poke:$LIVES,09 poke:$BOSS,32 poke:$BDX,0000 poke:$SHIP,3A "type:$sp" frames:900 mem:$AREA,1 mem:$MODE,1)
check "the boss arrives after the waves" "[ $(echo "$out" | memval $BS 1) -eq 2 ]"
check "hits on the core destroy it; warp to area 2" "[ $(echo "$out" | memval $AREA) -eq 1 ] && [ $(echo "$out" | memval $MODE) -eq 0 ]"

# 4b. Area 2's boss has envoys: its core stays shut (shots do nothing)
#     until both envoys are destroyed, then it can be killed.  The ship is
#     kept invulnerable (the envoys bomb heavily).
EL=$(sym env_left); IV=$(sym invuln)
keep=""; for i in $(seq 1 10); do keep="$keep frames:20 poke:$IV,F0"; done
out=$(run frames:30 'type: ' frames:300 poke:$AREA,01 "poke:$ALIENS,$z" poke:$AREA_DONE,01 poke:$ALIVE,00 poke:$LIVES,09 $keep frames:130 \
      poke:$BOSS,32 poke:$BDX,0000 poke:$SHIP,3A "type:$sp" $keep mem:$HP,1 mem:$EL,1 \
      poke:$SHIP,26 "type:$sp" $keep poke:$SHIP,4E "type:$sp" $keep mem:$EL,1 \
      poke:$SHIP,3A "type:$sp" $keep $keep mem:$BS,1 mem:$AREA,1)
hp0=$(echo "$out" | memval $HP 1); e0=$(echo "$out" | memval $EL 1); e1=$(echo "$out" | memval $EL 2)
check "shut core takes no hits while envoys fly (core $hp0 of 10, envoys $e0)" "[ $hp0 -eq 10 ] && [ $e0 -eq 2 ]"
check "both envoys destroyed (left: $e1)" "[ $e1 -eq 0 ]"
bs3=$(echo "$out" | memval $BS 1)
check "then the open core is destroyed (boss state $bs3: dying, defeated or won)" "[ $bs3 -ge 3 ] || [ $bs3 -eq 0 ]"

# 4d. Area 4's fortress: it descends and stays put; its three cores are
#     shut while the envoys fly; with the envoys down the two side cores
#     open but the centre stays shut; with both side cores destroyed the
#     centre opens, and destroying it ends the boss.  (Fortress x 46:
#     ship x 32/82 under the envoys, 50/68 under the side cores, 59 under
#     the centre.)
CS=$(sym core_s)
keep3="$keep $keep $keep"
out=$(run frames:30 'type: ' frames:300 poke:$AREA,03 "poke:$ALIENS,$z" poke:$AREA_DONE,01 poke:$ALIVE,00 poke:$LIVES,09 $keep $keep frames:200 \
      mem:$BOSS,1 mem:$CS,3 \
      poke:$SHIP,3B "type:$sp" $keep3 mem:$HP,3 \
      poke:$SHIP,20 "type:$sp" $keep3 poke:$SHIP,20 "type:$sp" $keep3 \
      poke:$SHIP,52 "type:$sp" $keep3 poke:$SHIP,52 "type:$sp" $keep3 mem:$EL,1 mem:$CS,3 \
      poke:$SHIP,3B "type:$sp" $keep3 mem:$HP,3 \
      poke:$SHIP,32 "type:$sp" $keep3 poke:$SHIP,44 "type:$sp" $keep3 mem:$CS,3 mem:$BOSS,1 \
      poke:$SHIP,3B "type:$sp" $keep3 poke:$SHIP,3B "type:$sp" $keep3 poke:$SHIP,3B "type:$sp" $keep3 mem:$BS,1 mem:$AREA,1)
bx0=$(echo "$out" | memval $BOSS 1); bx1=$(echo "$out" | memval $BOSS 2)
cs0=$(echo "$out" | grep "^mem $CS" | sed -n 1p | cut -d: -f2 | tr -d ' ')
hp0=$(echo "$out" | grep "^mem $HP" | sed -n 1p | cut -d: -f2 | tr -d ' ')
el=$(echo "$out" | memval $EL 1)
cs1=$(echo "$out" | grep "^mem $CS" | sed -n 2p | cut -d: -f2 | tr -d ' ')
hp1=$(echo "$out" | grep "^mem $HP" | sed -n 2p | cut -d: -f2 | tr -d ' ')
cs2=$(echo "$out" | grep "^mem $CS" | sed -n 3p | cut -d: -f2 | tr -d ' ')
bs4=$(echo "$out" | memval $BS 1)
check "the fortress stays put (x $bx0, later $bx1) with its cores shut (states $cs0, hits $hp0)" "[ $bx0 -eq 46 ] && [ $bx1 -eq 46 ] && [ $cs0 = 000000 ] && [ $hp0 = 06060E ]"
check "envoys down: the side cores open, the centre stays shut and unhurt (envoys $el, states $cs1, hits $hp1)" "[ $el -eq 0 ] && [ $cs1 = 010100 ] && [ \$(echo $hp1 | cut -c5-6) = 0E ]"
check "side cores destroyed: the centre opens (states $cs2), and destroying it ends the boss (state $bs4)" "[ $cs2 = 020201 ] && { [ $bs4 -ge 3 ] || [ $bs4 -eq 0 ]; }"

# 4c. No safe spot ("pizza break"): a ship that never moves is lost
#     within 30 seconds of area 1, at the start position and elsewhere.
#     (The bug: area 1's first wave dropped bombs at fixed points of its
#     path, and an unmoving ship between them lasted for minutes.)
DEADV=$(sym dead)
s=""; for i in $(seq 1 120); do s="$s frames:15 mem:$DEADV,1"; done
slow=""
for x in start 0 20 58 100 111; do
    p=""; [ $x != start ] && p="frames:60 poke:$SHIP,$(printf %02X $x) frames:60 poke:$SHIP,$(printf %02X $x)"
    t=$(run frames:30 'type: ' frames:2 $p $s | grep '^mem' | awk '{n++; if(strtonum("0x"$3) && !t) t=n} END{print t? int(t/4) : -1}')
    [ $t -lt 0 ] && slow="$slow x=$x"
    times="${times:-}$x:${t}s "
done
check "an unmoving ship is lost within 30 s ($times)" "[ -z \"$slow\" ]"

# 5. The frame budget holds in realistic play: two minutes of sweeping
#    side to side with fire held, through the area's full waves (the
#    old test, firing straight up from the centre, missed a regression).
mv=""; for i in $(seq 1 60); do mv="$mv A A A A A A A A A A S S S S S S S S S S S S S S S S S S S S A A A A A A A A A A"; done
over=$(run dbgport:BE00 frames:30 'type: ' frames:250 "type:$mv" frames:7200 | grep 'val=\$BB' | sed 's/.*dt=\([0-9]*\).*/\1/' | \
       awk '$1>14700 && $1<100000 {o++} END{printf "%.1f", 100*o/NR}')
check "frames over budget, sweeping with fire held: ${over}% (limit 2%)" "awk 'BEGIN{exit !($over <= 2.0)}'"

echo "----"
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
