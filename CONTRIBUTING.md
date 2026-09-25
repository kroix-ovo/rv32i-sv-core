# Contributing

Keep changes small enough to explain in a waveform. An ISA change should include a directed test, and a memory-interface change should include a wait-state test or assertion.

Run the program generator, reference model, SystemVerilog checks, and RTL simulations before opening a pull request:

```powershell
python sim/build_programs.py
python python/rv32i_model.py
.\.venv\Scripts\python scripts\lint_sv.py
.\scripts\run_tests.ps1
```

Do not weaken illegal-instruction or alignment checks to make a test pass. If behavior differs from the specification, record the instruction word, operand values, expected result, actual result, and the specification section used to decide.

Code comments should explain hardware behavior or a non-obvious ISA rule. Avoid comments that only restate the line below them.

