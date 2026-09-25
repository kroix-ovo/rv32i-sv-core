# Five-stage pipeline

The synthesizable `rv32i_core` has IF, ID, EX, MEM, and WB stages. The
interstage valid bits are `if_valid_q`, `id_valid_q`, `ex_valid_q`, and
`wb_valid_q`. IF is the outstanding instruction-memory request at
`fetch_pc_q`; an accepted response fills the IF/ID register.

| Stage | Work | State passed onward |
| --- | --- | --- |
| IF | Request a four-byte-aligned instruction; hold address until ready | Instruction and PC |
| ID | Decode, read x0–x31, wait on RAW dependencies | Operands, immediate, controls, PC |
| EX | ALU, branch decision, effective address, alignment/illegal checks | ALU/link result or memory request |
| MEM | Complete load/store handshake and extract signed/unsigned data | Result, destination, retirement identity |
| WB | Write destination register and report one retirement | Architectural state |

There is no forwarding in this baseline. ID waits while a source register has
an older writer in ID/EX, EX/MEM, or MEM/WB. A stalled data request holds
EX/MEM and all younger stages; WB may still retire once. IF pauses for an
unresolved branch or jump, FENCE, faulting instruction, or memory operation.
This keeps the existing non-cancellable ready/valid requests stable and means
throughput is below one instruction per cycle. Branches resolve in EX.

For example, suppose `ADDI x1,x0,7` is followed by `ADD x2,x1,x1`.
The ADD needs the new x1 value. While ADDI is in ID/EX, EX/MEM, or MEM/WB,
`dependency` is high. ADD remains in IF/ID and `id_valid_q` receives a
bubble (valid = 0). After ADDI's WB edge writes x1, ADD reads 7 from both
source ports and moves to ID/EX. Its EX result is 14.

The `_q` suffix marks clocked values. `assign` and `always_comb` describe
logic that responds to inputs in the current cycle. `always_ff` describes
flip-flops that change at a clock edge. A nonblocking assignment (`<=`)
uses values from before that edge; this is why one instruction can move from
ID/EX to EX/MEM while another moves from IF/ID to ID/EX on the same edge.
When a valid bit is zero, the data bits beside it are ignored.

MEM faults take priority over EX faults, which take priority over fetch faults.
Younger instructions are discarded; older instructions retire before the
sticky external trap is published. A faulting instruction does not retire or
write a destination register. `debug_state_o` is now a status summary:
0 flowing, 1 interlock/serialization, 2 memory wait, 3 trapped. It is not a
pipeline stage number.

The cocotb bench uses a memory transaction driver with seeded wait states,
request monitors, an instruction-retirement scoreboard backed by
`python/rv32i_model.py`, and coverage checks for stage overlap, RAW stalls,
and memory waits. This borrows UVM's driver/monitor/scoreboard/coverage
separation; it is not a SystemVerilog UVM implementation.

Vivado 2023.2 simulation, synthesis, and routed timing results are in
`docs/pipeline_vivado_report.md`. Physical-board execution remains untested.
Existing generated PDFs, static datapath graphics, and Archify artifacts
still describe the earlier multicycle controller.
