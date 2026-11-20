# Build environment

## Required tools

- `asm8080` for the CP/M 2.2 CCP/BDOS (same assembler as PC-9801 CP/M-80)
- `z80asm` for the Z80 BIOS
- `lwasm` from LWTOOLS, used in strict 6809 mode (`--6809`)
- Python 3
- GNU Make or a compatible make

On Ubuntu, install the Z80 assembler with:

```sh
sudo apt install z80asm
```

## CCP + BDOS

The active build assembles the 62K core from `cpm22/cpm22_fm11.asm`,
adapted from PC-9801 CP/M-80 v1.1. No external binary is required.
The generated `build/cpm22/ccpbdos62.bin` must be exactly 5632 bytes
(DC00h-F1FFh). The BIOS is assembled at F200h. BDOS function 13 reads the
boot-drive byte at FBF4h and ignores the caller's DE parameter.

The locally owned Fujitsu reference image can still be used to extract its
original 56K CCP+BDOS for comparison. `make extract-core` writes that separate
reference file to:

```text
external/cpm22/ccpbdos56.bin
```

It does not overwrite the assembled 62K core.

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
F600-F95F  free / BIOS stack (SP=F960h)
F970-FBE7  DIRBUF / CSV / ALV workspace
FBF4       logical boot drive (0 or 4)
FBF5       boot controller family (0 or 1)
FBF6-FBFF  Z80/6809 mailbox
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
make extract-core
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

`ipl_2d.bin` is the 512-byte-maximum ROM-loaded IPL assembled for `$0400`.
There is no second-stage loader in the active boot path. See
`docs/coldboot.md` and `docs/disk-image.md` for the exact sector layout.
