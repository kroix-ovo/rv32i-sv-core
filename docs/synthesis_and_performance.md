# Synthesis and performance report

This report records what the current RTL does in simulation and how the core
maps in open-source synthesis. It keeps three questions separate: functional
correctness, cycle cost under stated memory assumptions, and estimated
resources before FPGA placement and routing.

![RV32I OSS CAD Suite results](diagrams/generated/oss-cad-results.png)

## Toolchain and reproduction

The 2026-09-05 run used the macOS ARM64 OSS CAD Suite 2026-09-05 binary bundle
installed under the adjacent `oss-cad-suite-build-main` folder. The synthesis
driver reports Yosys 0.68+195; `read_slang` handles the SystemVerilog package,
imports, enums, and typed ports. Verilator 5.048 and cocotb 2.0.1 produced the
cycle measurements.

From the repository root:

```bash
make oss-cad-report PYTHON=.venv/bin/python
```

That target reruns the cocotb tests, writes transient performance JSON under
`sim/build/cocotb/`, synthesizes `rv32i_core` twice, and updates:

- `reports/oss-cad/summary.json` — compact combined result;
- `reports/oss-cad/generic-stat.json` — raw Yosys generic cell statistics;
- `reports/oss-cad/generic-synthesis.txt` — complete generic synthesis log;
- `reports/oss-cad/xc7-synthesis.txt` — complete Xilinx 7-series mapping log;
- `docs/diagrams/generated/oss-cad-results.svg` and `.png` — documentation
  graphic generated from the measured values.

Set `OSS_CAD_ROOT=/path/to/oss-cad-suite` when the suite is installed
elsewhere. The original `oss-cad-suite-build-main` checkout is the source used
to build the distribution; the extracted binary bundle supplies Yosys, ABC,
the Slang plugin, and the device libraries used here.

## Cycle measurements

Both measurements execute the same generated directed program. It exercises
the implemented RV32I instruction groups and stores `0x600d600d` at address
`0x900` only after its internal comparisons pass. Cycles are counted after
reset release until that pass signature is observed. CPI is total measured
cycles divided by 134 retired instructions; IPC is its reciprocal.

| Memory behavior | Cycles | Retired | CPI | IPC | Instruction waits | Data waits |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Both ports answer without an inserted wait | 282 | 134 | 2.104 | 0.475 | 0 | 0 |
| Seeded 0–3-cycle waits per transaction | 501 | 134 | 3.739 | 0.267 | 200 | 20 |

The zero-wait result is close to the controller's structural limit: ordinary
instructions need fetch and execute states, while 15 data transfers add a
memory state. Two extra instruction transfers can be visible while the test
observes the memory-written pass signature, so transaction count is not used
as the retired-instruction count.

Frequency alone does not change CPI. If an implementation closes timing at
frequency `f`, its workload rate is `instructions/second = f / CPI`. Applying
100 MHz only as a conversion point gives 47.5 MIPS for the zero-wait case and
26.7 MIPS for the measured wait-state case. These are derived throughput
values, not proof that the Arty A7 build closes at 100 MHz.

## Synthesis results

The generic pass runs `synth -top rv32i_core`. The architecture-specific pass
runs `synth_xilinx -family xc7 -top rv32i_core`, matching the Arty A7's Xilinx
7-series family at the technology-library level.

| Result | Count |
| --- | ---: |
| Generic synthesized cells | 8,307 |
| Generic sequential cells | 1,269 |
| Generic mux cells | 1,149 |
| Estimated Xilinx logic cells | 2,132 |
| Flip-flops (`FDCE` + `FDPE`) | 1,270 |
| LUT1 / LUT2 / LUT3 | 10 / 287 / 306 |
| LUT4 / LUT5 / LUT6 | 433 / 783 / 610 |
| `CARRY4` | 52 |
| `MUXF7` / `MUXF8` | 47 / 12 |

The LUT rows count mapper primitives, not physical slices, and should not be
added to the estimated logic-cell number as if they were the same unit. The
large sequential count includes the 32×32 register file implemented inside the
core. This report deliberately synthesizes the core boundary rather than
`rv32i_soc`, so the 4,096-word simulation memory does not dominate or obscure
the CPU estimate.

## What these numbers do not claim

- No place-and-route step was run for the XC7A100T.
- No maximum clock frequency, slack, dynamic power, or board-level result is
  claimed.
- Yosys estimates are useful for repeatable design comparison but are not a
  substitute for Vivado implementation reports on the target board.
- The directed workload is a functional coverage program, not CoreMark,
  Dhrystone, Embench, or an application benchmark.

The next FPGA evidence step is to run `scripts/vivado_build.tcl`, archive the
utilization and timing summaries, and compare the post-route result with this
open-source pre-route baseline.
