# External CP/M 2.2 core

Place the locally supplied 56K CP/M 2.2 CCP+BDOS binary here as:

```
external/cpm22/ccpbdos56.bin
```

It must contain exactly the address range `C400h-D9FFh`, i.e. `1600h`
(5632) bytes:

- CCP at `C400h`
- BDOS at `CC00h`
- BIOS begins at `DA00h` and is built by this repository

The binary is intentionally not tracked by Git because redistribution terms
for historical CP/M binaries may vary.

## Why not the common 62K image?

A conventional 62K CP/M 2.2 layout places CCP around `DC00h`, BDOS around
`E400h`, and BIOS around `F200h`.  That overlaps the FM-11 resident 6809 I/O
service beginning at physical/Z80 address `DE00h`.  The initial FM-11 port
therefore uses the Fujitsu-style 56K layout.

A 62K core may be kept elsewhere as reference material, but it is not a valid
input to the current build and should not be renamed to `ccpbdos56.bin`.
