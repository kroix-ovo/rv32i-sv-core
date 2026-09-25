"""Compile all RTL and testbench sources with the slang SystemVerilog front end."""

from __future__ import annotations

from pathlib import Path
import sys

import pyslang


REPO = Path(__file__).resolve().parents[1]
SOURCES = [
    *sorted((REPO / "rtl").glob("*.sv")),
    *sorted((REPO / "fpga").glob("*.sv")),
    *sorted((REPO / "tb").glob("*.sv")),
]

source_manager = pyslang.SourceManager()
compilation = pyslang.ast.Compilation()
for source in SOURCES:
    tree = pyslang.syntax.SyntaxTree.fromFile(str(source), source_manager)
    compilation.addSyntaxTree(tree)

diagnostics = compilation.getAllDiagnostics()
rendered = pyslang.DiagnosticEngine.reportAll(source_manager, diagnostics)
if rendered:
    print(rendered, end="")

engine = pyslang.DiagnosticEngine(source_manager)
engine.issue(diagnostics)
print(f"slang checked {len(SOURCES)} files: {engine.numErrors} errors, {engine.numWarnings} warnings")
sys.exit(1 if engine.numErrors else 0)

