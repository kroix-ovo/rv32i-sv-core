"""Build the directed CPU test and the Arty LED demo.

Run this file from the repository root. The generated hex format is accepted by
SystemVerilog $readmemh and by Vivado memory initialization.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))

import rv32i_encode as rv  # noqa: E402


@dataclass
class Fixup:
    kind: str
    index: int
    args: tuple[int, ...]
    label: str


class Program:
    def __init__(self) -> None:
        self.words: list[int] = []
        self.labels: dict[str, int] = {}
        self.fixups: list[Fixup] = []

    @property
    def pc(self) -> int:
        return len(self.words) * 4

    def emit(self, word: int) -> None:
        self.words.append(word & 0xFFFF_FFFF)

    def label(self, name: str) -> None:
        if name in self.labels:
            raise ValueError(f"duplicate label: {name}")
        self.labels[name] = self.pc

    def branch(self, funct3: int, rs1: int, rs2: int, label: str) -> None:
        self.fixups.append(Fixup("branch", len(self.words), (funct3, rs1, rs2), label))
        self.emit(0)

    def jal(self, rd: int, label: str) -> None:
        self.fixups.append(Fixup("jal", len(self.words), (rd,), label))
        self.emit(0)

    def li(self, rd: int, value: int) -> None:
        value &= 0xFFFF_FFFF
        signed_value = value if value < 0x8000_0000 else value - 0x1_0000_0000
        if -2048 <= signed_value <= 2047:
            self.emit(rv.op_imm(rd, 0, signed_value, 0b000))
            return
        upper = (value + 0x800) & 0xFFFF_F000
        lower = (value - upper) & 0xFFF
        lower = lower if lower < 0x800 else lower - 0x1000
        self.emit(rv.lui(rd, upper))
        self.emit(rv.op_imm(rd, rd, lower, 0b000))

    def resolve(self) -> list[int]:
        for fixup in self.fixups:
            if fixup.label not in self.labels:
                raise ValueError(f"unknown label: {fixup.label}")
            pc = fixup.index * 4
            offset = self.labels[fixup.label] - pc
            if fixup.kind == "branch":
                funct3, rs1, rs2 = fixup.args
                self.words[fixup.index] = rv.b_type(offset, rs2, rs1, funct3)
            else:
                (rd,) = fixup.args
                self.words[fixup.index] = rv.j_type(offset, rd)
        return self.words


def build_directed() -> list[int]:
    p = Program()

    def check(register: int, expected: int) -> None:
        p.li(30, expected)
        p.branch(0b001, register, 30, "fail")  # BNE

    # Upper-immediate and immediate arithmetic instructions.
    p.emit(rv.op_imm(1, 0, 5, 0b000))                # addi x1, x0, 5
    check(1, 5)
    p.emit(rv.lui(2, 0x1234_5000))                   # lui x2, 0x12345
    check(2, 0x1234_5000)
    auipc_pc = p.pc
    p.emit(rv.auipc(3, 0))
    check(3, auipc_pc)
    p.emit(rv.op_imm(4, 1, -8, 0b000))               # -3
    check(4, -3)
    p.emit(rv.op_imm(5, 4, 0, 0b010))                # slti
    check(5, 1)
    p.emit(rv.op_imm(6, 4, 1, 0b011))                # sltiu
    check(6, 0)
    p.emit(rv.op_imm(7, 1, 3, 0b100))                # xori
    check(7, 6)
    p.emit(rv.op_imm(8, 1, 2, 0b110))                # ori
    check(8, 7)
    p.emit(rv.op_imm(9, 8, 6, 0b111))                # andi
    check(9, 6)
    p.emit(rv.shift_imm(10, 1, 3, 0b001))            # slli
    check(10, 40)
    p.emit(rv.shift_imm(11, 10, 2, 0b101))           # srli
    check(11, 10)
    p.emit(rv.shift_imm(12, 4, 1, 0b101, True))      # srai
    check(12, -2)

    # All ten register-to-register ALU instructions.
    p.li(13, 2)
    p.emit(rv.op(14, 1, 13, 0b000)); check(14, 7)             # add
    p.emit(rv.op(14, 1, 13, 0b000, True)); check(14, 3)       # sub
    p.emit(rv.op(14, 1, 13, 0b001)); check(14, 20)            # sll
    p.emit(rv.op(14, 4, 1, 0b010)); check(14, 1)              # slt
    p.emit(rv.op(14, 4, 1, 0b011)); check(14, 0)              # sltu
    p.emit(rv.op(14, 1, 13, 0b100)); check(14, 7)             # xor
    p.emit(rv.op(14, 10, 13, 0b101)); check(14, 10)           # srl
    p.emit(rv.op(14, 4, 13, 0b101, True)); check(14, -1)      # sra
    p.emit(rv.op(14, 1, 13, 0b110)); check(14, 7)             # or
    p.emit(rv.op(14, 1, 13, 0b111)); check(14, 0)             # and

    # Byte lanes and signed extension are easy places for load/store bugs.
    # Keep scratch data well above the generated instruction image.
    p.li(20, 0x800)
    p.li(21, 0x80FF_7F01)
    p.emit(rv.store(21, 20, 0, 0b010))                        # sw
    p.emit(rv.load(22, 20, 0, 0b000)); check(22, 1)           # lb
    p.emit(rv.load(22, 20, 1, 0b000)); check(22, 0x7F)
    p.emit(rv.load(22, 20, 2, 0b000)); check(22, -1)
    p.emit(rv.load(22, 20, 3, 0b000)); check(22, -128)
    p.emit(rv.load(22, 20, 2, 0b100)); check(22, 0xFF)        # lbu
    p.emit(rv.load(22, 20, 0, 0b001)); check(22, 0x7F01)      # lh
    p.emit(rv.load(22, 20, 2, 0b001)); check(22, 0xFFFF_80FF)
    p.emit(rv.load(22, 20, 2, 0b101)); check(22, 0x80FF)      # lhu
    p.emit(rv.load(22, 20, 0, 0b010)); check(22, 0x80FF_7F01) # lw
    p.li(23, 0xAA)
    p.emit(rv.store(23, 20, 4, 0b000))                        # sb
    p.emit(rv.load(22, 20, 4, 0b100)); check(22, 0xAA)
    p.li(23, 0xBEEF)
    p.emit(rv.store(23, 20, 6, 0b001))                        # sh
    p.emit(rv.load(22, 20, 6, 0b101)); check(22, 0xBEEF)

    # Each branch below must skip the jump to the shared failure handler.
    for number, (funct3, rs1, rs2) in enumerate([
        (0b000, 1, 1),   # beq
        (0b001, 1, 13),  # bne
        (0b100, 4, 1),   # blt
        (0b101, 1, 4),   # bge
        (0b110, 13, 1),  # bltu
        (0b111, 1, 13),  # bgeu
    ]):
        label = f"branch_ok_{number}"
        p.branch(funct3, rs1, rs2, label)
        p.jal(0, "fail")
        p.label(label)

    # A deliberately false BEQ checks the not-taken path.
    p.branch(0b000, 1, 13, "fail")

    jal_pc = p.pc
    p.jal(10, "jal_target")
    p.jal(0, "fail")
    p.label("jal_target")
    check(10, jal_pc + 4)

    # The absolute target is close enough to construct with one ADDI.
    jalr_setup_pc = p.pc
    jalr_target = jalr_setup_pc + 12
    p.emit(rv.op_imm(11, 0, jalr_target, 0b000))
    jalr_pc = p.pc
    p.emit(rv.jalr(12, 11, 0))
    p.jal(0, "fail")
    check(12, jalr_pc + 4)

    p.emit(rv.FENCE)
    p.li(30, 0x600D_600D)
    p.emit(rv.store(30, 20, 0x100, 0b010))
    p.label("pass_loop")
    p.jal(0, "pass_loop")

    p.label("fail")
    p.li(30, 0xBAD0_0001)
    p.emit(rv.store(30, 20, 0x100, 0b010))
    p.label("fail_loop")
    p.jal(0, "fail_loop")
    return p.resolve()


def build_fpga_demo() -> list[int]:
    p = Program()
    p.li(1, 0x1000_0000)        # memory-mapped GPIO address
    p.li(2, 0)
    p.label("outer")
    p.emit(rv.op_imm(2, 2, 1, 0b100))  # xori x2, x2, 1
    p.emit(rv.store(2, 1, 0, 0b010))
    p.li(3, 6_250_000)
    p.label("delay")
    p.emit(rv.op_imm(3, 3, -1, 0b000))
    p.branch(0b001, 3, 0, "delay")
    p.jal(0, "outer")
    return p.resolve()


def write_hex(path: Path, words: list[int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"{word:08x}\n" for word in words), encoding="ascii")


if __name__ == "__main__":
    write_hex(ROOT / "sim/programs/rv32i_directed.hex", build_directed())
    write_hex(ROOT / "sim/programs/fpga_demo.hex", build_fpga_demo())
    print("Wrote directed CPU test and FPGA LED demo hex files.")
