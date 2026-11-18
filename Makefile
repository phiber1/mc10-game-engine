# mc10-game-engine build
#
#   make                 build every program in bench/ (DEBUG=1 by default)
#   make DEBUG=0         release build: no debug-port writes
#   make run-tick        run a program in the emulator (vmc10 --mcx32sd --8k)
#   make variants        sprite test builds: run-sp_m0 ... run-sp_a5 (see below)
#   make smdemo          sprite manager demo: run-sm_m, run-sm_a (+ _mk, _ak meter)
#   make run-shooter     playable test: W A S Z / arrows, SPACE fires
#                        (run-shooterk: with the CPU meter)
#   make run-waves       attack waves on scripted flight paths (run-wavesk: meter)
#   make run-game        the game prototype: title, score, lives (run-gamek: meter)
#   make check           headless checks of the game prototype
#   make run-view        a still display of every sprite in a sprite file
#                        (VIEW=sprites/NAME.spr, default sprites/game.spr)
#   make log-tick        run it headless and print the debug-port log
#
# Each bench/NAME.asm builds build/NAME.bin: a DECB binary for the
# MCX32-SD's LOADM (8K mod + MCX32-SD required), with a main segment at
# $6000-$ADFF and optionally a low one at $0400-$1FFF.  Programs start at
# $6000.  (build/NAME.c10, for CLOADM, still builds on request for
# single-segment programs.)

VMC10   ?= $(HOME)/vmc10-linux
EMU     ?= $(VMC10)/vmc10
HEADLESS?= $(VMC10)/build/headless
ROMS    ?= $(VMC10)/roms
DEBUG   ?= 1
CPPDEFS ?=

LOAD    := 6000
CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -std=c11

