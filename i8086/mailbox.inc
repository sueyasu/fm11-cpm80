; Common mailbox ABI (logical addresses in shared CP/M segment (physical bank one on 8088+Z80)).
BOOTDRV equ 0xfbf4
BOOTTYPE equ 0xfbf5
MBOX_CMD equ 0xfbf6
MBOX_STATUS equ 0xfbf7
MBOX_DRIVE equ 0xfbf8
MBOX_DATA equ 0xfbf9
MBOX_TRACK equ 0xfbfa
MBOX_SECTOR equ 0xfbfc
MBOX_DMA equ 0xfbfe

MBCMD_CACHE_SYNC equ 0x04
MBCMD_CACHE_RESET equ 0x05

MBCMD_HDD_GEOM equ 0x06

MBCMD_RAW_GEOM equ 0x07
MBCMD_RAW_READ equ 0x08
MBCMD_RAW_WRITE equ 0x09
MBCMD_RAW_FORMAT equ 0x0a
MBCMD_CPU_TYPE equ 0x0b
