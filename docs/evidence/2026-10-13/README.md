# Nexys A7-100T board evidence — 2026-10-13

The [test record](../../board_test_2026-10-13.md) is the readable account of
the session, including the user's physical observations and coverage limits.

| Test | Evidence | Result |
| --- | --- | --- |
| Nexys software blink, heartbeat, reset/restart | User observation recorded in the test record | PASS |
| Nexys directed RV32I program | Exact pass-signature LED indication, user observed | PASS |
| Directed-test reset repeatability | User confirmed all five retries | 5/5 PASS |
| Original Arty image on this Nexys | Wrong reset/LED pin mapping; retained for diagnosis | Invalid board test |
| Self-test injected comparison failure / EBREAK | Vivado xsim, five reset/retests | Simulation PASS only |

Raw evidence keeps its original repository-relative path below `raw/`:

- [JTAG discovery](raw/build/board/2026-10-13/probe.log)
- [Nexys demo programming](raw/build/board/2026-10-13/nexys_program.log)
- [Nexys demo configuration status](raw/build/board/2026-10-13/nexys_device_status.txt)
- [Directed-test programming](raw/build/board/2026-10-13/selftest_program.log)
- [Directed-test configuration status](raw/build/board/2026-10-13/selftest_device_status.txt)
- [Directed-test simulation](raw/build/board/2026-10-13/selftest_sim.log)
- [Directed-test routed timing](raw/build/board/2026-10-13/selftest/reports/post_route_timing.rpt)
- [Directed-test utilization](raw/build/board/2026-10-13/selftest/reports/post_route_utilization.rpt)
- [Directed-test DRC](raw/build/board/2026-10-13/selftest/rv32i_nexys_a7.runs/impl_1/nexys_a7_selftest_top_drc_routed.rpt)

[manifest.json](manifest.json) records every raw file's SHA-256 and size.
[tested_bitstreams.zip](tested_bitstreams.zip) preserves all three images:
the original wrong-target Arty image, the successful Nexys blinking demo,
and the successful Nexys directed self-test. Archive members retain their
original build paths; their hashes match the original bitstream receipts.
For this Nexys board, use the Nexys images, not the diagnostic Arty image.

The raw logs include local tool/source paths and the JTAG device serial.
Physical pass results come from the user's responses in this session;
there is no photograph, video, UART log, or JTAG CPU trace. Vivado timing,
utilization, and power reports are implementation estimates, not physical
performance or power measurements. The recorded DRC warnings are retained.
