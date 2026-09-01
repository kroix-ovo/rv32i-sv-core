# Memory interface

The core has one instruction request port and one data request port. Each uses the same valid/ready rule. The ports are separate so a future system can connect Harvard memories, caches, or two bus adapters. This multicycle core never asserts both request ports at the same time.

## Request rule

The core starts a transfer by raising `valid`. It holds `valid`, the address, and every request control signal stable until memory raises `ready`. Memory must present `rdata` and `error` in the cycle where both signals are high.

```text
clock        0      1      2      3
valid        0      1      1      0
address      -      A      A      -
ready        0      0      1      0
rdata        -      -      D      -
transfer                   ^
```

Memory may answer in the first valid cycle or insert any number of wait cycles. The core does not issue a second request while it waits.

## Instruction port

| Signal | Direction | Meaning |
| --- | --- | --- |
| `imem_valid_o` | core to memory | Instruction request is active |
| `imem_addr_o[31:0]` | core to memory | Four-byte-aligned byte address |
| `imem_ready_i` | memory to core | Request completed this cycle |
| `imem_rdata_i[31:0]` | memory to core | Fetched instruction word |
| `imem_error_i` | memory to core | Instruction access fault |

## Data port

| Signal | Direction | Meaning |
| --- | --- | --- |
| `dmem_valid_o` | core to memory | Load or store request is active |
| `dmem_write_o` | core to memory | One for a store, zero for a load |
| `dmem_addr_o[31:0]` | core to memory | Original byte address |
| `dmem_wdata_o[31:0]` | core to memory | Store bytes placed in their bus lanes |
| `dmem_wstrb_o[3:0]` | core to memory | One write enable per byte lane |
| `dmem_ready_i` | memory to core | Request completed this cycle |
| `dmem_rdata_i[31:0]` | memory to core | Aligned word containing load data |
| `dmem_error_i` | memory to core | Load or store access fault |

For data reads, the memory should use `dmem_addr_o[31:2]` to select the word. The core uses the low address bits to select a byte or halfword. `rv32i_soc.sv` is the reference implementation of this rule.

## FENCE behavior

There is no request queue, cache, or write buffer. A new instruction cannot execute until the current data transfer completes. All earlier memory operations are therefore complete when `FENCE` reaches execute. The decoder accepts `FENCE`, and the core retires it without another hardware action.

