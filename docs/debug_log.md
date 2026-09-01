# Build and verification log

This file records observed results. It is not a list of results the project is expected to have later.

## 2026-08-19

The initial repository contained a README, empty source folders, and empty documentation pages.

The architecture was set to a four-state multicycle core with separate ready/valid instruction and data ports. The design target is the ratified RV32I base ISA, without privileged CSRs or extensions.

The first generated directed program passed the Python reference model. During manual RTL review, the `LUI` path was found to use `rs1` as the ALU left operand even though U-type instructions do not have an `rs1` field. A dedicated zero-left-operand decoder control was added. This is the kind of error that a self-checking RTL simulation should catch immediately.

Final local checks in this shell:

- Program generation: pass, 147 words written
- Independent RV32I model: pass, 134 instructions retired before signature
- Pass signature: `0x600d600d`
- Icarus Verilog 12 ALU simulation: pass, 10 checks
- Icarus Verilog 12 directed-core simulation: pass, 431 clock cycles
- Icarus Verilog 12 trap simulation: pass, 9 trap records
- Slang 11.0 parse and elaboration: zero errors across 12 SystemVerilog files
- Slang warnings: zero

Icarus Verilog was not already installed. The package-manager entry did not support a per-user install. Its official installer was downloaded and its SHA-256 matched the package manifest. A silent install did not finish, so its two installer processes were stopped. The same verified package was then unpacked without system installation and used to run the three simulations above.

Vivado was not installed or visible on `PATH`, so xsim, synthesis, implementation, timing, and bitstream generation were not run here. The repository contains batch scripts for those checks. Run them before reporting an FPGA result.

## 2026-09-01

Added a Verilator 5.048 + cocotb 2.0.1 regression around the native core ports.
The first compiled harness failed because the local Apple Clang invocation did
not select C++14 or newer; the runner now explicitly requests C++17. With that
host fix, both cocotb tests passed in 5.11 us of simulated time and produced a
15 KiB FST containing 175 signals plus one alias.

The standard Homebrew `gtkwave` command is a deprecated Perl wrapper and failed
because `Switch.pm` is absent. The underlying GTKWave 3.3.107 app binary loaded
the FST and save file successfully in `--exit` validation mode. The checked-in
`scripts/open_wave.sh` uses the macOS app launcher directly and falls back to a
normal `gtkwave` command on other systems. This is a viewer-launch issue, not a
simulation or waveform-format failure.

Fresh results:

- Verilator RTL lint/elaboration: pass
- cocotb directed program with deterministic wait states: pass
- cocotb illegal-instruction sticky trap: pass
- FST trace: 5.11 us, successfully loaded by GTKWave
