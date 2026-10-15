SHELL := /bin/sh

ASM8080 ?= asm8080
LWASM   ?= lwasm
PYTHON  ?= python3

BUILD       := build
Z80_BUILD   := $(BUILD)/z80
M6809_BUILD := $(BUILD)/6809
CPM_BUILD   := $(BUILD)/cpm22

CPM22_CORE ?= external/cpm22/ccpbdos56.bin

.PHONY: all check-tools bios ioserver loader system clean

all: check-tools system ioserver loader

check-tools:
	@command -v $(ASM8080) >/dev/null 2>&1 || { echo "error: asm8080 not found" >&2; exit 1; }
	@command -v $(LWASM) >/dev/null 2>&1 || { echo "error: lwasm not found" >&2; exit 1; }
	@command -v $(PYTHON) >/dev/null 2>&1 || { echo "error: python3 not found" >&2; exit 1; }

$(Z80_BUILD) $(M6809_BUILD) $(CPM_BUILD):
	mkdir -p $@

bios: $(Z80_BUILD)/bios.bin

$(Z80_BUILD)/bios.bin: cpm22/bios/bios.asm include/z80/fm11.inc | $(Z80_BUILD)
	$(ASM8080) cpm22/bios/bios.asm --split -l -o $(Z80_BUILD)
	$(PYTHON) tools/check_binary.py $@ --max-size 0x400 --name "CP/M 2.2 BIOS (DA00-DDFF)"

ioserver: $(M6809_BUILD)/ioserver.bin

$(M6809_BUILD)/ioserver.bin: m6809/ioserver.asm include/6809/fm11.inc | $(M6809_BUILD)
	$(LWASM) --6809 --format=raw -I include/6809 --list=$(M6809_BUILD)/ioserver.lst --symbols -o $@ $<
	$(PYTHON) tools/check_binary.py $@ --max-size 0x1200 --name "6809 I/O server (DE00-EFFF)"

loader: $(M6809_BUILD)/loader.bin

$(M6809_BUILD)/loader.bin: m6809/loader.asm include/6809/fm11.inc | $(M6809_BUILD)
	$(LWASM) --6809 --format=raw -I include/6809 --list=$(M6809_BUILD)/loader.lst --symbols -o $@ $<

system: $(CPM_BUILD)/system56.bin

$(CPM_BUILD)/system56.bin: $(CPM22_CORE) $(Z80_BUILD)/bios.bin tools/mksystem.py | $(CPM_BUILD)
	$(PYTHON) tools/mksystem.py --core $(CPM22_CORE) --bios $(Z80_BUILD)/bios.bin --output $@

$(CPM22_CORE):
	@echo "error: missing $@" >&2
	@echo "Place a 56K CP/M 2.2 CCP+BDOS binary there (exactly 0x1600 bytes)." >&2
	@exit 1

clean:
	rm -rf $(BUILD)
