"""Cycle-accurate cocotb checks for the RV32I core.

The tests drive the core's native ready/valid ports instead of reaching into
RTL storage. Deterministic wait states exercise request stability, while the
retirement scoreboard compares the RTL stream with the independent Python ISA
model already used by this repository.
"""

from __future__ import annotations

import random
import sys
from dataclasses import dataclass
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from rv32i_model import RV32IModel  # noqa: E402


STATE_FETCH = 0
STATE_EXECUTE = 1
STATE_MEMORY = 2
STATE_TRAP = 3
PASS_SIGNATURE = 0x600D_600D
FAIL_SIGNATURE = 0xBAD0_0001
SIGNATURE_ADDRESS = 0x900


def load_words(path: Path) -> list[int]:
    return [int(line.split()[0], 16) for line in path.read_text().splitlines()]


@dataclass
class Request:
    address: int
    write: bool = False
    data: int = 0
    strobes: int = 0
    delay: int = 0


class MemoryAgent:
    """Serve instruction and data requests with reproducible wait states."""

    def __init__(self, dut, words: list[int], seed: int = 0x32_1C):
        self.dut = dut
        self.memory = bytearray(4096)
        for index, word in enumerate(words):
            self.memory[index * 4:index * 4 + 4] = word.to_bytes(4, "little")
        self.random = random.Random(seed)
        self.imem_request: Request | None = None
        self.dmem_request: Request | None = None
        self.imem_wait_cycles = 0
        self.dmem_wait_cycles = 0
        self.instruction_handshakes = 0
        self.data_handshakes = 0

    def read_word(self, address: int) -> int:
        if address < 0 or address + 4 > len(self.memory):
            return 0
        return int.from_bytes(self.memory[address:address + 4], "little")

    def _capture_imem(self) -> None:
        if self.imem_request is None and int(self.dut.imem_valid_o.value):
            self.imem_request = Request(
                address=int(self.dut.imem_addr_o.value),
                delay=self.random.randrange(0, 4),
            )

    def _capture_dmem(self) -> None:
        if self.dmem_request is None and int(self.dut.dmem_valid_o.value):
            self.dmem_request = Request(
                address=int(self.dut.dmem_addr_o.value),
                write=bool(self.dut.dmem_write_o.value),
                data=int(self.dut.dmem_wdata_o.value),
                strobes=int(self.dut.dmem_wstrb_o.value),
                delay=self.random.randrange(0, 4),
            )

    def _assert_stable(self) -> None:
        if self.imem_request is not None and int(self.dut.imem_valid_o.value):
            assert int(self.dut.imem_addr_o.value) == self.imem_request.address
        if self.dmem_request is not None and int(self.dut.dmem_valid_o.value):
            current = (
                int(self.dut.dmem_addr_o.value),
                bool(self.dut.dmem_write_o.value),
                int(self.dut.dmem_wdata_o.value),
                int(self.dut.dmem_wstrb_o.value),
            )
            expected = (
                self.dmem_request.address,
                self.dmem_request.write,
                self.dmem_request.data,
                self.dmem_request.strobes,
            )
            assert current == expected

    async def run(self) -> None:
        self.dut.imem_ready_i.value = 0
        self.dut.imem_rdata_i.value = 0
        self.dut.imem_error_i.value = 0
        self.dut.dmem_ready_i.value = 0
        self.dut.dmem_rdata_i.value = 0
        self.dut.dmem_error_i.value = 0

        while True:
            await FallingEdge(self.dut.clk_i)
            self.dut.imem_ready_i.value = 0
            self.dut.dmem_ready_i.value = 0
            self._capture_imem()
            self._capture_dmem()
            self._assert_stable()

            if self.imem_request is not None:
                request = self.imem_request
                if request.delay:
                    request.delay -= 1
                    self.imem_wait_cycles += 1
                else:
                    self.dut.imem_rdata_i.value = self.read_word(request.address)
                    self.dut.imem_error_i.value = int(
                        request.address & 3 or request.address + 4 > len(self.memory)
                    )
                    self.dut.imem_ready_i.value = 1

            if self.dmem_request is not None:
                request = self.dmem_request
                if request.delay:
                    request.delay -= 1
                    self.dmem_wait_cycles += 1
                else:
                    self.dut.dmem_rdata_i.value = self.read_word(request.address & ~3)
                    self.dut.dmem_error_i.value = int(
                        request.address + 4 > len(self.memory)
                    )
                    self.dut.dmem_ready_i.value = 1

            await RisingEdge(self.dut.clk_i)
            if self.imem_request is not None and int(self.dut.imem_ready_i.value):
                self.instruction_handshakes += 1
                self.imem_request = None
            if self.dmem_request is not None and int(self.dut.dmem_ready_i.value):
                request = self.dmem_request
                if request.write and not int(self.dut.dmem_error_i.value):
                    aligned = request.address & ~3
                    for lane in range(4):
                        if request.strobes & (1 << lane):
                            self.memory[aligned + lane] = (request.data >> (lane * 8)) & 0xFF
                self.data_handshakes += 1
                self.dmem_request = None


