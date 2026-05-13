# RV32I SystemVerilog CPU Core

## Project Overview

This project is a synthesizable RV32I RISC-V CPU core designed in SystemVerilog. The goal is to build a small but real processor from the RTL level, verify it through simulation and assertions, and eventually deploy it on the Arty A7-100T FPGA.

The project is intended to strengthen my skills in RTL design, computer architecture, SystemVerilog verification, waveform debugging, FPGA implementation, and technical documentation.

## Project Goals

By the end of this project, the CPU should include:

- Program counter
- Instruction memory
- Instruction decoder
- Control unit
- Register file
- Immediate generator
- ALU
- Branch and jump logic
- Data memory
- Writeback path
- SystemVerilog testbenches
- Assertions for important CPU properties
- FPGA implementation on the Arty A7-100T
- Vivado synthesis and timing reports

## Architecture

The first version of this CPU will be a single-cycle RV32I subset processor.

Basic datapath:

```text
PC
→ Instruction Memory
→ Instruction Decode / Control
→ Register File
→ ALU / Branch Logic
→ Data Memory
→ Writeback
→ Register File