PROGS   := $(basename $(notdir $(wildcard bench/*.asm)))
ENGINE  := $(wildcard engine/*.asm engine/*.inc)
SPRITES := $(patsubst sprites/%.spr,build/%_spr.inc,$(wildcard sprites/*.spr))

all: $(foreach p,$(PROGS),build/$(p).bin)

build/mkc10: tools/mkc10.c | build
	$(CC) $(CFLAGS) -o $@ $<

build/p2decb: tools/p2decb.c | build
	$(CC) $(CFLAGS) -o $@ $<

build/spritec: tools/spritec.c | build
	$(CC) $(CFLAGS) -o $@ $<

# compiled sprites: sprites/NAME.spr -> build/NAME_spr.inc
build/%_spr.inc: sprites/%.spr build/spritec
	build/spritec $< > $@

build:
	mkdir -p build

# cpp handles #include/#define, then ASL assembles and p2bin extracts
build/%.s: bench/%.asm $(ENGINE) $(SPRITES) | build
	$(CC) -E -P -w -x assembler-with-cpp -Iengine -Ibuild -DDEBUG=$(DEBUG) $(CPPDEFS) $< -o $@

build/%.p: build/%.s
	cd build && asl -q -L -U $*.s

build/%.raw: build/%.p
	p2bin -q -r '$$$(LOAD)-$$' $< $@

build/%.c10: build/%.raw build/mkc10
	build/mkc10 $< $@ $(shell echo $* | tr a-z A-Z | cut -c1-8) $(LOAD) $(LOAD)

# The DECB binary straight from ASL's object file, every byte checked to
# lie in the low or main segment (clear of what LOADM itself uses)
SEGMENTS := 0400-1FFF 6000-ADFF
build/%.bin: build/%.p build/p2decb
	build/p2decb $< $@ $(LOAD) $(SEGMENTS)

# Sprite test variants for visual checking: build/sp_<art><mode>.c10
#   art m = 16x16 mono (shown without artifact colours), a = 8x8 artifact
#   mode 0 = OR + clear, 1 = XOR, 2 = self-erasing, 3 = XOR delta, 4 = halo,
#   5 = 1-pixel halo at 1 pixel per frame
# build/spk_<art><mode>.c10 are the same with the CPU meter (METER=1).
# Sprite counts are chosen to fit in one 60 Hz frame.
NSPR_m0 := 16
NSPR_m1 := 12
NSPR_m2 := 24
NSPR_a0 := 18
NSPR_a1 := 14
NSPR_a2 := 26
NSPR_m3 := 11
NSPR_a3 := 11
NSPR_m4 := 18
NSPR_a4 := 18
NSPR_m5 := 20
NSPR_a5 := 20
SPVARS  := m0 m1 m2 m3 m4 m5 a0 a1 a2 a3 a4 a5

variants: $(foreach v,$(SPVARS),build/sp_$(v).bin build/spk_$(v).bin)

build/sp_%.s: bench/sprites.asm $(ENGINE) $(SPRITES) Makefile | build
	$(CC) -E -P -w -x assembler-with-cpp -Iengine -Ibuild -DDEBUG=$(DEBUG) \
	    -DART=$(if $(findstring a,$*),1,0) -DMODE=$(subst a,,$(subst m,,$*)) \
	    -DNSPR=$(NSPR_$*) $(CPPDEFS) $< -o $@

build/spk_%.s: bench/sprites.asm $(ENGINE) $(SPRITES) Makefile | build
	$(CC) -E -P -w -x assembler-with-cpp -Iengine -Ibuild -DDEBUG=$(DEBUG) -DMETER=1 \
	    -DART=$(if $(findstring a,$*),1,0) -DMODE=$(subst a,,$(subst m,,$*)) \
	    -DNSPR=$(NSPR_$*) $(CPPDEFS) $< -o $@

# Sprite manager demo builds: build/sm_m.c10 (mono), sm_a (artifact), and
# sm_mk / sm_ak with the CPU meter.
SMVARS  := m a mk ak
smdemo: $(foreach v,$(SMVARS),build/sm_$(v).bin)

build/sm_%.s: bench/smdemo.asm $(ENGINE) $(SPRITES) Makefile | build
	$(CC) -E -P -w -x assembler-with-cpp -Iengine -Ibuild -DDEBUG=$(DEBUG) \
	    -DART=$(if $(findstring a,$*),1,0) -DMETER=$(if $(findstring k,$*),1,0) \
	    -DNSPR=16 $(CPPDEFS) $< -o $@

# Run in the emulator: the build/sd folder is the MCX32-SD's SD card;
# LOADM the program, then EXEC.  Mono programs run with artifact colours
# off.  DBGLOG=FILE logs the debug port to FILE.
SD      := build/sd
run-%: build/%.bin
	mkdir -p $(SD)
	cp $< $(SD)/$(shell echo $* | tr a-z A-Z).BIN
	$(EMU) --mcx32sd --8k --sd $(SD) $(if $(filter sp_m% spk_m% sm_m% shooter%,$*),--no-artifact) \
	    $(if $(DBGLOG),--debug-port BE00$(comma)$(DBGLOG)) \
	    --type 'LOADM"$(shell echo $* | tr a-z A-Z)"\nEXEC\n'
comma := ,

# Headless: load the raw binary straight into memory and jump to it.
FRAMES ?= 10
log-%: build/%.raw
	$(HEADLESS) $(ROMS)/MC10.BIN mcx32sd:$(ROMS)/mcx32sd_flash.bin 8k frames:200 \
	    dbgport:BE00 load:$<,$(LOAD) pc:$(LOAD) frames:$(FRAMES)

# The shooter test with the CPU meter
build/shooterk.s: bench/shooter.asm $(ENGINE) $(SPRITES) Makefile | build
	$(CC) -E -P -w -x assembler-with-cpp -Iengine -Ibuild -DDEBUG=$(DEBUG) -DMETER=1 \
	    $(CPPDEFS) $< -o $@

build/wavesk.s: bench/waves.asm $(ENGINE) $(SPRITES) Makefile | build
	$(CC) -E -P -w -x assembler-with-cpp -Iengine -Ibuild -DDEBUG=$(DEBUG) -DMETER=1 \
	    $(CPPDEFS) $< -o $@

build/gamek.s: bench/game.asm $(ENGINE) $(SPRITES) Makefile | build
	$(CC) -E -P -w -x assembler-with-cpp -Iengine -Ibuild -DDEBUG=$(DEBUG) -DMETER=1 \
	    $(CPPDEFS) $< -o $@

shot-%: build/%.raw
	$(HEADLESS) $(ROMS)/MC10.BIN mcx32sd:$(ROMS)/mcx32sd_flash.bin 8k frames:200 \
	    load:$<,$(LOAD) pc:$(LOAD) frames:$(FRAMES) ppm:build/$*.ppm >/dev/null

# The sprite viewer: build/view_spr.inc and the drawing code come from
# $(VIEW), rebuilt every time (VIEW may change between runs)
VIEW    ?= sprites/game.spr
build/view_spr.inc: FORCE build/spritec | build
	build/spritec $(VIEW) > $@
build/view_list.inc: build/view_spr.inc tools/sprview.py
	python3 tools/sprview.py $(VIEW) build/view_spr.inc > $@
build/view.s: build/view_list.inc build/view_spr.inc
FORCE:

# Headless checks of the game prototype (needs the emulator's harness)
check: build/game.bin
	VMC10=$(VMC10) sh tests/game_check.sh

clean:
	rm -rf build

.PHONY: all clean variants smdemo check FORCE
.PRECIOUS: build/%.s build/%.p build/%.raw build/%_spr.inc build/%.bin
