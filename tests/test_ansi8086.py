#!/usr/bin/env python3
"""Build and execute the shared ANSI translator with a mock native transport.

Requires NASM and Python unicorn (pip install unicorn). No ROM/disk needed.
"""
import os
from pathlib import Path
import struct
import subprocess
import tempfile
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16
from unicorn.x86_const import UC_X86_REG_AX, UC_X86_REG_BX, UC_X86_REG_CX, UC_X86_REG_DX, UC_X86_REG_SI, UC_X86_REG_DI, UC_X86_REG_BP, UC_X86_REG_SP, UC_X86_REG_EFLAGS, UC_X86_REG_IP

source = next(p for p in (Path("i8086/ansi_console.inc"), Path("src/cbios_ansi.inc")) if p.exists()).resolve()
harness = '''cpu 8086
bits 16
org 0
dw ansi_putc, ansi_row, ansi_col, ansi_attr, ansi_state, log_count, log_bytes, fail_after
local_native_putc:
    push bx
    mov bx,[log_count]
    cmp bx,[fail_after]
    jae .fail
    mov [log_bytes+bx],al
    inc word [log_count]
    pop bx
    clc
    ret
.fail:
    pop bx
    stc
    ret
%include "{source}"
log_count dw 0
fail_after dw 0xffff
log_bytes times 4096 db 0
'''
with tempfile.TemporaryDirectory() as td:
    asm = Path(td) / "test.asm"
    binfile = Path(td) / "test.bin"
    asm.write_text(harness.format(source=source.as_posix()))
    subprocess.run([os.environ.get("NASM", "nasm"), "-f", "bin", str(asm), "-o", str(binfile)], check=True)
    code = binfile.read_bytes()

entry, row, col, attr, state, count, log, fail = struct.unpack_from("<8H", code)
STOP = 0xf000
STACK = 0xeffe
regs = (UC_X86_REG_AX, UC_X86_REG_BX, UC_X86_REG_CX, UC_X86_REG_DX,
        UC_X86_REG_SI, UC_X86_REG_DI, UC_X86_REG_BP)

def machine():
    u = Uc(UC_ARCH_X86, UC_MODE_16)
    u.mem_map(0, 0x10000)
    u.mem_write(0, code)
    return u

def byte(u, addr):
    return u.mem_read(addr, 1)[0]

def output(u):
    n = struct.unpack("<H", u.mem_read(count, 2))[0]
    return bytes(u.mem_read(log, n))

def feed(u, data, failure=False):
    for i, ch in enumerate(data):
        values = [0x5a00 | ch, 0x1234, 0x2345, 0x3456, 0x4567, 0x5678, 0x6789]
        for reg, val in zip(regs, values):
            u.reg_write(reg, val)
        u.reg_write(UC_X86_REG_SP, STACK)
        u.mem_write(STACK, struct.pack("<H", STOP))
        u.reg_write(UC_X86_REG_EFLAGS, 0x202)
        u.emu_start(entry, STOP, count=100000)
        assert u.reg_read(UC_X86_REG_IP) == STOP
        assert u.reg_read(UC_X86_REG_SP) == STACK + 2
        assert [u.reg_read(r) for r in regs] == values
        expected = 0x203 if failure and i == len(data)-1 else 0x202
        assert u.reg_read(UC_X86_REG_EFLAGS) & 0xffff == expected

u = machine()
feed(u, b"\x1b[1;5;31m")
assert output(u) == b"\x1bG2" and byte(u, attr) == 0x32
u = machine()
feed(u, b"\x1b[1;5;7;31;22;25;27;39m")
assert output(u) == b"\x1bG\x07"
u = machine()
feed(u, b"\x1b[1;5;7;31;22;25;27;39;32m")
assert output(u) == b"" and byte(u, attr) == 7
u = machine()
feed(u, b"\x1b[999;999H")
assert output(u) == bytes([0x12, 79, 24])
assert (byte(u,row), byte(u,col)) == (25,80)
feed(u, b"\x1b[3X")
assert output(u).endswith(b"\x1bT" + bytes([0x12,79,24]))
assert (byte(u,row), byte(u,col)) == (25,80)
u = machine()
feed(u, b"\t")
assert byte(u,col) == 9
feed(u, b"\x0c")
assert (byte(u,row), byte(u,col)) == (1,1)
feed(u, b"\x1b[?25l")
assert output(u) == b"\t\x0c"
u = machine()
u.mem_write(fail, struct.pack("<H", 1))
feed(u, b"\x1b[10;20H", failure=True)
assert output(u) == b"\x12"
assert (byte(u,row), byte(u,col), byte(u,state)) == (1,1,0)
u.mem_write(fail, struct.pack("<H", 0xffff))
feed(u, b"A")
assert output(u) == b"\x12A" and byte(u,col) == 2
print("PASS: shared ANSI translator (8086 execution, mock transport)")
