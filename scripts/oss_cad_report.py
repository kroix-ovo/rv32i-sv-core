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
    waits = data["wait_state_performance"]
    generic = data["generic_synthesis"]
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
        y = 444 + index * 39
        width = 430 * value / max_value
        bar_markup.append(
            f'<text x="78" y="{y + 16}" class="mono">{label}</text>'
            f'<rect x="140" y="{y}" width="{width:.1f}" height="19" class="bar"/>'
            f'<text x="{153 + width:.1f}" y="{y + 16}" class="mono">{value}</text>'
        )
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1400" height="820" viewBox="0 0 1400 820" role="img" aria-labelledby="title desc">
  <title id="title">RV32I core synthesis and cycle characterization sheet</title>
  <desc id="desc">Engineering report sheet containing Yosys XC7 resource estimates, Verilator cycle measurements, state sequencing, tool versions, and result limitations.</desc>
  <style>
    .paper {{ fill:#f5f3ec }} .ink {{ fill:#18222b }} .muted {{ fill:#53616a }}
    .rule {{ fill:none; stroke:#263944; stroke-width:1.4 }}
    .fine {{ fill:none; stroke:#829099; stroke-width:0.8 }}
    .dash {{ fill:none; stroke:#829099; stroke-width:1; stroke-dasharray:6 5 }}
    .accent {{ fill:#075d78 }} .warn {{ fill:#b64a2b }} .bar {{ fill:#1c7893 }}
    .title {{ fill:#18222b; font:700 28px Arial,sans-serif; letter-spacing:1px }}
    .kicker {{ fill:#075d78; font:700 12px Arial,sans-serif; letter-spacing:2px }}
    .section {{ fill:#f5f3ec; font:700 14px Arial,sans-serif; letter-spacing:1px }}
    .label {{ fill:#53616a; font:12px Arial,sans-serif }}
    .value {{ fill:#18222b; font:700 22px 'Courier New',monospace }}
    .mono {{ fill:#18222b; font:13px 'Courier New',monospace }}
    .small {{ fill:#53616a; font:11px Arial,sans-serif }}
    .state {{ fill:#f5f3ec; stroke:#075d78; stroke-width:1.5 }}
  </style>
  <defs><pattern id="grid" width="20" height="20" patternUnits="userSpaceOnUse"><path d="M20 0H0V20" fill="none" stroke="#9ba6aa" stroke-width="0.35" opacity="0.34"/></pattern><marker id="arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0 0L8 4L0 8Z" class="accent"/></marker></defs>
  <rect width="1400" height="820" class="paper"/><rect x="28" y="28" width="1344" height="764" fill="url(#grid)" class="rule"/>
  <text x="60" y="62" class="kicker">IMPLEMENTATION NOTE / CORE-ONLY / PRE-P&amp;R</text>
  <text x="60" y="101" class="title">RV32I CORE — SYNTHESIS + CYCLE CHARACTERIZATION</text>
  <text x="60" y="128" class="mono">TOP: rv32i_core   ISA: RV32I   BUS: SPLIT READY/VALID   CONTROL: 4-STATE MULTICYCLE</text>
  <rect x="1040" y="46" width="300" height="88" class="rule"/><path d="M1040 76H1340M1155 46V134" class="fine"/>
  <text x="1052" y="66" class="small">REPORT</text><text x="1052" y="101" class="mono">OSS-CAD-001</text>
  <text x="1168" y="66" class="small">TOOL RELEASE</text><text x="1168" y="101" class="mono">{data['suite_release']}</text><text x="1168" y="120" class="small">{data['yosys_version_short']}</text>

  <rect x="52" y="160" width="1296" height="35" class="accent"/><text x="66" y="183" class="section">A. MEASUREMENT CONDITIONS AND EXECUTION PATH</text>
  <text x="66" y="225" class="mono">WORKLOAD</text><text x="180" y="225" class="mono">rv32i_directed.hex / pass signature 0x600D600D</text>
  <text x="66" y="250" class="mono">CLOCK MODEL</text><text x="180" y="250" class="mono">10 ns simulation period; frequency conversion is illustrative only</text>
  <text x="66" y="275" class="mono">SAMPLE</text><text x="180" y="275" class="mono">{perf['retired_instructions']} retired instructions / {perf['data_transactions']} data transactions</text>
  <rect x="800" y="215" width="126" height="54" class="state"/><text x="863" y="239" text-anchor="middle" class="mono">FETCH</text><text x="863" y="257" text-anchor="middle" class="small">imem handshake</text>
  <rect x="975" y="215" width="126" height="54" class="state"/><text x="1038" y="239" text-anchor="middle" class="mono">EXECUTE</text><text x="1038" y="257" text-anchor="middle" class="small">decode / ALU</text>
  <rect x="1150" y="215" width="126" height="54" class="state"/><text x="1213" y="239" text-anchor="middle" class="mono">MEMORY</text><text x="1213" y="257" text-anchor="middle" class="small">load / store only</text>
  <path d="M926 242H968M1101 242H1143" stroke="#075d78" stroke-width="1.6" marker-end="url(#arrow)"/><path d="M1038 274V295H863V276" class="dash" marker-end="url(#arrow)"/><path d="M1213 274V310H863V276" class="dash" marker-end="url(#arrow)"/>

  <rect x="52" y="330" width="630" height="35" class="accent"/><text x="66" y="353" class="section">B. XILINX 7-SERIES TECHNOLOGY ESTIMATE</text>
  <text x="68" y="400" class="label">EST. LOGIC CELLS</text><text x="250" y="400" class="value">{xc7['estimated_lcs']:,}</text>
  <text x="390" y="400" class="label">FLIP-FLOPS</text><text x="520" y="400" class="value">{xc7['flip_flops']:,}</text>
  {''.join(bar_markup)}
  <text x="78" y="695" class="mono">CARRY4  {xc7['carry4']:>4}    MUXF7  {xc7['muxf7']:>4}    MUXF8  {xc7['muxf8']:>4}</text>

  <rect x="710" y="330" width="638" height="35" class="accent"/><text x="724" y="353" class="section">C. MEASURED CYCLE RESULTS</text>
  <path d="M710 414H1348M710 463H1348M710 512H1348M710 561H1348" class="fine"/>
  <path d="M960 380V561M1062 380V561M1166 380V561M1268 380V561" class="fine"/>
  <text x="724" y="401" class="small">MEMORY RESPONSE</text><text x="974" y="401" class="small">CYCLES</text><text x="1076" y="401" class="small">RETIRED</text><text x="1180" y="401" class="small">CPI</text><text x="1282" y="401" class="small">IPC</text>
  <text x="724" y="446" class="mono">zero inserted wait</text><text x="974" y="446" class="mono">{perf['cycles']}</text><text x="1076" y="446" class="mono">{perf['retired_instructions']}</text><text x="1180" y="446" class="mono">{perf['cpi']:.3f}</text><text x="1282" y="446" class="mono">{perf['ipc']:.3f}</text>
  <text x="724" y="495" class="mono">seeded 0–3 cycles</text><text x="974" y="495" class="mono">{waits['cycles']}</text><text x="1076" y="495" class="mono">{waits['retired_instructions']}</text><text x="1180" y="495" class="mono">{waits['cpi']:.3f}</text><text x="1282" y="495" class="mono">{waits['ipc']:.3f}</text>
  <text x="724" y="544" class="mono">wait contribution</text><text x="974" y="544" class="mono">I:{waits['instruction_wait_cycles']}</text><text x="1076" y="544" class="mono">D:{waits['data_wait_cycles']}</text><text x="1180" y="544" class="small">seed 0x321C</text>
  <text x="724" y="600" class="label">DERIVED RATE @ 100 MHz (NO TIMING CLAIM)</text><text x="724" y="633" class="value">{100 / perf['cpi']:.1f} MIPS</text><text x="930" y="633" class="mono">zero-wait</text><text x="1070" y="633" class="value">{100 / waits['cpi']:.1f} MIPS</text><text x="1260" y="633" class="mono">waited</text>
  <text x="724" y="682" class="label">GENERIC NETLIST</text><text x="850" y="682" class="mono">{generic['cells']} cells / {generic['sequential_cells']} seq / {generic['mux_cells']} mux</text>
  <rect x="710" y="706" width="638" height="42" fill="#ece5d9" stroke="#b64a2b" stroke-width="1.4"/><text x="724" y="724" class="small">LIMIT: RESOURCE MAPPING ONLY. NO XC7A100T PLACEMENT, ROUTING, SLACK, POWER, BRAM,</text><text x="724" y="740" class="small">OR FMAX RESULT IS CLAIMED. VIVADO IMPLEMENTATION REMAINS THE BOARD-LEVEL AUTHORITY.</text>

  <rect x="52" y="760" width="1296" height="32" class="rule"/><path d="M980 760V792M1160 760V792" class="fine"/>
  <text x="64" y="781" class="small">SOURCE: reports/oss-cad/summary.json + cocotb measured counters</text><text x="992" y="781" class="small">SCOPE: rv32i_core</text><text x="1172" y="781" class="small">STATUS: REPRODUCIBLE</text>
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
                "--window-size=1400,820",
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
