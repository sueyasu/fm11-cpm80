; 8088+Z80 physical memory layout, minimum 128 KiB.
; Z80 fixed low/high windows are in bank 1 with the 8088 main card.
; CBIOS selects bank 1 for its middle 32 KiB window as well.
NATIVE_SEG equ 0x0400
NATIVE_SLOT equ 0x1800
NATIVE_STACK_TOP equ 0x2000
NATIVE_PHYS equ NATIVE_SEG*16
CACHE_SEG equ 0x0600
CPM_SEG equ 0x1000

; Whole-HDD reserved cylinder layout (256-byte physical sectors).
HDD_BOOT_DRIVE equ 8
HDD_SERVER_LBA equ 2
HDD_SYSTEM_LBA equ HDD_SERVER_LBA+NATIVE_SLOT/256
