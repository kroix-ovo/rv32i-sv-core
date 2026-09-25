# Interactive RV32I architecture map

`rv32i-core.architecture.json` is the diagram specification. It describes the
checked-in five-stage pipeline. `rv32i-core.architecture.html` is a
self-contained interactive viewer with the same current labels and notes.
The stage diagram in `../diagrams/core_datapath.svg` shows the interstage
registers more directly; this map groups the datapath into functional blocks.

The map provides three guided views:

- instruction fetch, decode, execute, writeback, and retirement;
- load effective-address, request, return, alignment, and writeback flow;
- pipeline interlocks and externally visible trap/retirement behavior.

It also records the architectural boundary, ready/valid invariants, and
Vivado implementation evidence. The reported timing is post-route; the
physical board has not been tested.

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
runs the automated Chrome viewport/readability check. The earlier multicycle
screenshots and visual-check receipt were removed; no new Archify visual-check
receipt is claimed for this pipeline map.

## Attribution

The CPU topology and explanatory content are project-authored from the RTL.
The generated viewer uses Archify 2.16.0. Archify is licensed under the MIT
license; see [ARCHIFY_LICENSE.txt](ARCHIFY_LICENSE.txt).
