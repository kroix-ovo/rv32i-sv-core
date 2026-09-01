`timescale 1ns/1ps

// Execute RV32I arithmetic, logical, shift, and comparison operations. The
// module is purely combinational; signed casts are confined to SLT and SRA so
// the remaining operations preserve the input bit patterns.

module rv32i_alu (
  // Selected datapath operands and decoded operation.
  input  logic [31:0]         lhs_i,
  input  logic [31:0]         rhs_i,
  input  rv32i_pkg::alu_op_t  op_i,
  output logic [31:0]         result_o
);
  import rv32i_pkg::*;

  // Shift amounts use only the low five bits because RV32I has XLEN=32.
  always_comb begin
    case (op_i)
      ALU_ADD:  result_o = lhs_i + rhs_i;
      ALU_SUB:  result_o = lhs_i - rhs_i;
      ALU_SLL:  result_o = lhs_i << rhs_i[4:0];
      ALU_SLT:  result_o = {31'b0, $signed(lhs_i) < $signed(rhs_i)};
      ALU_SLTU: result_o = {31'b0, lhs_i < rhs_i};
      ALU_XOR:  result_o = lhs_i ^ rhs_i;
      ALU_SRL:  result_o = lhs_i >> rhs_i[4:0];
      ALU_SRA:  result_o = $unsigned($signed(lhs_i) >>> rhs_i[4:0]);
      ALU_OR:   result_o = lhs_i | rhs_i;
      ALU_AND:  result_o = lhs_i & rhs_i;
      default:  result_o = 32'b0;
    endcase
  end
endmodule
