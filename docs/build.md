# Build environment

## Required tools

- `lwasm` from LWTOOLS, used in strict 6809 mode (`--6809`)
- `asm8080`, the Intel 8080 assembler distributed as the `asm8080` npm package
- Python 3
- GNU Make or a compatible make

Typical installation for `asm8080`:

```sh
npm install -g asm8080
```

`lwasm` is invoked with raw output and a listing/symbol table.  The Z80 BIOS
uses Intel 8080 mnemonics because `asm8080` is intentionally an 8080, not a
Z80, assembler.

## External CCP + BDOS

The initial port is a Fujitsu-style **56K CP/M 2.2** system, not a 62K system.
Provide this local file:

```text
external/cpm22/ccpbdos56.bin
```

It must be exactly `1600h` (5632) bytes and represent:

```text
C400-CBFF  CCP
CC00-D9FF  BDOS
DA00-      BIOS built from cpm22/bios/bios.asm
```

The build rejects a binary of any other size.

A conventional 62K CP/M layout would put CCP near `DC00`, BDOS near `E400`,
and BIOS near `F200`.  On the FM-11 port that would overlap the resident 6809
I/O service at `DE00-EFFF`, so a 62K CCP/BDOS image is not currently usable.

## Memory ownership above BDOS

```text
DA00-DDFF  Z80 CP/M BIOS (maximum 1 KiB)
DE00-EFFF  resident 6809 I/O server (maximum 4608 bytes)
EC00-EC09  mailbox fields reserved inside the shared area
F000-F247  CP/M DIRBUF / CSV / ALV workspace
FC00-FFFF  Z80 I/O space
```

The BIOS points its mutable disk workspace directly at the `F000` region; it
does not emit that workspace into `bios.bin`.

## Build

```sh
make
```

Useful individual targets:

```sh
make bios
make ioserver
make loader
make system
make clean
```

Outputs are written under `build/`:

```text
build/z80/bios.bin
build/z80/bios.lst
build/z80/bios.sym
build/6809/ioserver.bin
build/6809/ioserver.lst
build/6809/loader.bin
build/cpm22/system56.bin
```

`system56.bin` covers the Z80 address range `C400-DDFF`: the supplied CCP+BDOS
followed by the new BIOS padded to `DE00`.
