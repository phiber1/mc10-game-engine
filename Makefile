# mc10-game-engine build
#
#   make                 build every program in bench/ (DEBUG=1 by default)
#   make DEBUG=0         release build: no debug-port writes
#   make run-tick        run a program in the emulator (vmc10 --mcx32sd --8k)
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

# Run in the emulator: CLOADM from the cassette image, then EXEC.
run-%: build/%.c10
	$(EMU) --mcx32sd --8k --debug-port BE00 --tape $< --type 'CLOADM\nEXEC\n'

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

.PHONY: all clean
.PRECIOUS: build/%.s build/%.p build/%.raw build/%_spr.inc
