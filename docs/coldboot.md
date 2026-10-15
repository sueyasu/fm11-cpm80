# Cold boot

The FM-11 2D boot path uses a single ROM-loaded MC6809 IPL. There is no
second-stage loader.

## ROM-loaded IPL

`build/m6809/ipl_2d.bin` is assembled at `$0400` and is limited to 512 bytes.
The FM-11 ROM IPL loads physical sectors T0/H0/S1-S2 (2 x 256 bytes) to `$0400`
and transfers control there.

The IPL uses `$2000` as its stack, selects 2D drive 0, and DMA-loads the on-disk
system components directly to their final physical RAM locations. Mini FDC
transfers use DMA channel 0:

```text
$FD40/$FD41  DMA address H/L
$FD42/$FD43  DMA byte count H/L
$FD50        DMA mode/status
$FD94        DMA physical-address bank (PA19-16)
```

The direct-load disk stream still occupies the 30 sectors remaining on
cylinder 0, but its two components use different physical DMA banks:

```text
Disk raw        Physical RAM       Contents
$0200-$1BFF ->  $0DC00-$0F5FF      CCP + BDOS + BIOS (`system62.bin`)
$1C00-$1FFF ->  $10000-$103FF      resident 6809 I/O-server slot
```

`system62.bin` occupies 26 physical sectors. The resident I/O server is limited
to `$0400` bytes, so the complete disk stream remains:

```text
T0/H0/S3-S16
T0/H1/S1-S16
```

No SEEK or STEP operation is issued by the IPL.

## 62K CP/M layout

The Z80 system uses the conventional 62K CP/M 2.2 placement:

```text
$0100-$DBFF   TPA (55 KiB)
$DC00-$E3FF   CCP
$E400-$F1FF   BDOS
$F200-$F5FF   BIOS slot
$F600-$F99F   currently free
$F9A0-$FBE7   DIRBUF / CSV / ALV workspace
$FBF6-$FBFF   shared mailbox
$FC00-$FFFF   memory-mapped I/O
```

The build takes the relocated CCP+BDOS image from
`external/cpm22/ccpbdos62.bin`. The BIOS is assembled at `$F200` and the
combined system payload remains exactly `$1A00` bytes, so the disk sector
layout does not change.

## 6809 private mapping

The current I/O server fits in one 4 KiB page. It is linked at logical `$E000`
and loaded at physical `$10000`. Before entering it, the IPL initializes
hardware task 0 as an identity map and changes only MMR14:

```text
6809 logical        Physical RAM
$E000-$EFFF   ->    $10000-$10FFF   (MMR14 = $10)
```

Logical page `$D000-$DFFF` remains identity-mapped. This matters because the
62K TPA extends through `$DBFF`; CP/M DMA buffers in the upper TPA therefore
remain directly accessible to the 6809 I/O service.

The MMR is disabled while the task-0 register set is initialized. The IPL
preserves the non-MMU control bits in `$FD93`, enables translation after the
mapping is complete, and then jumps to logical `$E000`.

`IoServerStart` copies the CPU hand-off trampoline to fixed CPU-card SRAM at
`$FE00`. This fixed SRAM remains visible independently of the MMR. The shared
Z80/6809 mailbox occupies `$FBF6-$FBFF`, the top ten bytes of Z80-visible RAM.

The CP/M mutable disk workspace is packed directly below the mailbox:

```text
$F9A0-$FA1F   DIRBUF
$FA20-$FB1F   CSV0-CSV7
$FB20-$FBE7   ALV0-ALV7
$FBE8-$FBF5   reserved / free
$FBF6-$FBFF   mailbox
```

The IPL clears `$F9A0-$FBE7` during cold boot, installs `JP $F200` at Z80 reset
address `$0000`, and enters the private I/O server. The server hands control to
the Z80 through the fixed-SRAM trampoline; the Z80 starts at `$0000`, jumps to
BIOS at `$F200`, and continues to the CCP at `$DC00`.

## Warm boot

Cold boot and warm boot share the same single on-disk CP/M system image. There
is no second copy of `system62.bin` in cylinder 1.

On CP/M WBOOT the Z80 BIOS posts `MBCMD_WBOOT` and hands control to the private
6809 I/O server. The server reloads only CCP+BDOS, exactly `$1600` bytes
(22 physical sectors), from T0/H0/S3 onward.

Because logical page `$E000-$EFFF` belongs to the private I/O-server mapping
while the 6809 runs, WBOOT uses the Mini FDC DMA engine to write the system
sectors directly to physical Z80 bank 0 at `$DC00-$F1FF`. BIOS at physical
`$F200-$F5FF` is not reloaded.

After the reload completes, the BIOS restores current-drive state from CP/M
page zero, resets the default DMA address to `$0080`, reinstalls the page-zero
WBOOT and BDOS vectors, and jumps to the reloaded CCP at `$DC00`.
