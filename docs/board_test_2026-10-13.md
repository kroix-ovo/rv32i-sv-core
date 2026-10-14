# Nexys A7-100T board test — 2026-10-13

Published raw logs, reports, hash receipts, and tested bitstreams are in
[the evidence bundle](evidence/2026-10-13/README.md). Paths below beginning
with `build/board/2026-10-13/` are preserved under its `raw/` directory;
the three bitstreams are preserved in `tested_bitstreams.zip`.

## Scope and provenance

The user identified the connected board as **Nexys A7-100T**. This session
tests the five-stage RV32I core with the software LED demo and directed
instruction program on that physical FPGA. These are smoke and directed
tests, not an exhaustive instruction or trap regression. No throughput,
power, or clock-frequency measurement is
claimed from LED observations.

The checkout started at commit `d0484969aedc33d1086fd10c4dce8aa7d4140a3e`
with unrelated changes in `docs/pipeline.md` and an untracked `Claude outputs/`
directory. Those changes were preserved. The board image includes the
reset-polarity correction described below; it is not the unmodified commit.

Vivado 2023.2 detected target
`localhost:3121/xilinx_tcf/Digilent/210292ABF1AAA`, device `xc7a100t_0`,
part `xc7a100t`. The build targets `xc7a100tcsg324-1` using the repository's
Arty A7-100T constraints. JTAG identifies the FPGA family/device; it does not
independently identify the board revision or package.

## Reset correction and simulation

