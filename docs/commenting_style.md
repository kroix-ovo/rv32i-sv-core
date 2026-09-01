# RTL commenting style

The SystemVerilog comments follow the same structural ideas used by
[Aegis-Stream](https://github.com/kroix-ovo/Aegis-Stream), adapted to a teaching
CPU rather than copied line for line.

- Start each module with two or three lines describing its contract and key
  invariant.
- Label port groups by transaction or purpose: clock/reset, instruction memory,
  data memory, traps, and retirement.
- Comment registered state and transaction boundaries, not obvious syntax.
- Place protocol invariants beside the logic that enforces them, especially
  request stability, x0 behavior, alignment, byte strobes, and sticky traps.
- Reserve `/* verilator lint_* */` comments for genuine Verilator directives;
  ordinary version notes and explanations use normal `//` comments.
- Keep verification intent in testbenches and assertions, while synthesizable
  modules explain hardware behavior and interface guarantees.

The result is deliberately compact: a reader should understand why a block
exists and what must remain true without comments restating every assignment.
