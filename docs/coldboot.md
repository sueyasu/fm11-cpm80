# Cold boot

The FM-11 2D boot path now uses a single ROM-loaded MC6809 IPL. There is no
second-stage loader.

## ROM-loaded IPL

`build/6809/ipl_2d.bin` is assembled at `$0400` and is limited to 512 bytes.
The FM-11 ROM IPL loads physical sectors T0/H0/S1-S2 (2 x 256 bytes) to `$0400`
and transfers control there.

The IPL uses `$2000` as its stack, disables DMA channel 0 for the Mini FDC,
selects drive 0, and then reads the on-disk system image directly to its final
RAM addresses.

The direct-load range is 40 physical 256-byte sectors beginning at raw offset
`$0200` (T0/H0/S3):

```text
Disk raw        RAM             Contents
$0200-$1BFF ->  $C400-$DDFF     CCP + BDOS + BIOS (`system56.bin`)
$1C00-$29FF ->  $DE00-$EBFF     resident 6809 I/O-server slot
```

The I/O-server slot is fixed at `$0E00` bytes and zero padded after the actual
`ioserver.bin`. This preserves the current execution map while allowing the IPL
to perform one contiguous transfer to `$C400-$EBFF`.

The first 30 sectors are the remainder of cylinder 0:

```text
T0/H0/S3-S16
T0/H1/S1-S16
```

The final 10 sectors are T1/H0/S1-S10. Crossing from cylinder 0 to cylinder 1
uses a WD17xx SEEK; merely changing the track register is not relied upon.

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

Cold boot and warm boot now share the same single on-disk CP/M system image.
There is no second copy of `system56.bin` in cylinder 1.

On CP/M WBOOT the Z80 BIOS posts `MBCMD_WBOOT` and hands control to the resident
6809 I/O server. The server reloads only CCP+BDOS, which is exactly `$1600`
bytes (22 physical sectors), from T0/H0/S3 onward directly to `$C400-$D9FF`.
Those 22 sectors remain entirely on cylinder 0.

BIOS at `$DA00-$DDFF` and the resident I/O server at `$DE00-$EBFF` stay resident
across WBOOT. After the reload completes, the BIOS restores the current-drive
state from CP/M page zero, resets the default DMA address to `$0080`, reinstalls
the page-zero WBOOT and BDOS vectors, and jumps to the reloaded CCP at `$C400`.
