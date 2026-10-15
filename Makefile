SHELL := /bin/sh

Z80ASM  ?= z80asm
LWASM   ?= lwasm
PYTHON  ?= python3

BUILD       := build
Z80_BUILD   := $(BUILD)/z80
M6809_BUILD := $(BUILD)/m6809
CPM_BUILD   := $(BUILD)/cpm22
IMAGE_BUILD := $(BUILD)/images

CPM22_CORE         ?= external/cpm22/ccpbdos62.bin
CPM22_FUJITSU_CORE ?= external/cpm22/ccpbdos56.bin
FUJITSU_CPM_IMAGE  ?= external/reference/cpm2d00.img
COMMANDS_DIR       ?= external/commands

D88_IMAGE_2D  := $(IMAGE_BUILD)/fm11-cpm80-2d.d88
RAW_IMAGE_2D  := $(IMAGE_BUILD)/fm11-cpm80-2d.raw
D88_IMAGE_2HD := $(IMAGE_BUILD)/fm11-cpm80-2hd.d88
RAW_IMAGE_2HD := $(IMAGE_BUILD)/fm11-cpm80-2hd.raw
COMMAND_FILES := $(wildcard $(COMMANDS_DIR)/*.COM) $(wildcard $(COMMANDS_DIR)/*.com)

.PHONY: all check-tools bios ioserver ipl system image image2d image2hd extract-core clean

all: check-tools image

check-tools:
	@command -v $(Z80ASM) >/dev/null 2>&1 || { echo "error: z80asm not found" >&2; echo "Install it with: sudo apt install z80asm" >&2; exit 1; }
	@command -v $(LWASM) >/dev/null 2>&1 || { echo "error: lwasm not found" >&2; exit 1; }
	@command -v $(PYTHON) >/dev/null 2>&1 || { echo "error: python3 not found" >&2; exit 1; }

$(Z80_BUILD) $(M6809_BUILD) $(CPM_BUILD) $(IMAGE_BUILD):
	mkdir -p $@

bios: $(Z80_BUILD)/bios.bin

$(Z80_BUILD)/bios.bin: cpm22/bios/bios.asm include/z80/fm11.inc | $(Z80_BUILD)
	$(Z80ASM) --includepath=include/z80 --list=$(Z80_BUILD)/bios.lst --label=$(Z80_BUILD)/bios.sym --output=$@ $<
	$(PYTHON) tools/check_binary.py $@ --max-size 0x400 --name "CP/M 2.2 BIOS (F200-F5FF)"

ioserver: $(M6809_BUILD)/ioserver.bin

$(M6809_BUILD)/ioserver.bin: m6809/ioserver.asm include/6809/fm11.inc | $(M6809_BUILD)
	$(LWASM) --6809 --format=raw -I include/6809 --list=$(M6809_BUILD)/ioserver.lst --symbols -o $@ $<
	$(PYTHON) tools/check_binary.py $@ --max-size 0x800 --name "6809 I/O server disk slot (logical E000-E7FF, physical 10000-107FF)"

ipl: $(M6809_BUILD)/ipl_2d.bin $(M6809_BUILD)/ipl_2hd.bin

$(M6809_BUILD)/ipl_2d.bin: m6809/ipl_2d.asm | $(M6809_BUILD)
	$(LWASM) --6809 --format=raw --list=$(M6809_BUILD)/ipl_2d.lst --symbols -o $@ $<
	$(PYTHON) tools/check_binary.py $@ --max-size 0x200 --name "FM-11 2D IPL (0400-05FF)"

$(M6809_BUILD)/ipl_2hd.bin: m6809/ipl_2hd.asm include/6809/fm11.inc | $(M6809_BUILD)
	$(LWASM) --6809 --format=raw -I include/6809 --list=$(M6809_BUILD)/ipl_2hd.lst --symbols -o $@ $<
	$(PYTHON) tools/check_binary.py $@ --max-size 0x200 --name "FM-11 2HD IPL (0400-05FF)"

extract-core: $(FUJITSU_CPM_IMAGE) tools/extract_fujitsu_core.py
	$(PYTHON) tools/extract_fujitsu_core.py $(FUJITSU_CPM_IMAGE) $(CPM22_FUJITSU_CORE)

system: $(CPM_BUILD)/system62.bin

$(CPM_BUILD)/system62.bin: $(CPM22_CORE) $(Z80_BUILD)/bios.bin tools/mksystem.py | $(CPM_BUILD)
	$(PYTHON) tools/mksystem.py --core $(CPM22_CORE) --bios $(Z80_BUILD)/bios.bin --output $@

image: $(D88_IMAGE_2D) $(D88_IMAGE_2HD)
image2d: $(D88_IMAGE_2D)
image2hd: $(D88_IMAGE_2HD)

$(D88_IMAGE_2D): $(M6809_BUILD)/ipl_2d.bin $(CPM_BUILD)/system62.bin $(M6809_BUILD)/ioserver.bin tools/mk2d_d88.py $(COMMAND_FILES) | $(IMAGE_BUILD)
	$(PYTHON) tools/mk2d_d88.py \
		--ipl $(M6809_BUILD)/ipl_2d.bin \
		--system $(CPM_BUILD)/system62.bin \
		--ioserver $(M6809_BUILD)/ioserver.bin \
		--commands $(COMMANDS_DIR) \
		--output $@ \
		--raw-output $(RAW_IMAGE_2D) \
		--label "FM11 CPM80"

$(D88_IMAGE_2HD): $(M6809_BUILD)/ipl_2hd.bin $(CPM_BUILD)/system62.bin $(M6809_BUILD)/ioserver.bin tools/mk2hd_d88.py $(COMMAND_FILES) | $(IMAGE_BUILD)
	$(PYTHON) tools/mk2hd_d88.py \
		--ipl $(M6809_BUILD)/ipl_2hd.bin \
		--system $(CPM_BUILD)/system62.bin \
		--ioserver $(M6809_BUILD)/ioserver.bin \
		--commands $(COMMANDS_DIR) \
		--output $@ \
		--raw-output $(RAW_IMAGE_2HD) \
		--label "FM11 CPM80 2HD"

$(CPM22_CORE):
	@echo "error: missing $@" >&2
	@echo "Place a 62K CP/M 2.2 CCP+BDOS binary there (exactly 0x1600 bytes)." >&2
	@exit 1

$(FUJITSU_CPM_IMAGE):
	@echo "error: missing $@" >&2
	@echo "Place the locally owned Fujitsu FM-11 CP/M 2D image there." >&2
	@exit 1

clean:
	rm -rf $(BUILD)
