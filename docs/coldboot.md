# Cold boot

The FM-11 2D boot path has two MC6809 stages.

## Stage 1: ROM-loaded IPL

`build/6809/ipl_2d.bin` is assembled at `$0400` and is limited to 512 bytes.
The FM-11 ROM IPL loads physical sectors T0/H0/S1-S2 (2 x 256 bytes) to `$0400`
and transfers control there. This is the same ROM-loading convention used by
the FM-11 NitrOS-9 Level 1 2D IPL.

Stage 1 disables DMA channel 0 for the Mini FDC, selects drive 0, then reads only
the remaining 30 sectors of cylinder 0:

```text
T0/H0/S3-S16
T0/H1/S1-S16
```

Those sectors are loaded contiguously to `$4000-$5DFF`, after which stage 1
jumps to `$4000`.  Keeping the complete stage-2 load on cylinder 0 avoids any
SEEK/STEP operation in the ROM-loaded IPL and matches the proven NitrOS-9 boot
pattern, which also stays on track 0.

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

The fixed stage-2 load address `$4000` is deliberately outside the destination
range `$C400-$F247`, so stage 2 can safely copy its embedded payloads to their
final locations.
