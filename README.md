# FM-11 CP/M-80

Open-source BIOS, boot and I/O support for running CP/M-80 on the Fujitsu FM-11 with the Z80 card.

Initial target:

- CP/M 2.2
- A: through D: = 2D floppy drives 0 through 3
- E: through H: = 2HD floppy drives 0 through 3
- No HDD or bubble-memory support initially
- Z80 BIOS with 6809-resident I/O service for floppy access

The implementation is intended to follow the FM-11 hardware architecture and Fujitsu disk formats where useful, without requiring binary compatibility with Fujitsu's original CP/M implementation.
