# Vivado quick start

## Nexys A7-100T

Check the name printed on the PCB first. The connected board in the
2026-10-13 session is a Nexys A7-100T, not an Arty. Both use an `xc7a100t`,
so JTAG chip detection alone cannot select the correct board constraints.

```powershell
vivado -mode batch -source scripts/vivado_build.tcl -tclargs build/board/2026-10-13/nexys nexys
vivado -mode batch -source scripts/vivado_program.tcl -tclargs build/board/2026-10-13/nexys/rv32i_nexys_a7.runs/impl_1/nexys_a7_100t_top.bit build/board/2026-10-13/nexys_device_status.txt
```

The Nexys target uses `fpga/nexys_a7_100t_top.sv` and
`fpga/nexys_a7_100t.xdc`, with shared demo logic in `arty_a7_100t_top.sv`.
Clock E3, active-low CPU RESET C12, and LD0–LD3 H17/K15/J13/N14 follow
[Digilent's Nexys constraints](https://github.com/Digilent/digilent-xdc/blob/master/Nexys-A7-100T-Master.xdc).
LD0 should blink under software control, LD1 should stay off, LD2 reflects
the PC, and LD3 should blink independently of the CPU. LD4–LD15 are off.
Hold **CPU RESET**, not the configuration/PROG button, to reset all four
status LEDs. Release it to restart the demo.

### Nexys directed self-test

Generate the programs, then select `selftest` as the third build argument:

```powershell
python sim/build_programs.py
vivado -mode batch -source scripts/vivado_sim.tcl -tclargs tb_board_selftest
vivado -mode batch -source scripts/vivado_build.tcl -tclargs build/board/2026-10-13/selftest nexys selftest
vivado -mode batch -source scripts/vivado_program.tcl -tclargs build/board/2026-10-13/selftest/rv32i_nexys_a7.runs/impl_1/nexys_a7_selftest_top.bit build/board/2026-10-13/selftest_device_status.txt
```

This runs the directed test with its result written to the GPIO register:
`0x600d600d` for pass, `0xbad00001` for a failed comparison.
LD0 is steady on for pass; LD1 is on for a failed comparison or CPU trap;
LD2 is on once pass, fail, or trap is reported; LD3 remains the independent
heartbeat. LD4–LD15 stay off. CPU RESET clears the status and reruns the test.

The expected passing pattern is LD0 on, LD1 off, LD2 on, LD3 blinking.
The simulation gate also checks an intentionally corrupted arithmetic
instruction and an EBREAK image, ensuring both show failure, and repeats
all three paths through five resets. Those injected failures are simulation
evidence; the normal board image tests the successful directed sequence.

## Arty A7-100T

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
The red RESET button on C2 is active-low. Holding it should turn all four
discrete LEDs off; releasing it restarts the demo after reset synchronization.
Physical observations and programming evidence are tracked in
[the 2026-10-13 board-test record](board_test_2026-10-13.md).

To preserve prior builds, pass a separate output directory:

```powershell
vivado -mode batch -source scripts/vivado_build.tcl -tclargs build/board/2026-10-13/demo
```

Program the connected FPGA's volatile configuration and save its status:

```powershell
vivado -mode batch -source scripts/vivado_program.tcl -tclargs build/board/2026-10-13/demo/rv32i_arty_a7.runs/impl_1/arty_a7_100t_top.bit build/board/2026-10-13/device_status.txt
```

The programming script requires exactly one target and one `xc7a100t` device.
It does not program the board's configuration flash. Successful configuration
still requires LED and reset observations to establish the physical smoke test.

## Behavioral simulation

The supplied Tcl script accepts one testbench name:

```powershell
vivado -mode batch -source scripts/vivado_sim.tcl -tclargs tb_core_directed
```

Valid names are `tb_alu`, `tb_core_directed`, `tb_core_traps`, and
`tb_board_reset`. The board-reset bench checks polarity, synchronized release,
software GPIO startup, and restart; it remains a simulation test.

For a manual xsim project, set the simulation top to one testbench at a time. Keep `rtl/rv32i_pkg.sv` first in compile order. The concurrent assertion file is optional and is not needed by the three basic tests.

## What to inspect after synthesis

Open the synthesized schematic and find `u_soc/u_core`. Confirm that the pipeline valid registers and the 32-word register file are present. Check the memory report to see how Vivado mapped the shared array. The exact BRAM result can vary with Vivado release and memory settings.

Read `reports/post_route_timing.rpt` rather than assuming a successful bitstream meets timing. A nonnegative worst negative slack means the 100 MHz constraint was met in that run.

## Common problems

`Package rv32i_pkg not found` means the package compiled after a module that imports it. Move the package to the start of the source order.

`Cannot open fpga_demo.hex` means the hex file was not added as a memory initialization source or the program generator was not run.

An always-lit trap LED usually means instruction memory was empty, the reset PC was changed, or the memory file path did not resolve. Probe `trap_cause_o`, `trap_pc_o`, and `trap_tval_o` in an Integrated Logic Analyzer if simulation does not reproduce it.
