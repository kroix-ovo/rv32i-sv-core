# Interactive RV32I architecture map

`rv32i-core.architecture.json` is the source-of-truth diagram specification.
It describes the checked-in multicycle RTL rather than an idealized or pipelined
RISC-V implementation. `rv32i-core.architecture.html` is a self-contained
Archify viewer generated from that specification.

The map provides three guided views:

- instruction fetch, decode, execute, writeback, and retirement;
- load effective-address, request, return, alignment, and writeback flow;
- controller ownership and externally visible trap/retirement behavior.

It also records the architectural boundary, ready/valid invariants, and the
scope of the completed simulation evidence. Simulation results do not claim
FPGA timing closure.

## Rebuild and check

The default path assumes `archify-main` and `rv32i_sv_core` are sibling
directories. Override `ARCHIFY_ROOT` or `NODE` when they are installed
elsewhere.

```bash
make architecture-map
make architecture-check
```

`architecture-map` performs Archify's showcase validation before writing the
self-contained HTML. `architecture-check` repeats specification validation and
runs the automated Chrome viewport/readability check. The checked-in PNGs,
JSON receipt, and contact sheet are evidence from that visual check.

## Attribution

The CPU topology and explanatory content are project-authored from the RTL.
The generated viewer uses Archify 2.16.0. Archify is licensed under the MIT
license; see [ARCHIFY_LICENSE.txt](ARCHIFY_LICENSE.txt).
