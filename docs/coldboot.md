# Cold-boot stage 2

`build/6809/loader.bin` is a position-independent MC6809 stage-2 cold image. It embeds both files produced earlier in the build:

- `build/cpm22/system56.bin` (Z80 `$C400-$DDFF`)
- `build/6809/ioserver.bin` (resident service at `$DE00-$EBFF`)

At run time the loader:

1. copies the 56K CP/M system image to `$C400`,
2. copies the resident 6809 I/O server to `$DE00`,
3. clears the mailbox at `$EC00-$EC09`,
4. clears the CP/M disk workspace at `$F000-$F247`,
5. installs `JP $DA00` at Z80 reset address `$0000`, and
6. jumps to the resident I/O server at `$DE00`.

`IoServerStart` then writes `$01` to `$FD05`, releasing the Z80. The Z80 starts at `$0000`, jumps to the BIOS cold-boot entry at `$DA00`, and the BIOS continues to the CCP at `$C400`.

## Stage-1 loading constraint

The stage-2 image is position independent, so it does not require a fixed load address. However, the *entire* `loader.bin` (code plus embedded payloads) must initially reside in RAM that does not overlap the destination area it overwrites while copying:

```text
C400-F247
```

The eventual FM-11 IPL should therefore load `loader.bin` wholly outside that range and jump to its first byte. The exact IPL load address is intentionally left for the boot-track implementation rather than being hard-coded into the stage-2 image.
