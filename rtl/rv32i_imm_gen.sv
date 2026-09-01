`timescale 1ns/1ps

// Reconstruct the I, S, B, U, and J immediate layouts defined by the RV32I ISA.
// Branch and jump outputs include their implicit low zero bit and are therefore
// byte offsets ready for the next-PC adder.

/* verilator lint_off UNUSEDSIGNAL */
module rv32i_imm_gen (
  // Raw instruction, decoder-selected layout, and sign-extended result.
  input  logic [31:0]          instruction_i,
  input  rv32i_pkg::imm_sel_t  select_i,
  output logic [31:0]          immediate_o
);
  import rv32i_pkg::*;

  // Instruction bit 31 is the sign bit in every sign-extended layout.
  always_comb begin
    case (select_i)
      IMM_I: immediate_o = {{20{instruction_i[31]}}, instruction_i[31:20]};
      IMM_S: immediate_o = {{20{instruction_i[31]}}, instruction_i[31:25],
                             instruction_i[11:7]};
      IMM_B: immediate_o = {{19{instruction_i[31]}}, instruction_i[31],
                             instruction_i[7], instruction_i[30:25],
                             instruction_i[11:8], 1'b0};
      IMM_U: immediate_o = {instruction_i[31:12], 12'b0};
      IMM_J: immediate_o = {{11{instruction_i[31]}}, instruction_i[31],
                             instruction_i[19:12], instruction_i[20],
                             instruction_i[30:21], 1'b0};
      default: immediate_o = 32'b0;
    endcase
  end
endmodule
/* verilator lint_on UNUSEDSIGNAL */
