# References and design influences

The ISA behavior comes from the RISC-V specification. Open cores were used to study repository organization and practical bus contracts. No source file from another CPU was copied into this repository.

## Primary specifications

- [RISC-V Instruction Set Manual, Volume I, unprivileged architecture](https://docs.riscv.org/reference/isa/v20250508/unpriv/rv32.html). The RV32I chapter defines the register model, instruction encodings, alignment rules, and instruction behavior.
- [RISC-V ISA Manual source repository](https://github.com/riscv/riscv-isa-manual). This is the maintained source for the specification and points to official releases.
- [AMD Vivado Synthesis Guide UG901](https://docs.amd.com/r/en-US/ug901-vivado-synthesis/Verilog-Functionality). The RAM coding sections informed the synchronous memory wrapper, byte write enables, and `$readmemh` use.
- [Digilent Arty A7-100 master XDC](https://github.com/Digilent/digilent-xdc/blob/master/Arty-A7-100-Master.xdc). The board clock, reset, and four discrete LED pin assignments come from this file.

## Open hardware examples

- [PicoRV32](https://github.com/YosysHQ/picorv32). Its documented native memory port is a clear example of holding valid and request signals until ready. PicoRV32 is a compact Verilog core with several bus wrappers.
- [Ibex](https://github.com/lowRISC/ibex). Ibex is a larger production SystemVerilog core. Its module separation, documentation, and verification material are useful examples even though this teaching core uses a much smaller architecture.
- [Ibex pipeline documentation](https://ibex-core.readthedocs.io/en/latest/03_reference/pipeline_details.html). Its clearly labeled implementation diagram informed the report's preference for source-grounded signal flow. This core remains multicycle rather than a copy of the Ibex pipeline.
- [Aegis-Stream](https://github.com/kroix-ovo/Aegis-Stream). Its RTL uses short module summaries, port-group labels, invariant comments beside logic, and simulator pragmas only when they are real tool directives. This repository adopts that comment structure while documenting a different CPU architecture.

## Verification and waveform tools

- [cocotb simulator support](https://docs.cocotb.org/en/stable/simulator_support.html). This documents Verilator support and FST waveform generation with `--trace-fst` and `--trace-structs`.
- [cocotb Python runner reference](https://docs.cocotb.org/en/stable/library_reference.html#python-runner). The checked-in runner uses this build/test interface and enables waves at both stages.
- [Verilator user guide](https://verilator.org/guide/latest/). Verilator provides SystemVerilog elaboration, lint diagnostics, and the compiled cocotb simulation harness.
- [GTKWave](https://gtkwave.sourceforge.net/). GTKWave loads the generated FST trace and checked-in signal-group save file.

## Architecture presentation

- [Archify](https://github.com/tt-a1i/archify). Archify 2.16.0 renders the checked-in typed JSON specification as the interactive architecture map. Its showcase validator is also used to check crossings, route clarity, label clearance, and desktop readability. The CPU topology, signal names, guided views, and explanatory cards remain project-authored and are derived from this repository's RTL.

## Next verification references

- [RISC-V Architectural Test Framework](https://github.com/riscv-non-isa/riscv-arch-test). Use this for standardized ISA test generation and signature comparison.
- [RISC-V Formal Interface](https://github.com/YosysHQ/riscv-formal). An RVFI wrapper would allow formal checks of every retired instruction.

The ISA and tool documentation can change. The links above were checked on 2026-09-01. The implemented target remains RV32I version 2.1, which is listed as ratified in the referenced specification release. The static SVGs and Archify input specification are original project work derived from the checked-in RTL and verified interfaces; the generated interactive viewer uses Archify under its MIT license. External reference diagrams are not embedded assets.
