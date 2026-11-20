# FM-11 CP/M-80 whole-HDD boot

One physical MDC HDD maps to I:, with the same filesystem as the CP/M-86
whole-HDD data area. All nine models in [hdd-data.md](hdd-data.md) are
supported by design for all three CPU backends.

| Physical LBA (256 bytes) | Contents |
|---|---|
| 0–1 | 512-byte HDD IPL (CPU-specific) |
| 2–25 | 6 KiB native server, specific to CPU backend |
| 26–51 | 0x1a00-byte CCP/BDOS/CBIOS, specific to backend |
| 52 to end of cylinder 0 | Reserved (E5h) |
| Cylinder 1 onward | CP/M filesystem, identical to data-only images |

The smallest supported cylinder has 64 sectors, so all system sectors
fit in cylinder 0. The original FM-11 8088 boot ROM reads LBA 0–1 into
07C0:0000, then the IPL relocates to 0100:0000 and loads the native
server into 0400:0000, passing AL=8. The server SENSEs the HDD and
loads 26 sectors starting at LBA 26 into 1000:DC00. WBOOT flushes
the cache, refreshes geometry, and reloads only LBA 26–47 (22 sectors,
CCP+BDOS); CBIOS and ALV are not overwritten. The existing Z80 FD05
or V20 BRKEM/CALLN backend is unchanged. BOOTDRV=8, BOOTTYPE=2.
FDD boot remains supported.

No replacement reset ROM is required. The disassembled FM-11 8088 ROM
v3.3 (SM07418-M050/02, 01/07/84) has an HDD boot path at FF00:02CF:
it reads records 0 and 1 of cylinder 0/head 0 (256 bytes each) via
the ROM disk-read entry FF00:001B and jumps to 07C0:0000 at FF00:0393.
The IPL initializes its own stack and segments, conditionally initializes
USART0 as the FDD IPL does, and explicitly selects binary LBA / DMA2.
The original ROM performs device selection via FD23 DIP switches.
This ROM/IPL handoff and boot on 8088+Z80 and V20 have been confirmed
in the FM-11 emulator. No original ROM bytes are included in this repository.

## Build

```sh
make imagev20-hdd HDD_MODEL=m2233b
# or
make image8088-hdd HDD_MODEL=m2233b
make test-hdd-boot
```

Outputs:
- build/i8086/ipl_hdd.bin (shared)
- build/images/fm11-cpm80-v20-hdd.img or fm11-cpm80-8088-hdd.img

Optional COM files from external/commands are imported in user 0.
Image creation refuses to overwrite an existing file. Use
HDD_V20_IMAGE or HDD_8088_IMAGE to choose a distinct output path
for another model or test. The model must match the image size.
The test target checks both binary layouts and all nine model
images with a multi-extent file, not actual boot execution.

Use your existing working CPU and display configuration. Set HDD=true
under [DIPSW], keep main_cpu=8088, and select the proper backend
(V20/no Z80, or 8088/Z80). Example:

```ini
[hdd]
image = /absolute/path/to/fm11-cpm80-v20-hdd.img
```

```sh
fm11-sdl --config /path/to/fm11emu.conf
```

Keep the original boot8088.bin in [main_8088] rom; do not override it
with a custom ROM. The initial prompt must be I>. Boot first without mounted floppies
to demonstrate that both cold boot and WBOOT (Ctrl-C) work from HDD.
Run DIR and a supplied COM program such as STAT, copy a file on I:,
then Ctrl-C and confirm it is retained. Test FDD access and WBOOT
while logged into a mounted FDD separately. For persistence, exit
after WBOOT and use cpmls -f fm11-cpm80-m2233b on the HDD image.
SUBMIT uses the actual boot drive I: as before.

Use separate images for the two CPU backends; their resident and
CBIOS code are different. Do not mount the same image concurrently.
Do not overwrite a data HDD with the image builder; the common
FORMAT.COM now supports `FORMAT HDD /S` on a disposable target. The same original ROM is used for FDD and HDD
boot, according to the DIP switches.

## 6809 + Z80

The standard 6809 ROM loads LBA 0–1 at $0400 (same contract as
FM-11 NitrOS-9 HDD IPL). The disk IPL uses 6844 DMA2 to load LBA 2–25
into physical $10000, configures MMR13/14 and jumps to $D000 with A=2.
The resident server uses native DMA2 and the existing two cache windows.
HDD side-track is encoded as high byte in PhysSide, low byte in PhysTrack;
the two-byte cache tag distinguishes all 8217 physical side-tracks.
HDD read/write uses 24-bit LBA; cold/warm system reload uses the same
LBA 26–51 / 26–47 as the 8088 variants.

```sh
make imagehdd HDD_MODEL=m2233b
make test-hdd-6809
```

Output: build/images/fm11-cpm80-6809-hdd.img. Use the original
boot6809.bin, [DIPSW] main_cpu=6809 and HDD=true, [optional_cpu]
type=z80; retain normal display/ROM configuration. Then boot with
fm11-sdl --config as usual. Initial prompt I:. Verify DIR, PIP,
Ctrl-C, and persistence. Also run the M2243B last-block test
described in hdd-data.md because this is a native transport regression check.
