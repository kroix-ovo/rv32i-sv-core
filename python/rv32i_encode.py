"""Small, dependency-free RV32I instruction encoder.

This is not meant to replace a real RISC-V assembler. It gives the repository's
tests a readable way to create machine words without requiring a cross compiler.
The field layout functions mirror the instruction-format drawing in the docs.
"""

from __future__ import annotations


def _signed(value: int, bits: int) -> int:
    minimum = -(1 << (bits - 1))
    maximum = (1 << (bits - 1)) - 1
    if not minimum <= value <= maximum:
        raise ValueError(f"{value} does not fit in a signed {bits}-bit field")
    return value & ((1 << bits) - 1)


def r_type(funct7: int, rs2: int, rs1: int, funct3: int, rd: int,
           opcode: int = 0x33) -> int:
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def i_type(imm: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    return (_signed(imm, 12) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def s_type(imm: int, rs2: int, rs1: int, funct3: int) -> int:
    encoded = _signed(imm, 12)
    return ((encoded >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((encoded & 0x1F) << 7) | 0x23


def b_type(offset: int, rs2: int, rs1: int, funct3: int) -> int:
    if offset & 1:
        raise ValueError("branch offset must be two-byte aligned")
    encoded = _signed(offset, 13)
    return (((encoded >> 12) & 1) << 31) | (((encoded >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (((encoded >> 1) & 0xF) << 8) | (((encoded >> 11) & 1) << 7) | 0x63


def u_type(value: int, rd: int, opcode: int) -> int:
    return (value & 0xFFFFF000) | (rd << 7) | opcode


def j_type(offset: int, rd: int) -> int:
    if offset & 1:
        raise ValueError("jump offset must be two-byte aligned")
    encoded = _signed(offset, 21)
    return (((encoded >> 20) & 1) << 31) | (((encoded >> 1) & 0x3FF) << 21) | (((encoded >> 11) & 1) << 20) | (((encoded >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


def lui(rd: int, value: int) -> int: return u_type(value, rd, 0x37)
def auipc(rd: int, value: int) -> int: return u_type(value, rd, 0x17)
def jalr(rd: int, rs1: int, imm: int = 0) -> int: return i_type(imm, rs1, 0, rd, 0x67)


def load(rd: int, rs1: int, imm: int, funct3: int) -> int:
    return i_type(imm, rs1, funct3, rd, 0x03)


def store(rs2: int, rs1: int, imm: int, funct3: int) -> int:
    return s_type(imm, rs2, rs1, funct3)


def op_imm(rd: int, rs1: int, imm: int, funct3: int) -> int:
    return i_type(imm, rs1, funct3, rd, 0x13)


def shift_imm(rd: int, rs1: int, shamt: int, funct3: int,
              arithmetic: bool = False) -> int:
    if not 0 <= shamt < 32:
        raise ValueError("RV32I shift amount must be between 0 and 31")
    upper = 0x20 if arithmetic else 0
    return i_type((upper << 5) | shamt, rs1, funct3, rd, 0x13)


def op(rd: int, rs1: int, rs2: int, funct3: int,
       alternate: bool = False) -> int:
    return r_type(0x20 if alternate else 0, rs2, rs1, funct3, rd)


FENCE = 0x0000000F
ECALL = 0x00000073
EBREAK = 0x00100073

