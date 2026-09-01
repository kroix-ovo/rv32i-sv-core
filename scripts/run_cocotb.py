"""Build and run the cocotb CPU regression with Verilator.

The runner keeps simulator details out of the tests and places every generated
artifact under ``sim/build/cocotb``. ``--waves`` enables Verilator FST tracing;
the resulting ``dump.fst`` is ready for GTKWave or another FST viewer.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

from cocotb_tools.runner import get_runner


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "sim" / "build" / "cocotb"
SOURCES = [
    ROOT / "rtl" / "rv32i_pkg.sv",
    ROOT / "rtl" / "rv32i_alu.sv",
    ROOT / "rtl" / "rv32i_imm_gen.sv",
    ROOT / "rtl" / "rv32i_regfile.sv",
    ROOT / "rtl" / "rv32i_decoder.sv",
    ROOT / "rtl" / "rv32i_core.sv",
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--waves", action="store_true", help="write dump.fst")
    parser.add_argument(
        "--testcase",
        action="append",
        help="run only the named cocotb test (repeatable)",
    )
    args = parser.parse_args()

    # Verilator diagnostics are locale-sensitive on some macOS installations.
    os.environ.setdefault("LANG", "C")
    os.environ.setdefault("LC_ALL", "C")

    runner = get_runner("verilator")
    build_args = [
        "-Wall",
        "-Wno-fatal",
        "--trace-structs",
        "-CFLAGS",
        "-std=c++17",
    ]
    if args.waves:
        build_args.append("--trace-fst")

    runner.build(
        sources=SOURCES,
        hdl_toplevel="rv32i_core",
        build_dir=BUILD,
        build_args=build_args,
        waves=args.waves,
        always=True,
    )
    runner.test(
        hdl_toplevel="rv32i_core",
        test_module="test_rv32i_core",
        test_dir=ROOT / "tb" / "cocotb",
        build_dir=BUILD,
        waves=args.waves,
        testcase=args.testcase,
        test_args=["--trace-file", str(BUILD / "dump.fst")] if args.waves else [],
        results_xml=BUILD / "results.xml",
    )

    if args.waves:
        print(f"Waveform: {BUILD / 'dump.fst'}")
        print(f"GTKWave save file: {ROOT / 'waves' / 'rv32i_core.gtkw'}")


if __name__ == "__main__":
    main()
