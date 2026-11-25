# FORMAT.COM

Common 8080-compatible formatter for 6809+Z80, 8088+Z80 and V20.
Requires the FM-11 RAW_DISK_API introduced in commit 4.

```text
FORMAT B:
FORMAT F: /L
FORMAT B: /S
FORMAT F: /S
FORMAT I:
FORMAT HDD /S
```

A:–D: are 2D, E:–H: are 2HD, I: or HDD denotes the whole MDC drive.
Default floppy format writes all physical side-tracks with E5h,
leaving a usable empty CP/M directory. As with CP/M-86, a successful
WRITE TRACK completes each side-track without reading back every sector.
 /L performs only this physical format, without installing a system.
The resulting E5h directory is also empty (same physical fill).
 /S additionally installs a bootable system with the appropriate IPL;
its system writes are read back and checked.
HDD default initializes only cylinder 0 and the 16 KiB directory;
other sectors are untouched. /S installs the system after initialization.
HDD /L is rejected. This is not a secure erase or physical HDD format.

The command refuses the boot and current drives, and requests Y/N
confirmation before destructive I/O. A failure stops immediately;
the target may be partially formatted. WBOOT resets BDOS state on exit.

## Bootable disks

 /S reads the resident native server and CCP/BDOS/CBIOS from the actual
boot disk, before changing the target. Only the six IPL templates are
embedded in FORMAT.COM. The running CPU type selects the correct
6809 or 8088 IPL family; the target medium selects 2D, 2HD or HDD.
V20 shares 8088 IPLs but copies its own native server and CBIOS from
the source. The source must be the matching, readable FM-11 system
disk; this is not a cross-CPU installation tool. No COM files are copied.

| Medium | IPL | Native server | CCP/BDOS/CBIOS |
|---|---:|---:|---:|
| 2D | 0 | 512 | 8192 |
| 2HD unpadded RAW | 0 | 512 | 9984 |
| HDD | 0 | 512 | 6656 |

Offsets in bytes. Sizes 512, 6144 and 6656 respectively.
System-installation physical sector writes are read back and compared;
the full-disk WRITE TRACK pass is not read back. The special 2HD
first side-track uses 26 x 128-byte sectors, all other sectors are
256 bytes. FDD stream matches the tested RAWTEST format.

In 6809+Z80, 8088+Z80 and V20 builds, RAW physical I/O flushes and
invalidates the track cache **without forgetting the FDC's current
physical head positions**. Explicit CACHE_RESET/cold initialization
still forgets the positions. On 6809, a failed raw FDC command also
invalidates positions; successful WRITE TRACK and sector I/O preserve
them. This avoids unnecessary RESTORE-to-track-zero and SEEK operations
when the emulator uses `[floppy] timing=timed`. WRITE TRACK still takes
simulated disk-rotation time, but the formatter no longer performs the
extra full-disk readback pass. The message
`Formatting all floppy tracks...` remains visible until that pass completes.

## Build and test

```sh
make test-format
mkdir -p external/commands
cp build/format/FORMAT.COM external/commands/
make image image8088 imagev20
```

The explicit format target requires lwasm and NASM to build all six
IPL templates. The default image build tool requirements are unchanged.
Copying FORMAT.COM into external/commands includes it in subsequently
generated images. Existing HDD images are never overwritten by make.

Use disposable scratch disks in B:, F: and I:, boot A: and remain on A:.
Test default FDD format, /L, and HDD default; DIR on targets must show
no files. Copy a command with PIP, read it back and warm boot.
Then run /S on each scratch target, power off after return to prompt,
mount it as the first drive of its family (B: -> A:, F: -> E:),
enable that boot device and boot using the original ROM.
HDD remains I:. Expect the normal CP/M banner and the correct prompt.
Repeat with 6809 and V20, and test at least one 8088+Z80 bootable disk.
Also test /S from an HDD boot disk to a floppy. The structural test
does not execute FORMAT or prove controller transfers.
