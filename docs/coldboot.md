# Cold boot

The FM-11 2D boot path has two MC6809 stages.

## Stage 1: ROM-loaded IPL

`build/6809/ipl_2d.bin` is assembled at `$0400` and is limited to 512 bytes.
The FM-11 ROM IPL loads physical sectors T0/H0/S1-S2 (2 x 256 bytes) to `$0400`
and transfers control there. This is the same ROM-loading convention used by
the FM-11 NitrOS-9 Level 1 2D IPL.

Stage 1 uses `$2000` as its stack, disables DMA channel 0 for the Mini FDC,
selects drive 0, then reads only the remaining 30 sectors of cylinder 0:

```text
T0/H0/S3-S16
T0/H1/S1-S16
```

Those sectors are loaded contiguously to `$2600-$43FF`, after which stage 1
jumps to `$2600`. Keeping the complete stage-2 disk read on cylinder 0 avoids
any SEEK/STEP operation in the ROM-loaded IPL and matches the proven NitrOS-9
boot pattern, which also stays on track 0.

`$2600` is the established stage-2 execution address for this port. FM-11 boot
testing showed that placing the stage-2 entry at `$4000` caused unstable 6809
execution, while moving the same position-independent image below `$4000`
allowed CP/M to reach the CCP prompt and successfully execute `DIR`. The image
itself may extend above `$4000`; the observed restriction concerns the stage-2
execution start address.

The stage-2 image therefore has a hard maximum size of `$1E00` bytes.

## Stage 2

`build/6809/loader.bin` is a position-independent MC6809 stage-2 image. It
embeds:

- `build/cpm22/system56.bin` (Z80 `$C400-$DDFF`)
- `build/6809/ioserver.bin` (resident service at `$DE00-$EBFF`)

At run time stage 2:

1. copies the 56K CP/M system image to `$C400`,
2. copies the resident 6809 I/O server to `$DE00`,
3. clears the mailbox at `$EC00-$EC09`,
4. clears the CP/M disk workspace at `$F000-$F247`,
5. installs `JP $DA00` at Z80 reset address `$0000`, and
6. jumps to the resident I/O server at `$DE00`.

`IoServerStart` writes `$01` to `$FD05`, releasing the Z80. The Z80 starts at
`$0000`, jumps to the BIOS cold-boot entry at `$DA00`, and the BIOS continues
to the CCP at `$C400`.

The stage-2 load region `$2600-$43FF` is temporary boot storage. The loader is
position independent and copies its embedded payloads to their final locations
before transferring control to the resident I/O server.

## Warm boot

The second reserved 2D cylinder contains an exact copy of `system56.bin` at raw
offset `$2000`. It occupies `$1A00` bytes, corresponding to 26 physical
256-byte sectors, and maps directly to Z80 `$C400-$DDFF`.

On CP/M WBOOT the Z80 BIOS posts `MBCMD_WBOOT` and hands control to the resident
6809 I/O server. The 6809 reads drive A:, physical cylinder 1, side 0 sectors
1-16 followed by side 1 sectors 1-10, and copies them directly to
`$C400-$DDFF`. This restores CCP, BDOS, and BIOS while the Z80 is stopped.

After the reload completes, the 6809 returns control to the Z80. Because the
BIOS image is restored with an identical copy, execution resumes safely in the
BIOS call path. The BIOS then restores the current-drive state from CP/M page
zero, resets the default DMA address to `$0080`, reinstalls the page-zero WBOOT
and BDOS vectors, and jumps to the reloaded CCP at `$C400`.
