# Pipeline and Vivado progress report

Date: 2026-09-25. Target: Digilent Arty A7-100T,
`xc7a100tcsg324-1`. Tool: Vivado 2023.2 on Windows.

## Architecture

`rv32i_core.sv` implements in-order IF, ID, EX, MEM, and WB stages with
valid bits at the four stage boundaries. ID stalls on read-after-write
dependencies. A waiting data-memory request holds younger stages. Branches
resolve in EX; fetch pauses while a control instruction is unresolved.
Faults discard younger work and let older instructions retire before the
external trap record becomes sticky. This baseline has no forwarding, caches,
CSRs, interrupts, compressed instructions, or multiply/divide extension.

The SoC wrapper keeps the same ready/valid interface. Instruction reads use
one block-RAM port; data reads and byte-lane writes use the other. Both ports
are clocked. The resettable ready/error flags stay outside the RAM process so
Vivado can infer block RAM.

## Verification

| Check | Result |
| --- | --- |
| slang elaboration | 12 files, 0 errors, 0 warnings |
| Icarus ALU bench | 10 checks passed |
| Icarus directed program | Pass signature, 521 cycles |
| Icarus trap bench | 9 architectural trap checks passed |
| cocotb under Icarus | 3 tests passed: model scoreboard, sticky trap, hazards/branch/memory |
| Vivado xsim | ALU, directed program, and trap bench all passed |

The cocotb tests use a seeded memory transaction driver, a request monitor
that checks held valid/address/data, a retirement monitor, the independent
Python ISA model as a scoreboard, and coverage checks for overlapping stages,
register interlocks, and memory waits. These are UVM verification roles
implemented in cocotb. This is not a full SystemVerilog UVM testbench.

## Implementation

The checked-in `scripts/vivado_build.tcl` uses the 10.000 ns clock constraint
in `fpga/arty_a7_100t.xdc`. Final routed reports from the 2026-09-25 run:

| Measure | Result |
| --- | ---: |
| Setup WNS | +0.681 ns |
| Setup TNS | 0.000 ns |
| Hold WHS | +0.155 ns |
| Slice LUTs | 1,631 / 63,400 (2.57%) |
| Slice registers | 1,560 / 126,800 (1.23%) |
| RAMB36 tiles | 4 / 135 (2.96%) |

Vivado generated `build/vivado/rv32i_arty_a7.runs/impl_1/arty_a7_100t_top.bit`.
The bitstream is a local generated artifact; it is not source-controlled.
The board has not been programmed or observed, so the LED demo is still a
hardware check to do.

Implementation completed with 0 DRC errors and 26 DRC warnings. One warns
that CFGBVS and CONFIG_VOLTAGE are unset. Four advise on RAMB output
registers. Twenty REQP-1839 warnings concern asynchronous reset on signals
driving RAMB inputs; the core gates memory requests low during reset. The
remaining CHECK-3 warning reports the REQP warning count limit. These
warnings did not prevent routing or bitstream creation, but they should be
reviewed before treating the board result as final.

The current architecture PDF, static datapath diagrams, and interactive map
describe the pipeline. `docs/synthesis_and_performance.md` and its OSS CAD
logs remain labeled historical results for the earlier multicycle controller.
