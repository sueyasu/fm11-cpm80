# Cold boot

The FM-11 2D boot path uses a ROM-loaded MC6809 IPL followed by the resident
MC6809 I/O server.  The key rule is that the IPL itself never leaves cylinder 0.

## ROM-loaded IPL

`build/m6809/ipl_2d.bin` is assembled at `$0400` and is limited to 512 bytes.
The FM-11 ROM IPL loads physical sectors T0/H0/S1-S2 (2 x 256 bytes) to `$0400`
and transfers control there.

The 2D IPL reads 24 sectors: T0/H0/S3-S16 and T0/H1/S1-S10.
The 2HD ROM loads T0/H0/S1-S4 (128 bytes each); its IPL then reads
T0/H0/S5-S26 (22 x 128) and T0/H1/S1-S13 (13 x 256).

Both loaders transfer a 6 KiB resident slot:

```text
Disk raw        Physical RAM       Contents
$0200-$19FF ->  $10000-$117FF      I/O server and workspace
```

The IPL never leaves cylinder 0. It maps logical D000-EFFF onto physical
10000-11FFF and jumps to D000.

## Cylinder-1 CP/M system image

Cylinder 1 contains the one and only CP/M system image. The following raw offsets are for 2D; on 2HD the system starts at raw 2700h.

```text
Disk raw        Z80 physical RAM   Contents
$2000-$35FF ->  $DC00-$F1FF        CCP + BDOS ($1600)
$3600-$39FF ->  $F200-$F5FF        BIOS slot ($0400)
```

The complete `system62.bin` is therefore `$1A00` bytes, or 26 physical
256-byte sectors, beginning at T1/H0/S1.

The first operation performed by the resident I/O server during cold boot is to
establish a known position on the boot controller with RESTORE followed by SEEK to cylinder 1.
Only after the IPL boot phase has ended does the system perform this first
cylinder change.  The I/O server then DMA-loads all 26 sectors directly to Z80
physical bank 0 at `$DC00-$F5FF`.

After the CP/M system is resident, the I/O server clears the mutable disk
workspace, installs `JP $F200` at Z80 reset address `$0000`, and releases the
Z80 through the fixed-SRAM trampoline.

## 62K CP/M layout

The Z80 system uses the conventional 62K CP/M 2.2 placement:

```text
$0100-$DBFF   TPA (54.75 KiB)
$DC00-$E3FF   CCP
$E400-$F1FF   BDOS
$F200-$F5FF   BIOS slot
$F600-$F95F   free / BIOS stack (SP=F960)
$F970-$FBE7   DIRBUF / CSV / ALV workspace
$FBF4         logical boot drive (0 or 4)
$FBF5         boot controller family
$FBF6-$FBFF   shared mailbox
$FC00-$FFFF   memory-mapped I/O
```

The build assembles the CCP+BDOS image from `cpm22/cpm22_fm11.asm`. The BIOS is assembled at `$F200`, and the
combined system payload is exactly `$1A00` bytes.

## 6809 private mapping

The I/O server is linked at logical D000. The IPL maps MMR13=10h and
MMR14=11h. D000-E7FF is the resident image and workspace; E800-EFFF
(physical 11800-11FFF) is the dedicated stack, starting at F000.
Two 8 KiB write-back cache windows occupy physical 12000-13FFF and
14000-15FFF. Each holds one side-track, with 32-bit valid and dirty maps.

Logical page C (C000-CFFF) is the temporary access window onto Z80 RAM
or cache RAM. MMR12 is saved and restored around copies; 128-byte records
crossing a 4 KiB boundary are copied through two mappings.

The CPU hand-off trampoline is copied to fixed CPU-card SRAM at `$FE00`. This
SRAM remains visible independently of the MMR. The shared Z80/6809 mailbox
occupies `$FBF6-$FBFF`.

The CP/M mutable disk workspace is packed directly below the mailbox:

```text
$F970-$F9EF   DIRBUF
$F9F0-$FAEF   CSV0-CSV7
$FAF0-$FBE7   ALV0-ALV7
$FBE8-$FBF3   reserved / free
$FBF4         boot drive (0=A, 4=E)
$FBF5         boot controller family
$FBF6-$FBFF   mailbox
```

## Warm boot

Cold boot and warm boot use the same cylinder-1 system image; there is no
second CP/M system copy.

On WBOOT, the Z80 BIOS posts `MBCMD_WBOOT` and hands control to the private
6809 I/O server. The server flushes both windows before invalidating cache
and saved FDC positions, then re-establishes cylinder 1 and reloads only the first
22 physical sectors, exactly CCP+BDOS (`$1600` bytes), from T1/H0/S1 onward to
Z80 physical `$DC00-$F1FF`.

BIOS at `$F200-$F5FF` remains resident while the service call is in progress.
After the reload completes, the BIOS restores current-drive state, resets the
default DMA address to `$0080`, reinstalls the page-zero WBOOT and BDOS vectors,
and jumps to the reloaded CCP at `$DC00`.

The reload always targets the physical boot drive. The BIOS probes the saved
current drive if different from the boot drive, and falls back to the boot
drive on failure. CCP resets BDOS on the boot drive (including batch-file
detection) before selecting the saved current drive and user.
