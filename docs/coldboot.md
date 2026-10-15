# Cold boot

The FM-11 2D boot path uses a ROM-loaded MC6809 IPL followed by the resident
MC6809 I/O server.  The key rule is that the IPL itself never leaves cylinder 0.

## ROM-loaded IPL

`build/m6809/ipl_2d.bin` is assembled at `$0400` and is limited to 512 bytes.
The FM-11 ROM IPL loads physical sectors T0/H0/S1-S2 (2 x 256 bytes) to `$0400`
and transfers control there.

The IPL then reads only T0/H0/S3-S10, using DMA channel 0, and places the
complete resident I/O server in private physical RAM:

```text
Disk raw        Physical RAM       Contents
$0200-$09FF ->  $10000-$107FF      I/O-server slot (maximum $0800)
```

No SEEK or STEP operation is issued by the IPL.  After the load it initializes
the task-0 MMR map, maps logical `$E000-$EFFF` to physical `$10000-$10FFF`, and
jumps to the I/O server at `$E000`.

## Cylinder-1 CP/M system image

Cylinder 1 contains the one and only CP/M system image:

```text
Disk raw        Z80 physical RAM   Contents
$2000-$35FF ->  $DC00-$F1FF        CCP + BDOS ($1600)
$3600-$39FF ->  $F200-$F5FF        BIOS slot ($0400)
```

The complete `system62.bin` is therefore `$1A00` bytes, or 26 physical
256-byte sectors, beginning at T1/H0/S1.

The first operation performed by the resident I/O server during cold boot is to
establish a known Mini-FDC position with RESTORE followed by SEEK to cylinder 1.
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
$F600-$F99F   currently free
$F9A0-$FBE7   DIRBUF / CSV / ALV workspace
$FBF6-$FBFF   shared mailbox
$FC00-$FFFF   memory-mapped I/O
```

The build takes the relocated CCP+BDOS image from
`external/cpm22/ccpbdos62.bin`. The BIOS is assembled at `$F200`, and the
combined system payload is exactly `$1A00` bytes.

## 6809 private mapping

The I/O server is linked at logical `$E000` and loaded at physical `$10000`.
Before entering it, the IPL initializes hardware task 0 as an identity map and
changes only MMR14:

```text
6809 logical        Physical RAM
$E000-$EFFF   ->    $10000-$10FFF   (MMR14 = $10)
```

Logical page `$D000-$DFFF` is reserved as a temporary 6809 window onto Z80
physical bank-0 RAM. For each normal CP/M READ/WRITE, the 16-bit DMA address in
the mailbox selects the physical 4 KiB page loaded into MMR13; the record is
then copied through `$D000-$DFFF` between the Z80 buffer and the private
256-byte blocking/deblocking buffer. The previous MMR13 value is restored after
the copy, and a 128-byte record crossing a 4 KiB boundary advances the window
to the next physical page.

The CPU hand-off trampoline is copied to fixed CPU-card SRAM at `$FE00`. This
SRAM remains visible independently of the MMR. The shared Z80/6809 mailbox
occupies `$FBF6-$FBFF`.

The CP/M mutable disk workspace is packed directly below the mailbox:

```text
$F9A0-$FA1F   DIRBUF
$FA20-$FB1F   CSV0-CSV7
$FB20-$FBE7   ALV0-ALV7
$FBE8-$FBF5   reserved / free
$FBF6-$FBFF   mailbox
```

## Warm boot

Cold boot and warm boot use the same cylinder-1 system image; there is no
second CP/M system copy.

On WBOOT, the Z80 BIOS posts `MBCMD_WBOOT` and hands control to the private
6809 I/O server. The server re-establishes cylinder 1 and reloads only the first
22 physical sectors, exactly CCP+BDOS (`$1600` bytes), from T1/H0/S1 onward to
Z80 physical `$DC00-$F1FF`.

BIOS at `$F200-$F5FF` remains resident while the service call is in progress.
After the reload completes, the BIOS restores current-drive state, resets the
default DMA address to `$0080`, reinstalls the page-zero WBOOT and BDOS vectors,
and jumps to the reloaded CCP at `$DC00`.
