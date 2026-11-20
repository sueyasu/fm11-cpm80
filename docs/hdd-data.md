# MDC HDD data drive (8088+Z80 and V20)

Boot from 2D or 2HD as usual. I: maps the entire single MDC HDD,
with the same filesystem as fm11-cpm86: 256-byte physical sectors,
32 sectors/side-track, 64 logical records/track, 16 KiB blocks,
EXM=7, DRM=511, AL0=80h, CKS=0. SENSE resolves the supported model,
DSM=floor((cylinders-1)*heads/2)-1 and OFF=heads. The first cylinder is
reserved. No partitions. All nine CP/M-86 models are supported by design.

The common BIOS queries native mailbox command 06h; successful replies
contain DSM in TRACK and OFF in SECTOR (big endian). The 6809 server
rejects this command, so I: remains unavailable there. Native geometry
is cached until CACHE_RESET/WBOOT; the HDD must not be exchanged while
mounted. I/O uses binary LBA and DMA channel 2, with the existing
256-byte bounce buffer and both 8 KiB cache windows. Dirty write-back
and directory ordering remain unchanged.

The original BDOS 16-bit relative record arithmetic wraps after 8 MiB.
The common BDOS now retains a high byte and directly divides the 24-bit
record number by SPT to compute track and sector. All supported DPBs
have SPT <=127. Existing floppy layout, CCP/BDOS/BIOS addresses, 62K
system, cache vectors F233/F236, and boot SP=F960 are unchanged.
The HDD ALV occupies F600-F800 (513 bytes), leaving 351 bytes below
the boot stack top; normal BDOS calls still use the separate BDOS stack.

## Build and test

```sh
make image8088 imagev20
make test-hdd-data
make hdd-data HDD_MODEL=m2233b
```

The last command creates a new, empty, **non-bootable** image
build/images/fm11-cpm80-m2233b-data.img. It refuses to overwrite an
existing image. Alternatively use a disposable copy of an existing
CP/M-86 HDD image, not the original. Do not mount the same disk twice.

In the emulator config, leave FDD boot enabled and HDD boot disabled,
and add:

```ini
[hdd]
image = /absolute/path/to/fm11-cpm80-m2233b-data.img
```

Test DIR I:, STAT I:, PIP I:TEST.COM=A:PIP.COM, directory listing,
copy back, erase, Ctrl-C on I: and reboot from FDD. Verify persisted
data with cpmtools (after CACHE_SYNC or WBOOT and emulator shutdown):

```sh
cpmls -f fm11-cpm80-m2233b build/images/fm11-cpm80-m2233b-data.img
```

Use the matching model name in diskdefs. For a high-address test,
prepopulate a disposable image so that a file uses a block >=512
(8 MiB relative), and check its bytes after reading and writing;
also test random-write function 40 and the largest model. The
geometry test checks the arithmetic model, not the assembled BDOS
execution. Assembler size checks remain in the build. HDD boot,
FORMAT, and 6809 MDC transport are outside this change.
