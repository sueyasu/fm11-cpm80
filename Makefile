SHELL := /bin/sh

ASM8080 ?= asm8080
LWASM   ?= lwasm
PYTHON  ?= python3

BUILD       := build
Z80_BUILD   := $(BUILD)/z80
M6809_BUILD := $(BUILD)/m6809
CPM_BUILD   := $(BUILD)/cpm22
IMAGE_BUILD := $(BUILD)/images

CPM22_CORE         := $(CPM_BUILD)/ccpbdos62.bin
CPM22_FUJITSU_CORE ?= external/cpm22/ccpbdos56.bin
FUJITSU_CPM_IMAGE  ?= external/reference/cpm2d00.img
COMMANDS_DIR       ?= external/commands

D88_IMAGE_2D  := $(IMAGE_BUILD)/fm11-cpm80-2d.d88
RAW_IMAGE_2D  := $(IMAGE_BUILD)/fm11-cpm80-2d.raw
D88_IMAGE_2HD := $(IMAGE_BUILD)/fm11-cpm80-2hd.d88
RAW_IMAGE_2HD := $(IMAGE_BUILD)/fm11-cpm80-2hd.raw
COMMAND_FILES := $(wildcard $(COMMANDS_DIR)/*.COM) $(wildcard $(COMMANDS_DIR)/*.com)

.PHONY: all check-tools core bios ioserver ipl system image image2d image2hd extract-core clean

all: check-tools image

check-tools:
	@command -v $(ASM8080) >/dev/null 2>&1 || { echo "error: asm8080 not found" >&2; exit 1; }
	@command -v $(LWASM) >/dev/null 2>&1 || { echo "error: lwasm not found" >&2; exit 1; }
	@command -v $(PYTHON) >/dev/null 2>&1 || { echo "error: python3 not found" >&2; exit 1; }

$(Z80_BUILD) $(M6809_BUILD) $(CPM_BUILD) $(IMAGE_BUILD):
	mkdir -p $@

bios: $(Z80_BUILD)/bios.bin

BIOS_COMMON := include/8080/mailbox.inc cpm22/bios/bios.asm
BIOS_Z80    := include/z80/fm11.inc cpm22/bios/cpu_z80.asm
BIOS_INIT_6809 := cpm22/bios/init_z80_6809.asm
BIOS_INIT_8088 := cpm22/bios/init_z80_8088.asm

$(Z80_BUILD)/bios.bin: $(BIOS_COMMON) $(BIOS_Z80) $(BIOS_INIT_6809) Makefile | $(Z80_BUILD)
	cat include/8080/mailbox.inc include/z80/fm11.inc cpm22/bios/bios.asm $(BIOS_INIT_6809) cpm22/bios/cpu_z80.asm > $(Z80_BUILD)/bios.asm
	$(ASM8080) $(Z80_BUILD)/bios.asm -o$(basename $@)
	$(PYTHON) tools/check_binary.py $@ --max-size 0x400 --name "CP/M 2.2 BIOS (F200-F5FF)"

ioserver: $(M6809_BUILD)/ioserver.bin

$(M6809_BUILD)/ioserver.bin: m6809/ioserver.asm m6809/ansi_console.inc m6809/track_cache.inc m6809/hdd.inc m6809/raw_disk.inc include/6809/fm11.inc Makefile | $(M6809_BUILD)
	$(LWASM) --6809 --format=raw -I include/6809 -I m6809 --list=$(M6809_BUILD)/ioserver.lst --symbols -o $@ $<
	$(PYTHON) tools/check_binary.py $@ --max-size 0x1800 --name "6809 I/O server disk slot (logical D000-E7FF, physical 10000-117FF)"

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

core: $(CPM22_CORE)

$(CPM22_CORE): cpm22/cpm22_fm11.asm tools/pad_core.py Makefile | $(CPM_BUILD)
	$(ASM8080) $< -o$(CPM_BUILD)/ccpbdos62-unpadded
	$(PYTHON) tools/pad_core.py $(CPM_BUILD)/ccpbdos62-unpadded.bin $@

$(FUJITSU_CPM_IMAGE):
	@echo "error: missing $@" >&2
	@echo "Place the locally owned Fujitsu FM-11 CP/M 2D image there." >&2
	@exit 1

clean:
	rm -rf $(BUILD)

# Experimental 8088+Z80 builds; default 6809 builds are unchanged.
NASM ?= nasm
I8086_BUILD := $(BUILD)/i8086
.PHONY: image8088 image8088-2d image8088-2hd ioserver8088 ipl8088 bios8088 system8088
bios8088: $(I8086_BUILD)/bios.bin
system8088: $(I8086_BUILD)/system62.bin
image8088: image8088-2d image8088-2hd
ioserver8088: $(I8086_BUILD)/ioserver.bin
ipl8088: $(I8086_BUILD)/ipl_2d.bin $(I8086_BUILD)/ipl_2hd.bin

$(I8086_BUILD):
	mkdir -p $@

$(I8086_BUILD)/bios.bin: $(BIOS_COMMON) $(BIOS_Z80) $(BIOS_INIT_8088) Makefile | $(I8086_BUILD)
	cat include/8080/mailbox.inc include/z80/fm11.inc cpm22/bios/bios.asm $(BIOS_INIT_8088) cpm22/bios/cpu_z80.asm > $(I8086_BUILD)/bios.asm
	$(ASM8080) $(I8086_BUILD)/bios.asm -o$(basename $@)
	$(PYTHON) tools/check_binary.py $@ --max-size 0x400 --name "8088+Z80 BIOS"

$(I8086_BUILD)/system62.bin: $(CPM22_CORE) $(I8086_BUILD)/bios.bin tools/mksystem.py | $(I8086_BUILD)
	$(PYTHON) tools/mksystem.py --core $(CPM22_CORE) --bios $(I8086_BUILD)/bios.bin --output $@

$(I8086_BUILD)/ioserver.bin: i8086/ioserver.asm $(wildcard i8086/*.inc) Makefile | $(I8086_BUILD)
	$(NASM) -f bin -o $@ $<
	$(PYTHON) tools/check_binary.py $@ --max-size 0x1800 --name "8088 I/O server"

$(I8086_BUILD)/ipl_%.bin: i8086/ipl_%.asm i8086/memory.inc Makefile | $(I8086_BUILD)
	$(NASM) -f bin -o $@ $<
	$(PYTHON) tools/check_binary.py $@ --max-size 0x200 --name "8088 IPL"

image8088-2d: $(IMAGE_BUILD)/fm11-cpm80-8088-2d.d88
$(IMAGE_BUILD)/fm11-cpm80-8088-2d.d88: $(I8086_BUILD)/ipl_2d.bin $(I8086_BUILD)/system62.bin $(I8086_BUILD)/ioserver.bin tools/mk2d_d88.py $(COMMAND_FILES) | $(IMAGE_BUILD)
	$(PYTHON) tools/mk2d_d88.py --ipl $(I8086_BUILD)/ipl_2d.bin --system $(I8086_BUILD)/system62.bin --ioserver $(I8086_BUILD)/ioserver.bin --commands $(COMMANDS_DIR) --output $@ --raw-output $(IMAGE_BUILD)/fm11-cpm80-8088-2d.raw --label "FM11 CPM80 8088"

image8088-2hd: $(IMAGE_BUILD)/fm11-cpm80-8088-2hd.d88
$(IMAGE_BUILD)/fm11-cpm80-8088-2hd.d88: $(I8086_BUILD)/ipl_2hd.bin $(I8086_BUILD)/system62.bin $(I8086_BUILD)/ioserver.bin tools/mk2hd_d88.py $(COMMAND_FILES) | $(IMAGE_BUILD)
	$(PYTHON) tools/mk2hd_d88.py --ipl $(I8086_BUILD)/ipl_2hd.bin --system $(I8086_BUILD)/system62.bin --ioserver $(I8086_BUILD)/ioserver.bin --commands $(COMMANDS_DIR) --output $@ --raw-output $(IMAGE_BUILD)/fm11-cpm80-8088-2hd.raw --label "FM11 CPM80 8088"

.PHONY: test-cache-api
test-cache-api: bios bios8088
	$(PYTHON) tests/check_cache_api.py

# NEC V20 8080 emulation mode; no optional Z80 card required.
V20_BUILD := $(BUILD)/v20
BIOS_V20 := cpm22/bios/cpu_v20.asm
.PHONY: imagev20 imagev20-2d imagev20-2hd biosv20 systemv20 ioserverv20 iplv20 test-v20
biosv20: $(V20_BUILD)/bios.bin
systemv20: $(V20_BUILD)/system62.bin
ioserverv20: $(V20_BUILD)/ioserver.bin
iplv20: ipl8088
imagev20: imagev20-2d imagev20-2hd

$(V20_BUILD):
	mkdir -p $@

$(V20_BUILD)/bios.bin: $(BIOS_COMMON) $(BIOS_V20) Makefile | $(V20_BUILD)
	cat $(BIOS_COMMON) $(BIOS_V20) > $(V20_BUILD)/bios.asm
	$(ASM8080) $(V20_BUILD)/bios.asm -o$(basename $@)
	$(PYTHON) tools/check_binary.py $@ --max-size 0x400 --name "V20 8080 BIOS"

$(V20_BUILD)/system62.bin: $(CPM22_CORE) $(V20_BUILD)/bios.bin tools/mksystem.py | $(V20_BUILD)
	$(PYTHON) tools/mksystem.py --core $(CPM22_CORE) --bios $(V20_BUILD)/bios.bin --output $@

$(V20_BUILD)/ioserver.bin: i8086/ioserver.asm $(wildcard i8086/*.inc) Makefile | $(V20_BUILD)
	$(NASM) -DFM11_V20=1 -f bin -o $@ $<
	$(PYTHON) tools/check_binary.py $@ --max-size 0x1800 --name "V20 native I/O server"

V20_D88_2D := $(IMAGE_BUILD)/fm11-cpm80-v20-2d.d88
V20_RAW_2D := $(IMAGE_BUILD)/fm11-cpm80-v20-2d.raw
V20_D88_2HD := $(IMAGE_BUILD)/fm11-cpm80-v20-2hd.d88
V20_RAW_2HD := $(IMAGE_BUILD)/fm11-cpm80-v20-2hd.raw

imagev20-2d: $(V20_D88_2D) $(V20_RAW_2D)
$(V20_D88_2D) $(V20_RAW_2D) &: $(I8086_BUILD)/ipl_2d.bin $(V20_BUILD)/system62.bin $(V20_BUILD)/ioserver.bin tools/mk2d_d88.py $(COMMAND_FILES) | $(IMAGE_BUILD)
	$(PYTHON) tools/mk2d_d88.py --ipl $(I8086_BUILD)/ipl_2d.bin --system $(V20_BUILD)/system62.bin --ioserver $(V20_BUILD)/ioserver.bin --commands $(COMMANDS_DIR) --output $(V20_D88_2D) --raw-output $(V20_RAW_2D) --label "FM11 CPM80 V20"

imagev20-2hd: $(V20_D88_2HD) $(V20_RAW_2HD)
$(V20_D88_2HD) $(V20_RAW_2HD) &: $(I8086_BUILD)/ipl_2hd.bin $(V20_BUILD)/system62.bin $(V20_BUILD)/ioserver.bin tools/mk2hd_d88.py $(COMMAND_FILES) | $(IMAGE_BUILD)
	$(PYTHON) tools/mk2hd_d88.py --ipl $(I8086_BUILD)/ipl_2hd.bin --system $(V20_BUILD)/system62.bin --ioserver $(V20_BUILD)/ioserver.bin --commands $(COMMANDS_DIR) --output $(V20_D88_2HD) --raw-output $(V20_RAW_2HD) --label "FM11 CPM80 V20"

test-v20: imagev20
	$(PYTHON) tests/check_cache_api.py $(V20_BUILD)/bios.bin
	$(PYTHON) tests/check_v20.py $(V20_BUILD) $(I8086_BUILD) $(IMAGE_BUILD)

# Data-only HDD image (never overwrites an existing image).
HDD_MODEL ?= m2233b
HDD_DATA_IMAGE ?= $(IMAGE_BUILD)/fm11-cpm80-$(HDD_MODEL)-data.img
.PHONY: hdd-data test-hdd-data
hdd-data:
	$(PYTHON) tools/mk_hdd_data.py --model $(HDD_MODEL) $(HDD_DATA_IMAGE)
test-hdd-data: bios8088 biosv20 ioserver8088 ioserverv20
	$(PYTHON) tests/check_cache_api.py $(I8086_BUILD)/bios.bin $(V20_BUILD)/bios.bin
	PYTHONPATH=tools $(PYTHON) tests/check_hdd_geometry.py

# Disposable high-address HDD regression fixture; not a release command.
HDD_TEST_BUILD := $(BUILD)/hddtest
HDD_TEST_IMAGE ?= $(IMAGE_BUILD)/fm11-cpm80-m2243b-test.img
.PHONY: hdd-tail-test verify-hdd-tail
$(HDD_TEST_BUILD):
	mkdir -p $@
$(HDD_TEST_BUILD)/HDDTEST.COM: tests/hddtest.asm Makefile | $(HDD_TEST_BUILD)
	$(ASM8080) $< -o$(HDD_TEST_BUILD)/hddtest
	cp $(HDD_TEST_BUILD)/hddtest.bin $@
hdd-tail-test: $(HDD_TEST_BUILD)/HDDTEST.COM
	$(PYTHON) tools/mk_hdd_tail_test.py create $(HDD_TEST_IMAGE) $<
verify-hdd-tail: $(HDD_TEST_BUILD)/HDDTEST.COM
	$(PYTHON) tools/mk_hdd_tail_test.py verify $(HDD_TEST_IMAGE) $<

# Whole-HDD boot: standard FM-11 ROM, common IPL, separate native/system slots.
HDD_IPL := $(I8086_BUILD)/ipl_hdd.bin
HDD_8088_IMAGE ?= $(IMAGE_BUILD)/fm11-cpm80-8088-hdd.img
HDD_V20_IMAGE ?= $(IMAGE_BUILD)/fm11-cpm80-v20-hdd.img
.PHONY: image8088-hdd imagev20-hdd hdd-ipl test-hdd-boot
hdd-ipl: $(HDD_IPL)
$(HDD_IPL): i8086/ipl_hdd.asm i8086/hdd_boot_io.inc i8086/memory.inc Makefile | $(I8086_BUILD)
	$(NASM) -f bin -o $@ $<
	$(PYTHON) tools/check_binary.py $@ --max-size 0x200 --name "HDD IPL"
image8088-hdd: hdd-ipl $(I8086_BUILD)/system62.bin $(I8086_BUILD)/ioserver.bin
	$(PYTHON) tools/mk_hdd_boot.py --model $(HDD_MODEL) --ipl $(HDD_IPL) --server $(I8086_BUILD)/ioserver.bin --system $(I8086_BUILD)/system62.bin --commands $(COMMANDS_DIR) $(HDD_8088_IMAGE)
imagev20-hdd: hdd-ipl $(V20_BUILD)/system62.bin $(V20_BUILD)/ioserver.bin
	$(PYTHON) tools/mk_hdd_boot.py --model $(HDD_MODEL) --ipl $(HDD_IPL) --server $(V20_BUILD)/ioserver.bin --system $(V20_BUILD)/system62.bin --commands $(COMMANDS_DIR) $(HDD_V20_IMAGE)
test-hdd-boot: hdd-ipl $(I8086_BUILD)/system62.bin $(I8086_BUILD)/ioserver.bin $(V20_BUILD)/system62.bin $(V20_BUILD)/ioserver.bin
	PYTHONPATH=tools $(PYTHON) tests/check_hdd_boot.py $(I8086_BUILD) $(V20_BUILD)

# Standard 6809 ROM HDD boot; image layout matches native 8088 targets.
HDD_6809_IMAGE ?= $(IMAGE_BUILD)/fm11-cpm80-6809-hdd.img
.PHONY: imagehdd test-hdd-6809
$(M6809_BUILD)/ipl_hdd.bin: m6809/ipl_hdd.asm include/6809/fm11.inc Makefile | $(M6809_BUILD)
	$(LWASM) --6809 --format=raw -I include/6809 --list=$(M6809_BUILD)/ipl_hdd.lst --symbols -o $@ $<
	$(PYTHON) tools/check_binary.py $@ --max-size 0x200 --name "6809 HDD IPL"
imagehdd: $(M6809_BUILD)/ipl_hdd.bin $(CPM_BUILD)/system62.bin $(M6809_BUILD)/ioserver.bin
	$(PYTHON) tools/mk_hdd_boot.py --cpu 6809 --model $(HDD_MODEL) --ipl $(M6809_BUILD)/ipl_hdd.bin --server $(M6809_BUILD)/ioserver.bin --system $(CPM_BUILD)/system62.bin --commands $(COMMANDS_DIR) $(HDD_6809_IMAGE)
test-hdd-6809: $(M6809_BUILD)/ipl_hdd.bin $(CPM_BUILD)/system62.bin $(M6809_BUILD)/ioserver.bin
	PYTHONPATH=tools $(PYTHON) tests/check_hdd_6809.py $(M6809_BUILD) $(CPM_BUILD)

.PHONY: test-raw-api
test-raw-api: bios bios8088 biosv20 ioserver ioserver8088 ioserverv20
	$(PYTHON) tests/check_raw_api.py $(Z80_BUILD)/bios.bin $(I8086_BUILD)/bios.bin $(V20_BUILD)/bios.bin

# Runtime physical API diagnostic. Never installed automatically.
RAW_TEST_BUILD := $(BUILD)/rawtest
.PHONY: rawtest
$(RAW_TEST_BUILD):
	mkdir -p $@
$(RAW_TEST_BUILD)/RAWTEST.COM: tests/rawtest.asm Makefile | $(RAW_TEST_BUILD)
	$(ASM8080) $< -o$(RAW_TEST_BUILD)/rawtest
	cp $(RAW_TEST_BUILD)/rawtest.bin $@
rawtest: $(RAW_TEST_BUILD)/RAWTEST.COM
