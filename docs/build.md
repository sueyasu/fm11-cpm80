# Build environment

## Required tools

- `z80asm` for the Z80 BIOS
- `lwasm` from LWTOOLS, used in strict 6809 mode (`--6809`)
- Python 3
- GNU Make or a compatible make

On Ubuntu, install the Z80 assembler with:

```sh
sudo apt install z80asm
```

## External CCP + BDOS

The active build is a **62K CP/M 2.2** system. It expects:

```text
external/cpm22/ccpbdos62.bin
```

The file must be exactly `$1600` (5632) bytes and represents CCP at `$DC00`
followed by BDOS through `$F1FF`. The BIOS is assembled at `$F200`.

The locally owned Fujitsu reference image can still be used to extract its
original 56K CCP+BDOS for comparison. `make extract-core` writes that separate
reference file to:

```text
external/cpm22/ccpbdos56.bin
```

It does not overwrite the active 62K core.

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
F600-F99F  free
F9A0-FBE7  DIRBUF / CSV / ALV workspace
FBF6-FBFF  Z80/6809 mailbox
FC00-FFFF  memory-mapped I/O
```

The 6809 I/O server is not stored in Z80 RAM. It is linked at logical `$E000`,
loaded at physical `$10000`, and reached through MMR14 while the 6809 runs.

## Build

```sh
make
```

The default build creates both the bootable 2D system disk and a formatted
non-bootable 2HD data disk. The 2HD image uses the E:-H: DPB and can be read
and written through the FM-11 Standard FDC at runtime; only 2HD boot remains
unsupported.

Useful individual targets:

```sh
make check-tools
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
build/z80/bios.bin
build/m6809/ioserver.bin
build/m6809/ipl_2d.bin
build/cpm22/system62.bin
build/images/fm11-cpm80-2d.raw
build/images/fm11-cpm80-2d.d88
build/images/fm11-cpm80-2hd.raw
build/images/fm11-cpm80-2hd.d88
```

`ipl_2d.bin` is the 512-byte-maximum ROM-loaded IPL assembled for `$0400`.
There is no second-stage loader in the active boot path. See
`docs/coldboot.md` and `docs/disk-image.md` for the exact sector layout.
