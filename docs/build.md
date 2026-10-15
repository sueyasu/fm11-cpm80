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

The initial port is a Fujitsu-style **56K CP/M 2.2** system. The build expects:

```text
external/cpm22/ccpbdos56.bin
```

It must be exactly `1600h` (5632) bytes and represents CCP at `$C400` followed
by BDOS through `$D9FF`. The new BIOS is assembled at `$DA00`.

To extract the 56K CCP+BDOS from the locally owned Fujitsu 2D image, place it at:

```text
external/reference/cpm2d00.img
```

then run:

```sh
make extract-core
```

## External CP/M commands

Place optional `.COM` files in:

```text
external/commands/
```

They are installed in user area 0 of the generated disk and are not tracked by
Git.

## Memory ownership above BDOS

```text
DA00-DDFF  Z80 CP/M BIOS (maximum 1 KiB)
DE00-EBFF  resident 6809 I/O server (maximum 0E00h = 3584 bytes)
EC00-EC09  Z80/6809 mailbox
EC0A-EFFF  reserved for future shared service data
F000-F247  CP/M DIRBUF / CSV / ALV workspace
F248-FBFF  reserved/free shared RAM
FC00-FFFF  Z80 I/O space
```

## Build

```sh
make
```

Useful individual targets:

```sh
make check-tools
make bios
make ioserver
make system
make loader
make ipl
make image
make extract-core
make clean
```

Outputs include:

```text
build/z80/bios.bin
build/6809/ioserver.bin
build/6809/loader.bin
build/6809/ipl_2d.bin
build/cpm22/system56.bin
build/images/fm11-cpm80-2d.raw
build/images/fm11-cpm80-2d.d88
```

`ipl_2d.bin` is the 512-byte-maximum ROM-loaded stage 1 assembled for `$0400`.
`loader.bin` is the position-independent stage 2. The generated D88 contains
both stages and is intended to boot directly on the FM-11 2D boot path. See
`docs/coldboot.md` and `docs/disk-image.md` for the exact sector layout.
