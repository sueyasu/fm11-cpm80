* FM-11 CP/M-80 6809 loader skeleton.
*
* The final load address and stage-1 IPL interface are intentionally left
* open until the boot-track layout is fixed.  This file defines the cold
* boot responsibilities and the hand-off contract to ioserver.asm.

        include "../include/6809/fm11.inc"

LoaderEntry
        orcc    #$50            * IRQ/FIRQ off during cold boot

* TODO when boot layout is implemented:
*   1. initialize the console/8251 environment used by the Z80 BIOS
*   2. load the 56K CP/M image so that:
*        CCP  = Z80 $C400
*        BDOS = Z80 $CC00
*        BIOS = Z80 $DA00
*   3. install/retain the resident 6809 I/O service at $DE00
*   4. clear the mailbox at $EC00
*   5. initialize Mini FDC and Standard FDC to a known state
*   6. enter IoServerStart; it performs the first FD05 hand-off to Z80
*
* No disk-format assumptions should be duplicated here.  All CP/M logical
* sector interpretation belongs to the resident I/O service.

        clr     MBOX_CMD
        clr     MBOX_STATUS

* During framework development this symbol is expected to be resolved with
* ioserver.asm by the eventual build/link step.
        jmp     IoServerStart
