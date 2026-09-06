"""Generate reproducible OSS CAD Suite synthesis evidence for the RV32I core."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RTL = [
    "rtl/rv32i_pkg.sv",
    "rtl/rv32i_alu.sv",
    "rtl/rv32i_imm_gen.sv",
    "rtl/rv32i_regfile.sv",
    "rtl/rv32i_decoder.sv",
    "rtl/rv32i_core.sv",
]


def run_yosys(yosys: Path, commands: str, log_path: Path) -> str:
    result = subprocess.run(
        [str(yosys), "-Q", "-p", commands],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        env={**os.environ, "LANG": "C", "LC_ALL": "C"},
    )
    # Yosys/ABC prints cosmetic trailing spaces in command transcripts. Keep
    # checked-in evidence deterministic and friendly to `git diff --check`.
    clean_output = "\n".join(line.rstrip() for line in result.stdout.splitlines()) + "\n"
    log_path.write_text(clean_output)
    if result.returncode:
        raise SystemExit(f"Yosys failed; see {log_path.relative_to(ROOT)}")
    return clean_output


def metric(log: str, pattern: str) -> int:
    matches = re.findall(pattern, log, flags=re.MULTILINE)
    if not matches:
        raise ValueError(f"missing synthesis metric: {pattern}")
    return int(matches[-1])


def build_svg(data: dict[str, object]) -> str:
    xc7 = data["xc7_estimate"]
    perf = data["zero_wait_performance"]
    bars = [
        ("LUT1", xc7["lut1"]),
        ("LUT2", xc7["lut2"]),
        ("LUT3", xc7["lut3"]),
        ("LUT4", xc7["lut4"]),
        ("LUT5", xc7["lut5"]),
        ("LUT6", xc7["lut6"]),
    ]
    max_value = max(value for _, value in bars)
    bar_markup = []
    for index, (label, value) in enumerate(bars):
        y = 326 + index * 42
        width = 520 * value / max_value
        bar_markup.append(
            f'<text x="70" y="{y + 18}" class="barlabel">{label}</text>'
            f'<rect x="135" y="{y}" width="{width:.1f}" height="24" rx="5" class="bar"/>'
            f'<text x="{150 + width:.1f}" y="{y + 18}" class="barvalue">{value}</text>'
        )
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="650" viewBox="0 0 1200 650" role="img" aria-labelledby="title desc">
  <title id="title">RV32I OSS CAD Suite synthesis and performance snapshot</title>
  <desc id="desc">Verified Yosys XC7 resource estimates and zero-wait Verilator performance for the RV32I core.</desc>
  <style>
    .bg {{ fill:#08111f }} .card {{ fill:#111f33; stroke:#29415f; stroke-width:2 }}
    .title {{ fill:#f6f8fb; font:700 31px system-ui,sans-serif }}
    .sub {{ fill:#9fb3c8; font:16px system-ui,sans-serif }}
    .number {{ fill:#62d3ff; font:700 37px ui-monospace,monospace }}
    .label {{ fill:#d7e2ee; font:15px system-ui,sans-serif }}
    .heading {{ fill:#f6f8fb; font:700 20px system-ui,sans-serif }}
    .bar {{ fill:#2f9fd0 }} .barlabel,.barvalue {{ fill:#d7e2ee; font:14px ui-monospace,monospace }}
    .foot {{ fill:#8398ad; font:13px system-ui,sans-serif }}
  </style>
  <rect width="1200" height="650" class="bg"/>
  <text x="55" y="58" class="title">RV32I implementation snapshot</text>
  <text x="55" y="88" class="sub">OSS CAD Suite {data['suite_release']} · {data['yosys_version_short']} · target: Xilinx 7-series estimate</text>
  <g transform="translate(55 120)">
    <rect width="250" height="135" rx="14" class="card"/>
    <text x="24" y="34" class="label">Estimated logic cells</text>
    <text x="24" y="84" class="number">{xc7['estimated_lcs']:,}</text>
    <text x="24" y="113" class="foot">pre-place-and-route</text>
  </g>
  <g transform="translate(325 120)">
    <rect width="250" height="135" rx="14" class="card"/>
    <text x="24" y="34" class="label">Flip-flops</text>
    <text x="24" y="84" class="number">{xc7['flip_flops']:,}</text>
    <text x="24" y="113" class="foot">FDCE + FDPE</text>
  </g>
  <g transform="translate(595 120)">
    <rect width="250" height="135" rx="14" class="card"/>
    <text x="24" y="34" class="label">Zero-wait CPI</text>
    <text x="24" y="84" class="number">{perf['cpi']:.3f}</text>
    <text x="24" y="113" class="foot">{perf['retired_instructions']} instructions measured</text>
  </g>
  <g transform="translate(865 120)">
    <rect width="280" height="135" rx="14" class="card"/>
    <text x="24" y="34" class="label">Throughput at 100 MHz</text>
    <text x="24" y="84" class="number">{100 / perf['cpi']:.1f} MIPS</text>
    <text x="24" y="113" class="foot">derived; timing closure not claimed</text>
  </g>
  <text x="55" y="302" class="heading">LUT primitive distribution</text>
  {''.join(bar_markup)}
  <g transform="translate(785 305)">
    <rect width="360" height="260" rx="14" class="card"/>
    <text x="24" y="40" class="heading">Measured workload</text>
    <text x="24" y="82" class="label">Cycles</text><text x="205" y="82" class="barvalue">{perf['cycles']}</text>
    <text x="24" y="116" class="label">Retired instructions</text><text x="205" y="116" class="barvalue">{perf['retired_instructions']}</text>
    <text x="24" y="150" class="label">IPC</text><text x="205" y="150" class="barvalue">{perf['ipc']:.3f}</text>
    <text x="24" y="184" class="label">Instruction transfers</text><text x="205" y="184" class="barvalue">{perf['instruction_transactions']}</text>
    <text x="24" y="218" class="label">Data transfers</text><text x="205" y="218" class="barvalue">{perf['data_transactions']}</text>
  </g>
  <text x="55" y="625" class="foot">Generic counts and full logs are checked in under reports/oss-cad/. Results describe this RTL snapshot, not final FPGA utilization or fmax.</text>
</svg>'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", type=Path, required=True)
    args = parser.parse_args()
    yosys = args.suite.resolve() / "bin" / "yosys"
    if not yosys.is_file():
        raise SystemExit(f"OSS CAD Suite Yosys not found: {yosys}")

    report_dir = ROOT / "reports" / "oss-cad"
    diagram_dir = ROOT / "docs" / "diagrams" / "generated"
    report_dir.mkdir(parents=True, exist_ok=True)
    diagram_dir.mkdir(parents=True, exist_ok=True)
    sources = " ".join(RTL)

    generic_json = report_dir / "generic-stat.json"
    generic_log = run_yosys(
        yosys,
        f"plugin -i slang; read_slang --top rv32i_core {sources}; "
        f"synth -top rv32i_core; tee -o {generic_json} stat -json",
        report_dir / "generic-synthesis.txt",
    )
    xc7_log = run_yosys(
        yosys,
        f"plugin -i slang; read_slang --top rv32i_core {sources}; "
        "synth_xilinx -family xc7 -top rv32i_core; stat -tech xilinx",
        report_dir / "xc7-synthesis.txt",
    )
    generic = json.loads(generic_json.read_text())
    generic_json.write_text(json.dumps(generic, indent=2) + "\n")
    cells = generic["modules"]["\\rv32i_core"]["num_cells_by_type"]
    perf_path = ROOT / "sim" / "build" / "cocotb" / "performance.json"
    if not perf_path.is_file():
        raise SystemExit("Run 'make test-cocotb' before generating this report")

    version_line = subprocess.run(
        [str(yosys), "-V"], text=True, capture_output=True, check=True
    ).stdout.strip()
    raw_release = (args.suite.resolve() / "VERSION").read_text().strip()
    suite_release = (
        f"{raw_release[0:4]}-{raw_release[4:6]}-{raw_release[6:8]}"
        if re.fullmatch(r"\d{8}", raw_release)
        else raw_release
    )
    data = {
        "suite_release": suite_release,
        "yosys_version": version_line,
        "yosys_version_short": " ".join(version_line.split()[:2]),
        "top": "rv32i_core",
        "generic_synthesis": {
            "cells": generic["modules"]["\\rv32i_core"]["num_cells"],
            "sequential_cells": sum(value for key, value in cells.items() if "DFF" in key),
            "mux_cells": cells.get("$_MUX_", 0),
        },
        "xc7_estimate": {
            "estimated_lcs": metric(xc7_log, r"Estimated number of LCs:\s+(\d+)"),
            "flip_flops": metric(xc7_log, r"^\s*(\d+)\s+FDCE$")
            + metric(xc7_log, r"^\s*(\d+)\s+FDPE$"),
            **{f"lut{i}": metric(xc7_log, rf"^\s*(\d+)\s+LUT{i}$") for i in range(1, 7)},
            "carry4": metric(xc7_log, r"^\s*(\d+)\s+CARRY4$"),
            "muxf7": metric(xc7_log, r"^\s*(\d+)\s+MUXF7$"),
            "muxf8": metric(xc7_log, r"^\s*(\d+)\s+MUXF8$"),
        },
        "zero_wait_performance": json.loads(perf_path.read_text()),
        "wait_state_performance": json.loads(
            (ROOT / "sim" / "build" / "cocotb" / "performance-waits.json").read_text()
        ),
        "scope": "pre-place-and-route core-only estimate; no BRAM, timing, or fmax claim",
    }
    (report_dir / "summary.json").write_text(json.dumps(data, indent=2) + "\n")
    svg_path = diagram_dir / "oss-cad-results.svg"
    svg_path.write_text(build_svg(data))

    chrome = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
    if chrome.is_file():
        subprocess.run(
            [
                str(chrome),
                "--headless=new",
                "--disable-gpu",
                "--hide-scrollbars",
                "--window-size=1200,650",
                f"--screenshot={diagram_dir / 'oss-cad-results.png'}",
                svg_path.as_uri(),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    print(f"Report: {report_dir / 'summary.json'}")
    print(f"Diagram: {svg_path}")


if __name__ == "__main__":
    main()
