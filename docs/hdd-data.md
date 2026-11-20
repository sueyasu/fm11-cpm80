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
execution. Assembler size checks remain in the build. HDD boot is described in [boot-hdd.md](boot-hdd.md).
FORMAT and 6809 MDC transport remain outside the current implementation.

## M2243B last-block regression

```sh
make hdd-tail-test
```

This creates a **disposable, non-bootable** image
`build/images/fm11-cpm80-m2243b-test.img` containing HDDTEST.COM,
TAIL.DAT (16 KiB at block 4102, the last allocation block), and
GUARD.DAT (block 6, the address where old 16-bit record arithmetic
would wrap). No large filler files are needed. Existing images are
never overwritten. The final record is at the very end of the disk.

Attach this image as the HDD, boot from the usual FDD, and run:

```text
A>I:
I>HDDTEST
M2243B last-block test
PASS: DSM=1006h
PASS: TAIL.DAT opened
PASS: all 128 records read
PASS: random write/readback - verify image on host
```

HDDTEST uses only standard BDOS calls and 8080 instructions.
It checks the DSM, reads every record of TAIL.DAT sequentially,
overwrites record 127 with A5h bytes via random write, closes and
reopens the file, and reads the record back. It then performs WBOOT
to flush the cache. Run it only once per fresh fixture. After the
prompt returns, shut down the emulator and run:

```sh
make verify-hdd-tail
```

The host compares the complete RAW image against the expected result,
including the guard block and directory. Only the final 128 bytes
should differ from the original image. A failure reports the first
unexpected byte. Repeat using newly created fixtures for V20 and
8088+Z80; use HDD_TEST_IMAGE to select different filenames.
This tests sequential read and random overwrite at the disk boundary,
not allocation of new high blocks or BDOS function 40.

## Application compatibility

The 24-bit change is internal BDOS disk-relative addressing; the
standard FCB, BDOS API and per-file size limit are unchanged.
Drive capacities above 8 MiB are an extension to CP/M 2.2.
Programs that calculate disk sizes or physical addresses themselves
(e.g. STAT, sector editors, disk copy/repair tools) may overflow
or otherwise mishandle these larger drives. Do not use unverified
disk utilities for destructive operations.

The STAT.COM examined in this project uses a 16-bit unsigned KiB
counter for free space. It can display at most 65535 KiB
(65520 KiB for 16 KiB blocks). An empty M2243B has 65632 KiB free
and may display 96k instead. Allocating at least 112 KiB of file
space brings the displayed free space into range. STAT DSK: may
also misreport 128-byte record capacity above 8 MiB. This is a
utility limitation, not evidence of a BDOS I/O failure. Other
STAT versions may differ. The bundled test checks actual data,
not STAT output.

HDDTEST initializes its FCB explicitly and reports the failing stage,
including hexadecimal DSM, BDOS status, or record/byte offset and
expected/actual data. Recreate the fixture after rebuilding HDDTEST.
