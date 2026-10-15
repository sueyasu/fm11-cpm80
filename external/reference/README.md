# Local reference images

Place locally owned reference media here. These files are ignored by Git.

For the current build, the expected Fujitsu FM-11 CP/M-80 2D image is:

```text
external/reference/cpm2d00.img
```

Run:

```sh
make extract-core
```

This extracts image offsets `0200h-17FFh` (exactly `1600h` bytes) into:

```text
external/cpm22/ccpbdos56.bin
```

That range is the 56K CCP+BDOS payload used by the new BIOS build. The
original disk image itself is never copied into the repository.
