# Verification plan

The tests are layered so a failure can be narrowed down before opening a large waveform.

## Source and elaboration checks

`scripts/lint_sv.py` gives every RTL, FPGA, assertion, and testbench file to the slang SystemVerilog front end. It checks package use, types, port connections, procedural assignments, and elaboration.

```powershell
py -m venv .venv
.\.venv\Scripts\pip install -r requirements-dev.txt
.\.venv\Scripts\python scripts\lint_sv.py
```

The combinational case statements all have defensive defaults so an unknown or reserved input does not leave an output unassigned.

## Unit and instruction tests

`tb/tb_alu.sv` checks all ten ALU operations, including signed and unsigned comparison and both kinds of right shift.

`sim/build_programs.py` creates a 147-word program without an external assembler. The program executes all RV32I instruction groups and checks results in software. It covers upper immediates, every ALU operation, signed and unsigned loads, store byte lanes, every branch condition, jumps, and `FENCE`.

A passing run stores `0x600d600d` at address `0x900`. A failed comparison stores `0xbad00001`.

`tb/tb_core_traps.sv` checks illegal instructions, `ECALL`, `EBREAK`, misaligned jump/load/store addresses, and instruction/load/store access faults. It checks cause, faulting PC, tval, and sticky trap behavior.

## cocotb and Verilator integration

`tb/cocotb/test_rv32i_core.py` drives the synthesizable core through its native
instruction and data ready/valid ports. A seeded memory agent inserts zero to
three wait cycles, checks every held request remains stable, and services
little-endian writes using the RTL byte strobes.

The directed cocotb test compares every retirement PC and instruction against
`python/rv32i_model.py`. A second test independently checks the illegal-
instruction cause, PC, tval, state, and sticky behavior. Run:

```bash
make test-cocotb PYTHON=.venv/bin/python
make test-cocotb-waves PYTHON=.venv/bin/python
```

The waveform run writes `sim/build/cocotb/dump.fst`. Use
`waves/rv32i_core.gtkw` or `scripts/open_wave.sh` to inspect the controller,
retirement stream, memory handshakes, and traps. GTKWave supports diagnosis; it
does not replace the self-checking scoreboards.

## Protocol assertions

`tb/rv32i_core_assertions.sv` contains concurrent assertions for stable requests, aligned instruction fetches, non-overlapping instruction and data requests, valid store strobes, and sticky traps. The file binds the monitor to every core instance, and the Vivado simulation script includes it automatically.

## Independent ISA model

`python/rv32i_model.py` executes the generated program without using the RTL decoder or datapath. Matching the pass signature catches mistakes in the generator and gives a second description of instruction behavior.

## Broader conformance work

Before treating the core as production-ready, add the official RISC-V Architectural Test Framework and a RISC-V Formal Interface wrapper. Random instruction generation should compare every retired instruction against a trusted model such as Spike. FPGA synthesis and timing are required separately because simulation does not measure clock closure or BRAM inference.

## Passing criteria

| Check | Pass condition |
| --- | --- |
| Slang | Zero errors |
| ALU test | Ten checks and normal `$finish` |
| Directed program | Signature is `0x600d600d`; no trap |
| Trap test | Nine expected trap records |
| Verilator lint | Successful elaboration with reviewed diagnostics |
| cocotb directed test | Pass signature, no trap, matching retirement stream, observed wait states |
| cocotb trap test | Illegal-instruction record is correct and remains sticky |
| Vivado synthesis | No critical warnings about inferred latches, multiple drivers, or unconstrained ports |
| Vivado timing | Worst negative slack is nonnegative for the 10 ns board clock |
| FPGA demo | Heartbeat LED changes, software LED blinks, trap LED stays off |