async def reset(dut) -> None:
    dut.rst_ni.value = 0
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    await RisingEdge(dut.clk_i)


def initialize_inputs(dut) -> None:
    dut.rst_ni.value = 0
    dut.imem_ready_i.value = 0
    dut.imem_rdata_i.value = 0
    dut.imem_error_i.value = 0
    dut.dmem_ready_i.value = 0
    dut.dmem_rdata_i.value = 0
    dut.dmem_error_i.value = 0


@cocotb.test()
async def directed_program_matches_reference_model(dut):
    """Run all instruction groups with wait states and compare retirements."""

    words = load_words(ROOT / "sim" / "programs" / "rv32i_directed.hex")
    model = RV32IModel()
    model.load_hex(ROOT / "sim" / "programs" / "rv32i_directed.hex")
    initialize_inputs(dut)
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    memory = MemoryAgent(dut, words)
    memory_task = cocotb.start_soon(memory.run())
    await reset(dut)

    state_transitions = set()
    previous_state = STATE_FETCH
    retirements = 0
    for _cycle in range(20_000):
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        state = int(dut.debug_state_o.value)
        state_transitions.add((previous_state, state))
        previous_state = state

        assert not int(dut.trap_valid_o.value), (
            f"unexpected trap cause={int(dut.trap_cause_o.value)} "
            f"pc=0x{int(dut.trap_pc_o.value):08x}"
        )

        if int(dut.retire_valid_o.value):
            assert int(dut.retire_pc_o.value) == model.pc
            assert int(dut.retire_instruction_o.value) == model._read(model.pc, 4)
            model.step()
            assert model.trap is None
            retirements += 1

        signature = memory.read_word(SIGNATURE_ADDRESS)
        assert signature != FAIL_SIGNATURE
        if signature == PASS_SIGNATURE:
            break
    else:
        raise AssertionError(f"timeout at pc=0x{int(dut.debug_pc_o.value):08x}")

    memory_task.cancel()
    assert retirements == model.retired >= 100
    assert memory.imem_wait_cycles > 0
    assert memory.dmem_wait_cycles > 0
    assert (STATE_FETCH, STATE_EXECUTE) in state_transitions
    assert (STATE_EXECUTE, STATE_MEMORY) in state_transitions
    assert (STATE_MEMORY, STATE_FETCH) in state_transitions


@cocotb.test()
async def illegal_instruction_trap_is_sticky(dut):
    """Check the externally visible illegal-instruction trap record."""

    initialize_inputs(dut)
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    memory = MemoryAgent(dut, [0xFFFF_FFFF], seed=7)
    memory_task = cocotb.start_soon(memory.run())
    await reset(dut)

    for _ in range(30):
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        if int(dut.trap_valid_o.value):
            break
    else:
        raise AssertionError("illegal instruction did not trap")

    assert int(dut.debug_state_o.value) == STATE_TRAP
    assert int(dut.trap_cause_o.value) == 2
    assert int(dut.trap_pc_o.value) == 0
    assert int(dut.trap_tval_o.value) == 0xFFFF_FFFF
    for _ in range(4):
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        assert int(dut.trap_valid_o.value)
        assert int(dut.debug_state_o.value) == STATE_TRAP

    memory_task.cancel()
