# mc10-game-engine build
#
#   make                 build every program in bench/ (DEBUG=1 by default)
#   make DEBUG=0         release build: no debug-port writes
#   make run-tick        run a program in the emulator (vmc10 --mcx32sd --8k)
#   make variants        sprite test builds: run-sp_m0 ... run-sp_a2 (see below)
#   make log-tick        run it headless and print the debug-port log
#
# Each bench/NAME.asm builds build/NAME.c10 (CLOADM) and build/NAME.bin
# (MCX32-SD LOADM).  Programs load and start at $6000.

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

all: $(foreach p,$(PROGS),build/$(p).c10 build/$(p).bin)

build/mkc10: tools/mkc10.c | build
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

build/%.bin: build/%.raw build/mkc10
	build/mkc10 $< $@ $* $(LOAD) $(LOAD)

# Sprite test variants for visual checking: build/sp_<art><mode>.c10
#   art m = 16x16 mono (shown without artifact colours), a = 8x8 artifact
#   mode 0 = OR + clear, 1 = XOR, 2 = self-erasing, 3 = XOR delta
# Sprite counts are chosen to fit in one 60 Hz frame.
NSPR_m0 := 16
NSPR_m1 := 12
NSPR_m2 := 24
NSPR_a0 := 18
NSPR_a1 := 14
NSPR_a2 := 26
NSPR_m3 := 11
NSPR_a3 := 11
SPVARS  := m0 m1 m2 m3 a0 a1 a2 a3

variants: $(foreach v,$(SPVARS),build/sp_$(v).c10)

build/sp_%.s: bench/sprites.asm $(ENGINE) $(SPRITES) Makefile | build
	$(CC) -E -P -w -x assembler-with-cpp -Iengine -Ibuild -DDEBUG=$(DEBUG) \
	    -DART=$(if $(findstring a,$*),1,0) -DMODE=$(subst a,,$(subst m,,$*)) \
	    -DNSPR=$(NSPR_$*) $(CPPDEFS) $< -o $@

# Run in the emulator: CLOADM from the cassette image, then EXEC.
# Mono programs run with artifact colours off.  DBGLOG=FILE logs the
# debug port to FILE.
run-%: build/%.c10
	$(EMU) --mcx32sd --8k $(if $(findstring _m,$*),--no-artifact) \
	    $(if $(DBGLOG),--debug-port BE00$(comma)$(DBGLOG)) \
	    --tape $< --type 'CLOADM\nEXEC\n'
comma := ,

# Headless: load the raw binary straight into memory and jump to it.
FRAMES ?= 10
log-%: build/%.raw
	$(HEADLESS) $(ROMS)/MC10.BIN mcx32sd:$(ROMS)/mcx32sd_flash.bin 8k frames:200 \
	    dbgport:BE00 load:$<,$(LOAD) pc:$(LOAD) frames:$(FRAMES)

shot-%: build/%.raw
	$(HEADLESS) $(ROMS)/MC10.BIN mcx32sd:$(ROMS)/mcx32sd_flash.bin 8k frames:200 \
	    load:$<,$(LOAD) pc:$(LOAD) frames:$(FRAMES) ppm:build/$*.ppm >/dev/null

clean:
	rm -rf build

.PHONY: all clean variants
.PRECIOUS: build/%.s build/%.p build/%.raw build/%_spr.inc
