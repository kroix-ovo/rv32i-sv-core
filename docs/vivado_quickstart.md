# Vivado quick start

These instructions target the Digilent Arty A7-100T, part `xc7a100tcsg324-1`. You can still simulate `rv32i_core` without that board.

The tested setup used Vivado 2023.2 on Windows. Vivado is installed here at
`C:\Xilinx\Vivado\2023.2\bin\vivado.bat`; it is not on `PATH`. You need
the Arty A7-100T board and a USB data cable only for the final programming
step. Simulation, synthesis, implementation, and bitstream generation run
without the board connected.

The design inputs are `rtl/rv32i_pkg.sv`, `rv32i_alu.sv`,
`rv32i_imm_gen.sv`, `rv32i_regfile.sv`, `rv32i_decoder.sv`,
`rv32i_core.sv`, and `rv32i_soc.sv`; `fpga/arty_a7_100t_top.sv`;
`fpga/arty_a7_100t.xdc`; and `sim/programs/fpga_demo.hex`.
The hex image comes from `sim/build_programs.py`. Simulation also uses
`tb/tb_alu.sv`, `tb/tb_core_directed.sv`, `tb/tb_core_traps.sv`,
`tb/rv32i_core_assertions.sv`, and `sim/programs/rv32i_directed.hex`.

## Batch build

Open a shell where the Vivado command is available, change to the repository root, and run:

```powershell
python sim/build_programs.py
vivado -mode batch -source scripts/vivado_build.tcl
```

The script creates a project under `build/vivado`, synthesizes, implements, writes a bitstream, and saves reports under `reports`. Generated Vivado files are ignored by Git.
On this Windows installation, replace `vivado` with
`& 'C:\Xilinx\Vivado\2023.2\bin\vivado.bat'` in PowerShell.
The build script exits with an error if the routed 10 ns setup constraint
fails, even when Vivado writes a bitstream.

## GUI project

1. Create an RTL project and choose `xc7a100tcsg324-1`, or select the Arty A7-100 board if its board files are installed.
2. Add the SystemVerilog sources in this order: package, ALU, immediate generator, register file, decoder, core, SoC, and FPGA top.
3. Add `sim/programs/fpga_demo.hex` as a Memory Initialization File.
4. Add `fpga/arty_a7_100t.xdc` as a constraint file.
5. Set `arty_a7_100t_top` as the synthesis top.
6. Run synthesis. Check messages before continuing to implementation.
7. Run implementation and open the timing summary. The requested clock period is 10 ns.
8. Generate the bitstream and program the device.

Press the Arty reset button if the demo does not start immediately. LED 0 should blink. LED 1 should remain off. LED 3 gives a slower hardware heartbeat even if software traps.
This LED behavior is a simulation-based expectation; it has not yet been
observed on the physical board.

## Behavioral simulation

The supplied Tcl script accepts one testbench name:

```powershell
vivado -mode batch -source scripts/vivado_sim.tcl -tclargs tb_core_directed
```

Valid names are `tb_alu`, `tb_core_directed`, and `tb_core_traps`.

For a manual xsim project, set the simulation top to one testbench at a time. Keep `rtl/rv32i_pkg.sv` first in compile order. The concurrent assertion file is optional and is not needed by the three basic tests.

## What to inspect after synthesis

Open the synthesized schematic and find `u_soc/u_core`. Confirm that the pipeline valid registers and the 32-word register file are present. Check the memory report to see how Vivado mapped the shared array. The exact BRAM result can vary with Vivado release and memory settings.

Read `reports/post_route_timing.rpt` rather than assuming a successful bitstream meets timing. A nonnegative worst negative slack means the 100 MHz constraint was met in that run.

## Common problems

`Package rv32i_pkg not found` means the package compiled after a module that imports it. Move the package to the start of the source order.

`Cannot open fpga_demo.hex` means the hex file was not added as a memory initialization source or the program generator was not run.

An always-lit trap LED usually means instruction memory was empty, the reset PC was changed, or the memory file path did not resolve. Probe `trap_cause_o`, `trap_pc_o`, and `trap_tval_o` in an Integrated Logic Analyzer if simulation does not reproduce it.
