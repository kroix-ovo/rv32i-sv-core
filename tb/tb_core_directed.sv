`timescale 1ns/1ps

// Run the self-checking RV32I machine-code image through the synchronous SoC.
// Software writes a pass/fail signature, keeping the testbench independent of
// internal register names and aligned with the eventual FPGA execution path.

module tb_core_directed;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [31:0] gpio;
  logic trap_valid;
  logic [31:0] trap_cause;
  logic [31:0] trap_pc;
  logic [31:0] debug_pc;
  logic retire_valid;
  integer cycles;
  localparam integer SIGNATURE_WORD = 32'h900 >> 2;

  always #5 clk = ~clk;

  rv32i_soc #(
    .MEM_WORDS(1024),
    .MEM_INIT_FILE("sim/programs/rv32i_directed.hex")
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .gpio_o(gpio),
    .trap_valid_o(trap_valid),
    .trap_cause_o(trap_cause),
    .trap_pc_o(trap_pc),
    .debug_pc_o(debug_pc),
    .retire_valid_o(retire_valid)
  );

  initial begin
    repeat (4) @(posedge clk);
    rst_n <= 1'b1;

    for (cycles = 0; cycles < 10000; cycles = cycles + 1) begin
      @(posedge clk);
      if (trap_valid)
        $fatal(1, "Unexpected trap: cause=%0d pc=%08x", trap_cause, trap_pc);
      if (dut.memory[SIGNATURE_WORD] == 32'h600d_600d) begin
        $display("PASS: directed RV32I program completed in %0d cycles", cycles);
        $finish;
      end
      if (dut.memory[SIGNATURE_WORD] == 32'hbad0_0001)
        $fatal(1, "Directed RV32I program reached its failure handler at pc=%08x",
               debug_pc);
    end

    $fatal(1, "Timeout waiting for directed program, pc=%08x", debug_pc);
  end
endmodule