The original wrapper asserted reset when C2 was high. The Arty red reset
button instead pulls C2 low when pressed and leaves it high at rest, as
documented in the [Digilent Arty A7 reference manual](https://media.digikey.com/pdf/Data%20Sheets/Digilent%20PDFs/Arty_A7_RM_Web.pdf).
The wrapper now asserts reset on a falling edge and releases it after two
clock edges with C2 high.

Vivado xsim passed `tb_board_reset`: initial active-low reset, release after
two edges, the first CPU-driven GPIO write without a trap, asynchronous
button reset, and software restart. This is simulation evidence only.
Log: `build/board/2026-10-13/reset_sim/xsim.log`.

## Initial Arty image: wrong board target

The repository initially supplied only an Arty target. This image was
programmed before the PCB model was confirmed. The user subsequently
confirmed a Nexys A7-100T: Arty reset C2 is Nexys microSD data, and the Arty
LED pins do not map to the Nexys user LEDs. The first image and its retry
are not valid Nexys CPU tests. The shared clock pin is E3 on both boards.
Pin assignments were checked against
[Digilent's Nexys A7-100T master constraints](https://github.com/Digilent/digilent-xdc/blob/master/Nexys-A7-100T-Master.xdc).

Fresh build directory: `build/board/2026-10-13/demo/`.
Source SHA-256 hashes: `build/board/2026-10-13/source_hashes.json`.
JTAG discovery log: `build/board/2026-10-13/probe.log`.

Fresh implementation completed successfully. These figures are Vivado
implementation reports, not physical frequency or resource measurements:

| Measure | Result |
| --- | ---: |
| Clock constraint | 10.000 ns / 100 MHz |
| Setup WNS / TNS | +1.189 ns / 0.000 ns |
| Hold WHS / THS | +0.148 ns / 0.000 ns |
| Slice LUTs | 1,633 |
| Slice registers | 1,560 |
| RAMB36 blocks | 4 |
| Bitstream DRC | 0 errors, 26 warnings |

Reports: `build/board/2026-10-13/demo/reports/post_route_timing.rpt`
and `post_route_utilization.rpt`. The 26 DRC warnings include the existing
configuration-voltage and RAMB output-register/asynchronous-control warnings.

The fresh bitstream SHA-256 is
`B266C33B18FC3F87B5F37F8F2154A55B6E03F959263649007E9BE1EEDF00C43B`.
Vivado programmed `xc7a100t_0` over JTAG on 2026-10-13 at approximately
20:40 America/New_York and reported `End of startup status: HIGH`.
The command completed with exit code 0. Configuration DONE and EOS were 1;
CRC and IDCODE error flags were 0. Only volatile FPGA configuration was
programmed; configuration flash was not written.

Programming log: `build/board/2026-10-13/program.log`.
Device status receipt: `build/board/2026-10-13/device_status.txt`.
Vivado confirmed that this image contains no supported debug cores, so
internal CPU retirement, trap cause, and signature cannot be read through
the current JTAG interface.

## Initial physical observations with wrong board target

| Check | Expected behavior | Recorded observation |
| --- | --- | --- |
| LED 0 / LD4 | Repeated software-controlled blink | User reports nothing blinking; check did not pass |
| LED 1 / LD5 | Off; a lit LED indicates a CPU trap | Pending user observation |
| LED 2 / LD6 | Reflects PC bit 4; no pass/fail meaning | Pending user observation |
| LED 3 / LD7 | Hardware heartbeat, independent of CPU progress | User reports nothing blinking; check did not pass |
| Red RESET button held | All four discrete LEDs off | Pending user observation |
| Red RESET button released | Software blink and heartbeat restart | Pending user observation |

The user reported: "Maybe retry or the reset button may not be working
because nothing is blinking." The physical smoke test has not passed.
Reset failure is a hypothesis, not an established diagnosis. The exact PCB
model is being checked because JTAG chip identification alone does not
establish that the Arty clock/reset/LED pin assignments match the board.

The same bitstream was programmed again at approximately 20:44
America/New_York. Vivado again returned exit code 0 and startup status HIGH.
Retry evidence: `build/board/2026-10-13/retry_program.log` and
`retry_device_status.txt`. LED behavior after the retry has not yet been
reported. Successful reconfiguration does not resolve the physical failure.

## Correct Nexys target

The Nexys adapter reuses the same CPU, SoC, LED demo image, active-low reset
synchronizer, and heartbeat. Its own constraints connect CLK100MHZ to E3,
CPU_RESETN to C12, and LED[0:3] to H17/K15/J13/N14. LED[15:4] are held low.
Vivado xsim passed the updated board-reset test, including equality of the
Nexys status LEDs with the shared demo logic and inactive unused LEDs.
Simulation log: `build/board/2026-10-13/nexys_reset_gate.log`.

Build directory: `build/board/2026-10-13/nexys/`.
Source hashes: `build/board/2026-10-13/nexys_source_hashes.json`.
Nexys implementation completed successfully and met the 10.000 ns clock
constraint. Routed setup WNS/TNS: +0.170 ns / 0.000 ns; hold WHS/THS:
+0.062 ns / 0.000 ns. Utilization: 1,633 LUTs, 1,560 registers, four RAMB36
blocks. Bitstream generation reported 0 errors and 26 DRC warnings, of the
same categories described for the Arty implementation. These are tool
reports, not measurements of physical frequency or power.

Reports: `build/board/2026-10-13/nexys/reports/post_route_timing.rpt`
and `post_route_utilization.rpt`.
Bitstream: `build/board/2026-10-13/nexys/rv32i_nexys_a7.runs/impl_1/nexys_a7_100t_top.bit`.
SHA-256: `F922E9413E036238B53314D24926B12A0D57E7B2506AB459BC754E0C7F149808`.

Programming completed at approximately 20:49 America/New_York with exit
code 0 and startup status HIGH. Device DONE and EOS flags were 1; CRC and
IDCODE error flags were 0. Evidence:
`build/board/2026-10-13/nexys_program.log` and `nexys_device_status.txt`.
Only volatile FPGA configuration was written. The subsequent user
observations establish a passing physical LED/reset smoke test.

| Physical Nexys check | Expected | Observation |
| --- | --- | --- |
| LD0 | Software-controlled blink | User confirmed blinking — PASS |
| LD1 | Off, no trap indication | User confirmed the requested checks — PASS |
| LD2 | PC bit 4, no pass/fail meaning | User reported solid on; informational |
| LD3 | Independent hardware heartbeat | User confirmed blinking — PASS |
| LD4–LD15 | Off | Pending |
| CPU RESET held | LD0–LD3 off | User confirmed reset check — PASS |
| CPU RESET released | Software and heartbeat restart | User confirmed restart — PASS |

The user reported: "Yes blinking and reset both work also ld2 is solid on."
The reply answered the requested 20-second blink observation and two-second
CPU RESET hold/release check. Results are human-observed board evidence,
not an automated capture. LD4–LD15 were not separately confirmed.

**Result: physical software-GPIO, hardware-heartbeat, and CPU reset/restart
smoke test PASS on the Nexys A7-100T.** The software blink demonstrates CPU
execution through instruction memory, arithmetic, branch looping, and a
memory-mapped GPIO store. LD2 reflects PC bit 4 and may appear steady; it is
not a trap or failure flag. Its actual PC value was not captured.

This does not establish a full on-board RV32I regression. No retirement
trace, directed-program signature, trap-scenario coverage, instruction
throughput, clock frequency, or power was measured on the physical board.
Those claims remain outside this smoke test.

## Directed RV32I self-test

The directed image runs the existing test program with result stores routed
to GPIO instead of RAM address `0x900`. The ordinary simulation image and
blinking demo image remain unchanged. Expected values and control-flow
checks remain the same; the encoder resolves branches after adding the GPIO
result stores.

Coverage includes LUI/AUIPC, immediate arithmetic/logic/shifts, all ten
register ALU operations, LB/LBU/LH/LHU/LW, SB/SH/SW, signed load extension,
byte-lane accesses, BEQ/BNE/BLT/BGE/BLTU/BGEU, a not-taken BEQ, JAL and JALR
link values, and FENCE execution. This is a fixed directed program, not an
exhaustive architectural compliance suite or randomized on-board regression.

The self-test LED decoder recognizes the full GPIO signature:

| LED | Meaning |
| --- | --- |
| LD0 | Exact pass signature `0x600d600d` and no trap |
| LD1 | Exact fail signature `0xbad00001`, or CPU trap |
| LD2 | Pass, fail, or trap has been reported |
| LD3 | Independent hardware heartbeat |

Vivado xsim passed `tb_board_selftest`: exact pass signature, an intentionally
corrupted first ADDI producing the exact fail signature, EBREAK producing
a trap/failure indication, cleared status during reset, and five complete
reset/retest cycles for all three images. These are simulation observations.
Log: `build/board/2026-10-13/selftest_sim.log`.

Build directory: `build/board/2026-10-13/selftest/`.
Source hashes: `build/board/2026-10-13/selftest_source_hashes.json`.
Implementation completed and met the 10.000 ns clock constraint:
setup WNS/TNS +0.292 ns / 0.000 ns, hold WHS/THS +0.072 ns / 0.000 ns.
Utilization: 1,579 LUTs, 1,563 registers, four RAMB36 blocks. Bitstream
generation: 0 errors, 26 DRC warnings of the existing categories. These are
Vivado reports, not physical throughput/frequency/power measurements.
Reports are under `build/board/2026-10-13/selftest/reports/`.

Bitstream: `build/board/2026-10-13/selftest/rv32i_nexys_a7.runs/impl_1/nexys_a7_selftest_top.bit`.
SHA-256: `FB712CA90404EA1BC4F6D062FF28901AA51573CDD2F2F4E761F57C6937A6338D`.
Volatile JTAG programming completed at approximately 20:57 America/New_York,
exit code 0, startup status HIGH. DONE and EOS flags were 1; CRC and IDCODE
error flags were 0. Evidence: `build/board/2026-10-13/selftest_program.log`
and `selftest_device_status.txt`.

The user confirmed: "Pass pattern returns all five times." This answers the
requested LD0/LD2 steady on, LD1 off, LD3 blinking check and five CPU RESET
trials, each with an approximately one-second hold before release.

| Physical directed-test check | Result |
| --- | --- |
| Exact pass-signature LED indication | PASS, user observed |
| Failure/trap LED off | PASS, user confirmed requested pattern |
| Independent heartbeat | PASS, user confirmed requested pattern |
| CPU RESET repeatability | PASS, pass pattern returned after all 5 releases |

**Result: directed RV32I program PASS on the physical Nexys A7-100T,
including 5/5 reset/retest trials.** The full-signature LED decoder indicates
that the program wrote `0x600d600d` to GPIO and no trap was active at the
time of observation. This is a human-observed signature indication, not a
JTAG/UART capture of the GPIO value or instruction retirement trace.

The normal directed program checks the instruction and memory behaviors
listed above. Injected comparison failure and EBREAK LED indications were
validated in simulation only. Physical trap scenarios, randomized memory
stress, timing counters, and power/clock-frequency measurements remain
untested. The directed-test image remains loaded in volatile configuration.
