# Build environment

## Required tools

- `asm8080` for the CP/M 2.2 CCP/BDOS and CBIOS (same assembler as PC-9801 CP/M-80)
- `lwasm` from LWTOOLS, used in strict 6809 mode (`--6809`)
- Python 3
- GNU Make (4.3+ for the V20 grouped RAW/D88 image targets)
- NASM for 8088+Z80 / V20 builds and the common FORMAT.COM

The common CBIOS uses only Intel 8080 instructions. The active targets
are 6809+Z80, 8088+Z80 and V20 (8080 emulation without a Z80 card). The build concatenates `include/8080/mailbox.inc`,
`include/z80/fm11.inc`, `cpm22/bios/bios.asm`,
`cpm22/bios/init_z80_6809.asm`, and `cpm22/bios/cpu_z80.asm` into `build/z80/bios.asm` before assembly.
8088+Z80 uses `init_z80_8088.asm`; V20 uses `cpu_v20.asm` and CALLN.
The common BIOS has no direct hardware register access. No z80asm is required.
See [io-protocol.md](io-protocol.md) for the CPU hook contract.

## CCP + BDOS

The active build assembles the 62K core from `cpm22/cpm22_fm11.asm`,
adapted from PC-9801 CP/M-80 v1.1. No external binary is required.
The generated `build/cpm22/ccpbdos62.bin` must be exactly 5632 bytes
(DC00h-F1FFh). The BIOS is assembled at F200h. BDOS function 13 reads the
boot-drive byte at FBF4h and ignores the caller's DE parameter.

## External CP/M commands

Place optional `.COM` files in:

```text
external/commands/
```

They are installed in user area 0 of both generated disk images and are not
tracked by Git.

## Z80 memory layout

```text
0100-DBFF  CP/M TPA (55 KiB)
DC00-E3FF  CCP
E400-F1FF  BDOS
F200-F5FF  BIOS slot (maximum 1 KiB)
F600-F800  HDD ALV (513 bytes)
F801-F95F  remaining space / BIOS stack (SP=F960h)
F970-FBE7  DIRBUF / CSV / ALV workspace
FBF4       logical boot drive (0=A, 4=E, 8=I)
FBF5       boot type (0=2D, 1=2HD, 2=HDD)
FBF6-FBFF  native I/O mailbox
FC00-FFFF  memory-mapped I/O
```

The 6809 I/O server is linked at logical D000 and loaded at physical 10000
through MMR13/14. Its maximum image size is 1800h bytes; the upper 2 KiB
of the private 8 KiB mapping are reserved for the stack.

## Build

```sh
make
```

The default build creates both bootable 2D and 2HD system disks. Both
load the identical 6 KiB I/O-server slot from their respective cylinder 0.

Additional builds: `make image8088` and `make imagev20` create FDD
images. `make imagehdd`, `make image8088-hdd` and
`make imagev20-hdd` create bootable HDD images, with optional
`HDD_MODEL=m2233b`. The standard FM-11 boot ROM is used.
`make format` creates the common FORMAT.COM, and `make test-format`
checks its embedded IPLs and layout. External COM files can be placed
in `external/commands/` before creating new images.

Useful individual targets:

```sh
make check-tools
make core
make bios
make ioserver
make system
make ipl
make image
make image2d
make image2hd
make image8088
make imagev20
make imagehdd HDD_MODEL=m2233b
make image8088-hdd HDD_MODEL=m2233b
make imagev20-hdd HDD_MODEL=m2233b
make format
make test-format
make test-raw-api
make clean
```

Outputs include:

```text
build/cpm22/ccpbdos62.bin
build/z80/bios.bin
build/m6809/ioserver.bin
build/m6809/ipl_2d.bin
build/m6809/ipl_2hd.bin
build/cpm22/system62.bin
build/images/fm11-cpm80-2d.raw
build/images/fm11-cpm80-2d.d88
build/images/fm11-cpm80-2hd.raw
build/images/fm11-cpm80-2hd.d88
```

The 6809 `ipl_2d.bin` is the 512-byte-maximum ROM-loaded IPL at `$0400`.
The 8088 and V20 IPLs are entered at `07C0:0000`.
There is no second-stage loader in the active boot path. See
`docs/coldboot.md` and `docs/disk-image.md` for the exact sector layout.
