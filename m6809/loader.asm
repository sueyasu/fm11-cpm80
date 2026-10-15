* FM-11 CP/M-80 6809 loader skeleton.
*
* The final stage-1 IPL load address is still open, but this source is kept
* independently assemblable so the build can check its syntax now.

        include "fm11.inc"

IOSERVER_BASE   equ     $DE00

LoaderEntry
        orcc    #$50            * IRQ/FIRQ off during cold boot

* TODO when boot layout is implemented:
*   1. initialize the console/8251 environment used by the Z80 BIOS
*   2. load the 56K CP/M image so that:
*        CCP  = Z80 $C400
*        BDOS = Z80 $CC00
*        BIOS = Z80 $DA00
*   3. load/retain the resident 6809 I/O service at $DE00-$EFFF
*   4. leave $F000-$F247 available for CP/M DIRBUF/CSV/ALV workspace
*   5. clear the mailbox at $EC00
*   6. initialize Mini FDC and Standard FDC to a known state
*   7. jump to IoServerStart; it performs the first FD05 hand-off to Z80

        clr     MBOX_CMD
        clr     MBOX_STATUS
        jmp     IOSERVER_BASE
