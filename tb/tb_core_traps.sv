`timescale 1ns/1ps

// Reset into small programs that each cause one architectural fault. Every case
// checks cause, faulting PC, tval, and sticky behavior as one trap transaction.

module tb_core_traps;
  import rv32i_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  logic imem_valid;
  logic [31:0] imem_addr;
  logic imem_ready;
  logic [31:0] imem_rdata;
  logic imem_error;
  logic dmem_valid;
  logic dmem_write;
  logic [31:0] dmem_addr;
  logic [31:0] dmem_wdata;
  logic [3:0] dmem_wstrb;
  logic dmem_ready;
  logic [31:0] dmem_rdata;
  logic dmem_error;
  logic trap_valid;
  logic [31:0] trap_cause;
  logic [31:0] trap_pc;
  logic [31:0] trap_tval;
  logic retire_valid;
  logic [31:0] retire_pc;
  logic [31:0] retire_instruction;
  logic [31:0] debug_pc;
  logic [1:0] debug_state;

  logic [31:0] memory [0:255];
  integer index;
  integer timeout;
  integer tests;

  always #5 clk = ~clk;

  rv32i_core dut (
    .clk_i(clk), .rst_ni(rst_n),
    .imem_valid_o(imem_valid), .imem_addr_o(imem_addr),
    .imem_ready_i(imem_ready), .imem_rdata_i(imem_rdata),
    .imem_error_i(imem_error),
    .dmem_valid_o(dmem_valid), .dmem_write_o(dmem_write),
    .dmem_addr_o(dmem_addr), .dmem_wdata_o(dmem_wdata),
    .dmem_wstrb_o(dmem_wstrb), .dmem_ready_i(dmem_ready),
    .dmem_rdata_i(dmem_rdata), .dmem_error_i(dmem_error),
    .trap_valid_o(trap_valid), .trap_cause_o(trap_cause),
    .trap_pc_o(trap_pc), .trap_tval_o(trap_tval),
    .retire_valid_o(retire_valid), .retire_pc_o(retire_pc),
    .retire_instruction_o(retire_instruction),
    .debug_pc_o(debug_pc), .debug_state_o(debug_state)
  );

  // A combinational memory is useful here because the tests focus on trap
  // behavior. The main directed test covers a one-cycle synchronous wrapper.
  always_comb begin
    imem_ready = imem_valid;
    imem_error = imem_valid && (imem_addr >= 32'd1024);
    imem_rdata = imem_error ? 32'b0 : memory[imem_addr[9:2]];
    dmem_ready = dmem_valid;
    dmem_error = dmem_valid && (dmem_addr >= 32'd1024);
    dmem_rdata = dmem_error ? 32'b0 : memory[dmem_addr[9:2]];
  end

  // Default unused words to ADDI x0, x0, 0 so only the selected case can trap.
  task automatic clear_memory;
    begin
      for (index = 0; index < 256; index = index + 1)
        memory[index] = 32'h0000_0013;
    end
  endtask

  task automatic reset_core;
    begin
      rst_n = 1'b0;
      repeat (3) @(posedge clk);
      rst_n = 1'b1;
    end
  endtask

  // Wait for and validate the complete external trap record.
  task automatic expect_trap(
    input logic [31:0] expected_cause,
    input logic [31:0] expected_pc,
    input logic [31:0] expected_tval
  );
    begin
      timeout = 0;
      while (!trap_valid && timeout < 40) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (!trap_valid)
        $fatal(1, "Trap test timed out at pc=%08x", debug_pc);
      if ((trap_cause !== expected_cause) || (trap_pc !== expected_pc) ||
          (trap_tval !== expected_tval))
        $fatal(1, "Wrong trap: cause=%0d pc=%08x tval=%08x expected %0d/%08x/%08x",
               trap_cause, trap_pc, trap_tval, expected_cause, expected_pc,
               expected_tval);
      tests = tests + 1;
      @(posedge clk);
      if (!trap_valid)
        $fatal(1, "Trap output was not sticky");
    end
  endtask

  initial begin
    tests = 0;

    clear_memory();
    memory[0] = 32'hffff_ffff;
    reset_core();
    expect_trap(TRAP_ILLEGAL_INSTRUCTION, 0, 32'hffff_ffff);

    clear_memory();
    memory[0] = 32'h0000_0073;
    reset_core();
    expect_trap(TRAP_ECALL_MMODE, 0, 0);

    clear_memory();
    memory[0] = 32'h0010_0073;
    reset_core();
    expect_trap(TRAP_BREAKPOINT, 0, 0);

    clear_memory();
    memory[0] = 32'h0020_006f; // jal x0, +2
    reset_core();
    expect_trap(TRAP_INSTR_ADDR_MISALIGNED, 0, 2);

    clear_memory();
    memory[0] = 32'h0010_0093; // addi x1, x0, 1
    memory[1] = 32'h0000_a103; // lw x2, 0(x1)
    reset_core();
    expect_trap(TRAP_LOAD_ADDR_MISALIGNED, 4, 1);

    clear_memory();
    memory[0] = 32'h0010_0093; // addi x1, x0, 1
    memory[1] = 32'h0020_a023; // sw x2, 0(x1)
    reset_core();
    expect_trap(TRAP_STORE_ADDR_MISALIGNED, 4, 1);

    clear_memory();
    memory[0] = 32'h0000_20b7; // lui x1, 0x2 -> 0x2000
    memory[1] = 32'h0000_a103; // lw x2, 0(x1)
    reset_core();
    expect_trap(TRAP_LOAD_ACCESS_FAULT, 4, 32'h0000_2000);

    clear_memory();
    memory[0] = 32'h0000_20b7;
    memory[1] = 32'h0020_a023; // sw x2, 0(x1)
    reset_core();
    expect_trap(TRAP_STORE_ACCESS_FAULT, 4, 32'h0000_2000);

    clear_memory();
    memory[0] = 32'h0000_206f; // jal x0, +0x2000
    reset_core();
    expect_trap(TRAP_INSTR_ACCESS_FAULT, 32'h0000_2000, 32'h0000_2000);

    $display("PASS: %0d architectural trap checks", tests);
    $finish;
  end
endmodule
