# Cold boot

The FM-11 2D boot path uses a single ROM-loaded MC6809 IPL. There is no
second-stage loader.

## ROM-loaded IPL

`build/6809/ipl_2d.bin` is assembled at `$0400` and is limited to 512 bytes.
The FM-11 ROM IPL loads physical sectors T0/H0/S1-S2 (2 x 256 bytes) to `$0400`
and transfers control there.

The IPL uses `$2000` as its stack, selects 2D drive 0, and DMA-loads the on-disk
system image directly to its final RAM addresses. Mini FDC transfers use DMA
channel 0:

```text
$FD40/$FD41  DMA address H/L
$FD42/$FD43  DMA byte count H/L
$FD50        DMA mode/status
$FD94        DMA physical-address bank (PA19-16)
```

The current cold-boot destination lies entirely below physical `$10000`, so the
DMA bank register is zero. Each physical sector is transferred as one `$0100`
byte DMA operation. The IPL waits for DMA completion, checks both DMA and FDC
error status, and leaves channel 0 disabled after the load.

The direct-load stream begins at raw offset `$0200` (T0/H0/S3) and is kept
entirely within cylinder 0:

```text
Disk raw        RAM             Contents
$0200-$1BFF ->  $C400-$DDFF     CCP + BDOS + BIOS (`system56.bin`)
$1C00-...    ->  $DE00-...       resident 6809 I/O server
```

`system56.bin` occupies 26 physical sectors. The resident I/O server is limited
to `$0400` bytes in the current layout, so the combined direct-load image fits
in the 30 sectors remaining on cylinder 0:

```text
T0/H0/S3-S16
T0/H1/S1-S16
```

No SEEK or STEP operation is issued by the IPL.

After the direct load completes, the IPL clears the mailbox at `$EC00-$EC09`
and the CP/M disk workspace at `$F000-$F247`, installs `JP $DA00` at Z80 reset
address `$0000`, clears the initial IOBYTE/current-drive bytes, and jumps to the
resident I/O server at `$DE00`.

`IoServerStart` writes `$01` to `$FD05`, releasing the Z80. The Z80 starts at
`$0000`, jumps to the BIOS cold-boot entry at `$DA00`, and the BIOS continues
to the CCP at `$C400`.

The former position-independent stage-2 loader at `$2600` is no longer used.
The earlier `$4000` execution problem therefore does not affect the normal cold
boot path: the only 6809 boot code executed before the resident server is the
ROM-loaded IPL at `$0400`.

## Warm boot

Cold boot and warm boot share the same single on-disk CP/M system image. There
is no second copy of `system56.bin` in cylinder 1.

On CP/M WBOOT the Z80 BIOS posts `MBCMD_WBOOT` and hands control to the resident
6809 I/O server. The server reloads only CCP+BDOS, which is exactly `$1600`
bytes (22 physical sectors), from T0/H0/S3 onward directly to `$C400-$D9FF`.
Those 22 sectors remain entirely on cylinder 0.

BIOS at `$DA00-$DDFF` and the resident I/O server at `$DE00` stay resident
across WBOOT. After the reload completes, the BIOS restores the current-drive
state from CP/M page zero, resets the default DMA address to `$0080`, reinstalls
the page-zero WBOOT and BDOS vectors, and jumps to the reloaded CCP at `$C400`.
