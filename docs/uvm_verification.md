# Native SystemVerilog UVM verification

`tb/uvm/` contains a UVM 1.2 environment for `rv32i_core`. It runs with the
precompiled UVM library in Vivado 2023.2 XSim. The DUT is the core, not the
`rv32i_soc` GPIO wrapper. The existing directed SV and cocotb regressions remain
separate checks.

## Run

From the repository root in Windows PowerShell:

```powershell
python sim/build_programs.py
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_uvm.ps1 -Seed 1325
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_uvm.ps1 -Seed 99
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_tests.ps1 -Iverilog C:\iverilog\bin\iverilog.exe -Vvp C:\iverilog\bin\vvp.exe
$env:PATH='C:\iverilog\bin;'+$env:PATH
.\.venv\Scripts\python.exe scripts\run_cocotb.py --simulator icarus
```

`make test-uvm PYTHON=python` invokes the same script after rebuilding program
images when GNU Make is available. `-VivadoBin` selects another Vivado `bin`
directory. `-Seed` is the decimal root seed for the bounded random programs
and memory responses. The script writes it to `build/uvm/seed.txt`; rerun with
the same seed to reproduce a failure. Each random scenario prints its starting
generator state, and each scenario prints its instruction and data response
seeds in hexadecimal.

The script compiles RTL, interface, package, and top in explicit order with
`xvlog -sv -L uvm`, elaborates `tb_core_uvm` with `xelab -L uvm`, and runs XSim
for at most 1 ms. A pass requires the completion marker and zero UVM errors
and fatals. Logs are `build/uvm/compile.txt`, `elaborate.txt`, and `run.txt`;
XSim covergroup data is under `build/uvm/coverage/xsim.covdb/rv32i_uvm/`.

## Checks

- Each responder agent has a typed `rv32i_response_sequencer`. Its
  `rv32i_response_sequence` supplies one response item per core request, with
  a seeded zero-to-three-cycle wait or a fixed wait and an optional targeted
  fault. These response items are distinct from monitor events. The drivers
  capture requests, fetch items through `seq_item_port`, and complete them
  only on handshake. On reset they lower ready, cancel outstanding items,
  and discard the prior scenario's response sequences.
- `rv32i_suite_vseq` runs on a virtual sequencer holding both memory
  sequencers, the core interface, shared memory, and scoreboard. It owns
  directed, trap, injected-fault, reset, hazard, and random scenarios. Each
  scenario asserts reset, drains the drivers, stops old sequences, loads its
  program, resets the reference model, starts fresh response sequences, and
  releases reset. An epoch check rejects an item from an earlier scenario.
- Instruction and data responder agents share a byte-addressed memory image.
  Each inserts zero to three seeded wait cycles and can return an injected
  instruction or data access fault. Monitors check request stability until
  handshake, fetch alignment, store strobes, and non-overlapping ports.
- A separate SystemVerilog architectural model interprets retired RV32I
  instructions and keeps its own registers and memory. The scoreboard compares
  every retirement PC/instruction, each successful data transfer's address,
  direction, strobes and selected store bytes or load word, final signatures,
  and complete trap records. It rejects retirement after a sticky trap.
- Directed cases cover the full program, branch redirection and dependencies,
  nine architectural traps, three additional injected bus faults, reset while
  an instruction response item is pending, and eight bounded random legal
  programs. The reset case requires the driver's canceled-item count to rise
  and then verifies a clean restart.
- Covergroups and explicit pass/fail counters cover ten RV32I opcode groups,
  five load variants, three store widths, branch taken and untaken, all nine
  trap causes, and immediate and delayed responses on each port. The suite
  also requires an observed RAW stall, a retired load-use dependency, and a
  memory wait. Missing required bins produce UVM errors.

The pipeline stops instruction fetch while a load is in flight. Thus the
adjacent load-use case is handled by serialization; it does **not** create a
distinct load-use ID stall. The coverage report shows that stall count as zero
instead of claiming it occurred. The load result and dependent instruction are
still checked by the model and stored-memory comparison. The internal
`raw_stall` and `load_use_stall` taps are coverage observations only; correctness
comparisons use the core's public ports.

## Verification record

On 2026-09-29, Vivado Simulator 2023.2 (build 4029153) completed the
sequence-based suite with seeds `1325` and `99`; both had zero UVM warnings,
errors, and fatals. The directed program retired 134 instructions and wrote
`0x600d600d`. Both seeds covered all required opcode, load, store, wait-state,
branch, dependency, and trap bins. For seed `1325`, coverage reported 36
untaken and 15 taken branches, 268 adjacent RAW and 9 adjacent load-use
dependencies, 392 observed RAW stall cycles, and 109 memory wait cycles. For
seed `99`, the corresponding stall counts were 404 and 115. The Icarus SV
suite passed 10 ALU checks, the directed program, and 9 traps; cocotb 2.0.1
on Icarus passed all 3 core tests. These are simulation results; they do not
establish physical FPGA behavior.
