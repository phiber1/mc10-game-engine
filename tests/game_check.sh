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
pass=0; fail=0
check() {   # name, condition (shell test)
    if eval "$2"; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}
sym() { printf '%04X' 0x$(awk '/Symbol Table/{p=1} p' $LST | tr '|' '\n' | awk -v n=$1 '$1==n{print $3}'); }
# load the game the way a player does: LOADM from the SD card, then EXEC
run() { $H $R/MC10.BIN mcx32sd:$R/mcx32sd_flash.bin 8k sd:$SD frames:200 'type:LOADM"GAME"\nEXEC\n' frames:120 "$@"; }
memval() { grep "^mem $1" | sed -n "${2:-1}p" | awk '{print strtonum("0x"$3)}'; }

SHIP=$(sym ship); MODE=$(sym mode); WARPF=$(sym warpf); AREA=$(sym area)
ALIENS=$(sym aliens); SHOTS_END=$(sym shots_end); AREA_DONE=$(sym area_done); ALIVE=$(sym alive)

# 1. In play, the ship answers the controls (A = left) and the game is in
#    play mode with normal star speed.
out=$(run frames:30 'type: ' frames:220 mem:$SHIP,1 'type:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' frames:60 mem:$SHIP,1 mem:$MODE,1 mem:$WARPF,1)
x0=$(echo "$out" | memval $SHIP 1); x1=$(echo "$out" | memval $SHIP 2)
check "ship moves left when A is held (x $x0 -> $x1)" "[ $x1 -lt $x0 ]"
check "play mode with normal stars" "[ $(echo "$out" | memval $MODE) -eq 0 ] && [ $(echo "$out" | memval $WARPF) -eq 1 ]"

# 2. A won area (waves cleared, boss defeated) goes through salute, warp,
#    map and arrival to the next area, back in play mode.
n=$(( 0x$SHOTS_END - 0x$ALIENS ))
z=$(printf '0%.0s' $(seq 1 $((n*2))))
out=$(run frames:30 'type: ' frames:300 "poke:$ALIENS,$z" poke:$AREA_DONE,01 poke:$ALIVE,00 poke:$(sym boss_state),04 frames:700 mem:$AREA,1 mem:$MODE,1 mem:$WARPF,1)
check "area clear leads to area 2, back in play" "[ $(echo "$out" | memval $AREA) -eq 1 ] && [ $(echo "$out" | memval $MODE) -eq 0 ] && [ $(echo "$out" | memval $WARPF) -eq 1 ]"

# 3. The boss: with the waves cleared it arrives; shots up the channel
#    into its core (boss held still, ship lined up) destroy it, and the
#    victory warp leads to area 2.
BS=$(sym boss_state); HP=$(sym boss_hp); LIVES=$(sym lives); BOSS=$(sym boss)
BDX=$(printf '%04X' $((0x$BOSS + 4)))
sp=$(printf '%*s' 200 '')
out=$(run frames:30 'type: ' frames:300 "poke:$ALIENS,$z" poke:$AREA_DONE,01 poke:$ALIVE,00 frames:200 mem:$BS,1 poke:$HP,03 poke:$LIVES,09 poke:$BOSS,32 poke:$BDX,0000 poke:$SHIP,3A "type:$sp" frames:900 mem:$AREA,1 mem:$MODE,1)
check "the boss arrives after the waves" "[ $(echo "$out" | memval $BS 1) -eq 2 ]"
check "hits on the core destroy it; warp to area 2" "[ $(echo "$out" | memval $AREA) -eq 1 ] && [ $(echo "$out" | memval $MODE) -eq 0 ]"

# 4. The frame budget holds with fire held for ~30 s.
sp=$(printf '%*s' 400 '')
over=$(run dbgport:BE00 frames:30 'type: ' frames:200 "type:$sp" frames:1800 | grep 'val=\$BB' | sed 's/.*dt=\([0-9]*\).*/\1/' | awk '$1>14700{o++} END{printf "%d", 100*o/NR}')
check "frames over budget with fire held: ${over}% (limit 3%)" "[ $over -le 3 ]"

echo "----"
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
