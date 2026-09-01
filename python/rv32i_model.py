"""Readable instruction-level reference model for this RV32I project.

The SystemVerilog core is the design under test. This Python model is a second,
independent description of the ISA. It is useful for checking generated machine
code and for explaining an instruction one architectural step at a time. It is
not cycle accurate and it intentionally has no knowledge of the RTL state
machine.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


def u32(value: int) -> int:
    return value & 0xFFFF_FFFF


def signed(value: int, bits: int = 32) -> int:
    value &= (1 << bits) - 1
    sign_bit = 1 << (bits - 1)
    return value - (1 << bits) if value & sign_bit else value


def sign_extend(value: int, bits: int) -> int:
    return u32(signed(value, bits))


@dataclass
class Trap:
    cause: int
    pc: int
    tval: int


class RV32IModel:
    def __init__(self, memory_bytes: int = 4096) -> None:
        self.memory = bytearray(memory_bytes)
        self.regs = [0] * 32
        self.pc = 0
        self.trap: Trap | None = None
        self.retired = 0

    def load_hex(self, path: Path) -> None:
        for word_index, line in enumerate(path.read_text(encoding="ascii").splitlines()):
            word = int(line.split()[0], 16)
            address = word_index * 4
            self.memory[address:address + 4] = word.to_bytes(4, "little")

    def _read(self, address: int, size: int) -> int | None:
        if address + size > len(self.memory):
            return None
        return int.from_bytes(self.memory[address:address + size], "little")

    def _write(self, address: int, size: int, value: int) -> bool:
        if address + size > len(self.memory):
            return False
        self.memory[address:address + size] = u32(value).to_bytes(4, "little")[:size]
        return True

    def _raise(self, cause: int, tval: int) -> None:
        self.trap = Trap(cause, self.pc, u32(tval))

    def step(self) -> None:
        if self.trap is not None:
            return
        if self.pc & 3:
            self._raise(0, self.pc)
            return

        instruction = self._read(self.pc, 4)
        if instruction is None:
            self._raise(1, self.pc)
            return

        opcode = instruction & 0x7F
        rd = (instruction >> 7) & 0x1F
        funct3 = (instruction >> 12) & 7
        rs1 = (instruction >> 15) & 0x1F
        rs2 = (instruction >> 20) & 0x1F
        funct7 = instruction >> 25
        a = self.regs[rs1]
        b = self.regs[rs2]
        next_pc = u32(self.pc + 4)
        write_value: int | None = None

        imm_i = sign_extend(instruction >> 20, 12)
        imm_s = sign_extend(((instruction >> 25) << 5) | ((instruction >> 7) & 0x1F), 12)
        imm_b = sign_extend((((instruction >> 31) & 1) << 12) |
                            (((instruction >> 7) & 1) << 11) |
                            (((instruction >> 25) & 0x3F) << 5) |
                            (((instruction >> 8) & 0xF) << 1), 13)
        imm_u = instruction & 0xFFFF_F000
        imm_j = sign_extend((((instruction >> 31) & 1) << 20) |
                            (((instruction >> 12) & 0xFF) << 12) |
                            (((instruction >> 20) & 1) << 11) |
                            (((instruction >> 21) & 0x3FF) << 1), 21)

        if opcode == 0x37:                                      # LUI
            write_value = imm_u
        elif opcode == 0x17:                                    # AUIPC
            write_value = u32(self.pc + imm_u)
        elif opcode == 0x6F:                                    # JAL
            target = u32(self.pc + imm_j)
            if target & 3:
                self._raise(0, target)
                return
            write_value, next_pc = next_pc, target
        elif opcode == 0x67 and funct3 == 0:                     # JALR
            target = u32(a + imm_i) & 0xFFFF_FFFE
            if target & 3:
                self._raise(0, target)
                return
            write_value, next_pc = next_pc, target
        elif opcode == 0x63:                                    # Branches
            conditions = {
                0: a == b,
                1: a != b,
                4: signed(a) < signed(b),
                5: signed(a) >= signed(b),
                6: a < b,
                7: a >= b,
            }
            if funct3 not in conditions:
                self._raise(2, instruction)
                return
            if conditions[funct3]:
                target = u32(self.pc + imm_b)
                if target & 3:
                    self._raise(0, target)
                    return
                next_pc = target
        elif opcode == 0x03:                                    # Loads
            sizes = {0: (1, False), 1: (2, False), 2: (4, False),
                     4: (1, True), 5: (2, True)}
            if funct3 not in sizes:
                self._raise(2, instruction)
                return
            size, unsigned_load = sizes[funct3]
            address = u32(a + imm_i)
            if address & (size - 1):
                self._raise(4, address)
                return
            value = self._read(address, size)
            if value is None:
                self._raise(5, address)
                return
            write_value = value if unsigned_load else sign_extend(value, size * 8)
        elif opcode == 0x23:                                    # Stores
            sizes = {0: 1, 1: 2, 2: 4}
            if funct3 not in sizes:
                self._raise(2, instruction)
                return
            size = sizes[funct3]
            address = u32(a + imm_s)
            if address & (size - 1):
                self._raise(6, address)
                return
            if not self._write(address, size, b):
                self._raise(7, address)
                return
        elif opcode == 0x13:                                    # Immediate ALU
            if funct3 == 0: write_value = u32(a + imm_i)
            elif funct3 == 2: write_value = int(signed(a) < signed(imm_i))
            elif funct3 == 3: write_value = int(a < imm_i)
            elif funct3 == 4: write_value = a ^ imm_i
            elif funct3 == 6: write_value = a | imm_i
            elif funct3 == 7: write_value = a & imm_i
            elif funct3 == 1 and funct7 == 0: write_value = u32(a << rs2)
            elif funct3 == 5 and funct7 == 0: write_value = a >> rs2
            elif funct3 == 5 and funct7 == 0x20: write_value = u32(signed(a) >> rs2)
            else:
                self._raise(2, instruction)
                return
        elif opcode == 0x33:                                    # Register ALU
            operation = (funct7, funct3)
            if operation == (0, 0): write_value = u32(a + b)
            elif operation == (0x20, 0): write_value = u32(a - b)
            elif operation == (0, 1): write_value = u32(a << (b & 31))
            elif operation == (0, 2): write_value = int(signed(a) < signed(b))
            elif operation == (0, 3): write_value = int(a < b)
            elif operation == (0, 4): write_value = a ^ b
            elif operation == (0, 5): write_value = a >> (b & 31)
            elif operation == (0x20, 5): write_value = u32(signed(a) >> (b & 31))
            elif operation == (0, 6): write_value = a | b
            elif operation == (0, 7): write_value = a & b
            else:
                self._raise(2, instruction)
                return
        elif opcode == 0x0F and funct3 == 0:                     # FENCE
            pass
        elif instruction == 0x0000_0073:                        # ECALL
            self._raise(11, 0)
            return
        elif instruction == 0x0010_0073:                        # EBREAK
            self._raise(3, 0)
            return
        else:
            self._raise(2, instruction)
            return

        if write_value is not None and rd != 0:
            self.regs[rd] = u32(write_value)
        self.regs[0] = 0
        self.pc = next_pc
        self.retired += 1


def run_directed_test(repo: Path) -> tuple[int, int]:
    model = RV32IModel()
    model.load_hex(repo / "sim/programs/rv32i_directed.hex")
    signature_address = 0x900
    for _ in range(5000):
        model.step()
        if model.trap:
            raise RuntimeError(f"reference model trapped: {model.trap}")
        signature = model._read(signature_address, 4)
        if signature:
            if signature != 0x600D_600D:
                raise RuntimeError(f"directed program failed with signature 0x{signature:08x}")
            return model.retired, signature
    raise RuntimeError("reference model timed out")


if __name__ == "__main__":
    repo_root = Path(__file__).resolve().parents[1]
    retired_count, pass_signature = run_directed_test(repo_root)
    print(f"PASS: reference model retired {retired_count} instructions; signature=0x{pass_signature:08x}")

