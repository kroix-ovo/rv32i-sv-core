"""Cycle-accurate cocotb checks for the RV32I core.

The tests drive the core's native ready/valid ports. MemoryAgent acts as a
transaction driver and request monitor: it captures a request, waits a seeded
number of cycles, checks that the request stays stable, then returns a
response. The tests observe retire_valid_o as a retirement monitor and use
RV32IModel as an architectural scoreboard. Counters check that pipeline
overlap and stalls actually happened. These are basic UVM verification roles
implemented in cocotb, without a SystemVerilog UVM library.
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
from rv32i_encode import b_type, load, op, op_imm, store, EBREAK  # noqa: E402


STATE_FLOW = 0
STATE_INTERLOCK = 1
STATE_MEMORY_WAIT = 2
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
    """Serve requests and check their lifetime, like a driver plus monitor."""

    def __init__(self, dut, words: list[int], seed: int = 0x32_1C,
                 zero_wait_first_imem: int = 0):
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
        self.zero_wait_first_imem = zero_wait_first_imem
        self.instruction_requests = 0

    def read_word(self, address: int) -> int:
        if address < 0 or address + 4 > len(self.memory):
            return 0
        return int.from_bytes(self.memory[address:address + 4], "little")

    def _capture_imem(self) -> None:
        if self.imem_request is None and int(self.dut.imem_valid_o.value):
            delay = (0 if self.instruction_requests < self.zero_wait_first_imem
                     else self.random.randrange(0, 4))
            self.instruction_requests += 1
            self.imem_request = Request(
                address=int(self.dut.imem_addr_o.value),
                delay=delay,
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
        # After capture, valid must stay high and every request field must
        # keep its value until the agent returns ready. A changing address
        # could make a delayed response belong to the wrong instruction.
        if self.imem_request is not None:
            assert int(self.dut.imem_valid_o.value), "instruction request withdrawn before ready"
            assert int(self.dut.imem_addr_o.value) == self.imem_request.address
        if self.dmem_request is not None:
            assert int(self.dut.dmem_valid_o.value), "data request withdrawn before ready"
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
        assert not (int(self.dut.imem_valid_o.value) and
                    int(self.dut.dmem_valid_o.value))

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

    stage_overlap = 0
    dependency_cycles = 0
    memory_stall_cycles = 0
    retirements = 0
    for _cycle in range(20_000):
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        if sum(int(stage.value) for stage in
               (dut.if_valid_q, dut.id_valid_q, dut.ex_valid_q, dut.wb_valid_q)) >= 2:
            stage_overlap += 1
        dependency_cycles += int(dut.dependency.value) and int(dut.if_valid_q.value)
        memory_stall_cycles += int(dut.debug_state_o.value) == STATE_MEMORY_WAIT

        assert not int(dut.trap_valid_o.value), (
            f"unexpected trap cause={int(dut.trap_cause_o.value)} "
            f"pc=0x{int(dut.trap_pc_o.value):08x}"
        )

        # Retirement is the architectural observation point. The model
        # advances only when the hardware says one instruction has finished.
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
    assert stage_overlap > 0
    assert dependency_cycles > 0
    assert memory_stall_cycles > 0


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


@cocotb.test()
async def pipeline_hazards_branch_and_trap(dut):
    """Transaction driver, retire monitor, reference scoreboard, and coverage."""

    words = [
        op_imm(1, 0, 0x100, 0),    # base address
        op_imm(2, 0, 7, 0),
        op_imm(3, 0, 11, 0),
        op(4, 2, 3, 0),            # RAW: x4 = 18
        store(4, 1, 0, 2),
        load(5, 1, 0, 2),          # load-use interlock
        op_imm(6, 5, 1, 0),
        b_type(8, 6, 6, 0),        # taken, squash PC 32
        op_imm(7, 0, 99, 0),
        op_imm(7, 0, 42, 0),
        EBREAK,
    ]
    model = RV32IModel()
    for index, word in enumerate(words):
        model.memory[index * 4:index * 4 + 4] = word.to_bytes(4, "little")

    initialize_inputs(dut)
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    memory = MemoryAgent(dut, words, seed=0x515, zero_wait_first_imem=5)
    memory_task = cocotb.start_soon(memory.run())
    await reset(dut)

    retired = []
    overlap = raw_stalls = memory_stalls = max_occupied = 0
    for _ in range(500):
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        occupied = sum(int(stage.value) for stage in
                       (dut.if_valid_q, dut.id_valid_q, dut.ex_valid_q,
                        dut.wb_valid_q))
        overlap += occupied >= 2
        max_occupied = max(max_occupied, occupied)
        raw_stalls += bool(int(dut.if_valid_q.value) and int(dut.dependency.value))
        memory_stalls += int(dut.debug_state_o.value) == STATE_MEMORY_WAIT

        if int(dut.retire_valid_o.value):
            pc = int(dut.retire_pc_o.value)
            instruction = int(dut.retire_instruction_o.value)
            assert pc == model.pc
            assert instruction == model._read(model.pc, 4)
            model.step()
            assert model.trap is None
            retired.append(pc)

        if int(dut.trap_valid_o.value):
            break
    else:
        raise AssertionError("pipeline scenario timed out")

    assert retired == [0, 4, 8, 12, 16, 20, 24, 28, 36]
    model.step()
    assert model.trap is not None
    assert (int(dut.trap_cause_o.value), int(dut.trap_pc_o.value),
            int(dut.trap_tval_o.value)) == (
                model.trap.cause, model.trap.pc, model.trap.tval)
    assert model.regs[4:8] == [18, 18, 19, 42]
    assert memory.read_word(0x100) == 18
    assert overlap > 0 and max_occupied >= 3
    assert raw_stalls > 0 and memory_stalls > 0
    assert memory.imem_wait_cycles > 0 and memory.dmem_wait_cycles > 0
    memory_task.cancel()
