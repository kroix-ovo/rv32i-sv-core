`timescale 1ns/1ps

// Check one representative value for every ALU operation. Negative operands
// distinguish signed comparison and arithmetic shift from their unsigned forms.

module tb_alu;
  import rv32i_pkg::*;

  logic [31:0] lhs;
  logic [31:0] rhs;
  alu_op_t op;
  logic [31:0] result;
  integer checks;

  rv32i_alu dut (.lhs_i(lhs), .rhs_i(rhs), .op_i(op), .result_o(result));

  // Apply one vector and fail immediately on a four-state mismatch.
  task automatic check(
    input alu_op_t operation,
    input logic [31:0] left,
    input logic [31:0] right,
    input logic [31:0] expected
  );
    begin
      op = operation;
      lhs = left;
      rhs = right;
      #1;
      checks = checks + 1;
      if (result !== expected)
        $fatal(1, "ALU check %0d failed: got %08x expected %08x", checks,
               result, expected);
    end
  endtask

  initial begin
    checks = 0;
    check(ALU_ADD,  32'd7,  32'd5,  32'd12);
    check(ALU_SUB,  32'd7,  32'd9,  32'hffff_fffe);
    check(ALU_SLL,  32'd1,  32'd31, 32'h8000_0000);
    check(ALU_SLT,  32'hffff_ffff, 32'd1, 32'd1);
    check(ALU_SLTU, 32'hffff_ffff, 32'd1, 32'd0);
    check(ALU_XOR,  32'ha5a5_0000, 32'h0f0f_0f0f, 32'haaaa_0f0f);
    check(ALU_SRL,  32'h8000_0000, 32'd4, 32'h0800_0000);
    check(ALU_SRA,  32'h8000_0000, 32'd4, 32'hf800_0000);
    check(ALU_OR,   32'hf000_00f0, 32'h0f00_000f, 32'hff00_00ff);
    check(ALU_AND,  32'hf0f0_aa55, 32'h0ff0_55aa, 32'h00f0_0000);
    $display("PASS: %0d ALU checks", checks);
    $finish;
  end
endmodule
