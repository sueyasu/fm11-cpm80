# Cold boot

The FM-11 2D boot path uses a single ROM-loaded MC6809 IPL. There is no
second-stage loader.

## ROM-loaded IPL

`build/6809/ipl_2d.bin` is assembled at `$0400` and is limited to 512 bytes.
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
cylinder 0, but its two components now use different physical DMA banks:

```text
Disk raw        Physical RAM       Contents
$0200-$1BFF ->  $0C400-$0DDFF      CCP + BDOS + BIOS (`system56.bin`)
$1C00-$1FFF ->  $10E00-$111FF      resident 6809 I/O-server slot
```

`system56.bin` occupies 26 physical sectors. The resident I/O server is limited
to `$0400` bytes, so the complete disk stream remains:

```text
T0/H0/S3-S16
T0/H1/S1-S16
```

No SEEK or STEP operation is issued by the IPL.

## 6809 private mapping

The I/O server remains linked at logical `$DE00`. Before entering it, the IPL
initializes hardware task 0 as an identity map and then changes only two 4 KiB
MMR entries:

```text
6809 logical        Physical RAM
$D000-$DFFF   ->    $10000-$10FFF   (MMR13 = $10)
$E000-$EFFF   ->    $11000-$11FFF   (MMR14 = $11)
```

Therefore logical `$DE00` resolves to physical `$10E00`, exactly where the IPL
loaded the server image. The Z80 keeps its independent bank-0 RAM at
`$DE00-$EFFF`; the server no longer consumes that Z80-visible memory.

The MMR is disabled while the task-0 register set is initialized. The IPL
preserves the non-MMU control bits in `$FD93`, enables translation after the
mapping is complete, and then jumps to logical `$DE00`.

`IoServerStart` copies the CPU hand-off trampoline to fixed CPU-card SRAM at
`$FE00`. This fixed SRAM remains visible independently of the MMR. The shared
Z80/6809 mailbox occupies `$FBF6-$FBFF`, the top ten bytes of Z80-visible RAM.

After the direct load completes, the IPL also clears the CP/M disk workspace at
`$F000-$F247`, installs `JP $DA00` at Z80 reset address `$0000`, and enters the
private I/O server. The server hands control to the Z80 through the fixed-SRAM
trampoline; the Z80 starts at `$0000`, jumps to BIOS at `$DA00`, and continues
to the CCP at `$C400`.

The former position-independent stage-2 loader at `$2600` is no longer used.
The earlier `$4000` execution problem therefore does not affect this boot path.

## Warm boot

Cold boot and warm boot share the same single on-disk CP/M system image. There
is no second copy of `system56.bin` in cylinder 1.

On CP/M WBOOT the Z80 BIOS posts `MBCMD_WBOOT` and hands control to the private
6809 I/O server. The server reloads only CCP+BDOS, exactly `$1600` bytes
(22 physical sectors), from T0/H0/S3 onward.

Because logical page `$D000-$DFFF` belongs to the private I/O-server mapping
while the 6809 runs, WBOOT does not CPU-copy through that logical page. Instead,
the Mini FDC DMA engine writes the sectors directly to physical Z80 bank 0 at
`$C400-$D9FF`. BIOS at physical `$DA00-$DDFF` is not reloaded.

After the reload completes, the BIOS restores current-drive state from CP/M
page zero, resets the default DMA address to `$0080`, reinstalls the page-zero
WBOOT and BDOS vectors, and jumps to the reloaded CCP at `$C400`.
