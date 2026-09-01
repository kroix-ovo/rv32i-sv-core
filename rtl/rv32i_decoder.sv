`timescale 1ns/1ps

// Decode one 32-bit instruction into datapath, memory, writeback, and control-
// transfer signals. Reserved encodings keep valid_o low so the core reports a
// deterministic illegal-instruction trap.

module rv32i_decoder (
  // Instruction input and decoded execution controls.
  input  logic [31:0]             instruction_i,
  output logic                    valid_o,
  output rv32i_pkg::alu_op_t      alu_op_o,
  output rv32i_pkg::imm_sel_t     imm_sel_o,
  output logic                    alu_lhs_pc_o,
  output logic                    alu_lhs_zero_o,
  output logic                    alu_rhs_imm_o,
  output logic                    reg_write_o,
  output rv32i_pkg::wb_sel_t      wb_sel_o,
  output logic                    mem_read_o,
  output logic                    mem_write_o,
  output rv32i_pkg::mem_size_t    mem_size_o,
  output logic                    mem_unsigned_o,
  output rv32i_pkg::branch_op_t   branch_op_o,
  output logic                    jump_o,
  output logic                    jalr_o,
  output logic                    ecall_o,
  output logic                    ebreak_o,
  output logic                    fence_o
);
  import rv32i_pkg::*;

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  assign opcode = instruction_i[6:0];
  assign funct3 = instruction_i[14:12];
  assign funct7 = instruction_i[31:25];

  // Safe defaults describe an invalid side-effect-free instruction. Each legal
  // opcode overrides only the controls it needs.
  always_comb begin
    valid_o        = 1'b0;
    alu_op_o       = ALU_ADD;
    imm_sel_o      = IMM_I;
    alu_lhs_pc_o   = 1'b0;
    alu_lhs_zero_o = 1'b0;
    alu_rhs_imm_o  = 1'b0;
    reg_write_o    = 1'b0;
    wb_sel_o       = WB_ALU;
    mem_read_o     = 1'b0;
    mem_write_o    = 1'b0;
    mem_size_o     = MEM_WORD;
    mem_unsigned_o = 1'b0;
    branch_op_o    = BR_NONE;
    jump_o         = 1'b0;
    jalr_o         = 1'b0;
    ecall_o        = 1'b0;
    ebreak_o       = 1'b0;
    fence_o        = 1'b0;

    case (opcode)
      7'b0110111: begin // LUI
        valid_o       = 1'b1;
        imm_sel_o     = IMM_U;
        alu_lhs_zero_o= 1'b1;
        alu_rhs_imm_o = 1'b1;
        reg_write_o   = 1'b1;
      end

      7'b0010111: begin // AUIPC
        valid_o       = 1'b1;
        imm_sel_o     = IMM_U;
        alu_lhs_pc_o  = 1'b1;
        alu_rhs_imm_o = 1'b1;
        reg_write_o   = 1'b1;
      end

      7'b1101111: begin // JAL
        valid_o       = 1'b1;
        imm_sel_o     = IMM_J;
        reg_write_o   = 1'b1;
        wb_sel_o      = WB_PC_PLUS_4;
        jump_o        = 1'b1;
      end

      7'b1100111: begin // JALR has only one legal funct3 value.
        if (funct3 == 3'b000) begin
          valid_o       = 1'b1;
          imm_sel_o     = IMM_I;
          reg_write_o   = 1'b1;
          wb_sel_o      = WB_PC_PLUS_4;
          jalr_o        = 1'b1;
        end
      end

      7'b1100011: begin // Conditional branches
        imm_sel_o = IMM_B;
        case (funct3)
          3'b000: begin valid_o = 1'b1; branch_op_o = BR_EQ;  end
          3'b001: begin valid_o = 1'b1; branch_op_o = BR_NE;  end
          3'b100: begin valid_o = 1'b1; branch_op_o = BR_LT;  end
          3'b101: begin valid_o = 1'b1; branch_op_o = BR_GE;  end
          3'b110: begin valid_o = 1'b1; branch_op_o = BR_LTU; end
          3'b111: begin valid_o = 1'b1; branch_op_o = BR_GEU; end
          default: ;
        endcase
      end

      7'b0000011: begin // Loads
        imm_sel_o      = IMM_I;
        alu_rhs_imm_o  = 1'b1;
        reg_write_o    = 1'b1;
        wb_sel_o       = WB_MEMORY;
        mem_read_o     = 1'b1;
        case (funct3)
          3'b000: begin valid_o = 1'b1; mem_size_o = MEM_BYTE; end // LB
          3'b001: begin valid_o = 1'b1; mem_size_o = MEM_HALF; end // LH
          3'b010: begin valid_o = 1'b1; mem_size_o = MEM_WORD; end // LW
          3'b100: begin valid_o = 1'b1; mem_size_o = MEM_BYTE;
                         mem_unsigned_o = 1'b1; end              // LBU
          3'b101: begin valid_o = 1'b1; mem_size_o = MEM_HALF;
                         mem_unsigned_o = 1'b1; end              // LHU
          default: ;
        endcase
      end

      7'b0100011: begin // Stores
        imm_sel_o      = IMM_S;
        alu_rhs_imm_o  = 1'b1;
        mem_write_o    = 1'b1;
        case (funct3)
          3'b000: begin valid_o = 1'b1; mem_size_o = MEM_BYTE; end
          3'b001: begin valid_o = 1'b1; mem_size_o = MEM_HALF; end
          3'b010: begin valid_o = 1'b1; mem_size_o = MEM_WORD; end
          default: ;
        endcase
      end

      7'b0010011: begin // Immediate ALU operations
        imm_sel_o      = IMM_I;
        alu_rhs_imm_o  = 1'b1;
        reg_write_o    = 1'b1;
        case (funct3)
          3'b000: begin valid_o = 1'b1; alu_op_o = ALU_ADD;  end // ADDI
          3'b010: begin valid_o = 1'b1; alu_op_o = ALU_SLT;  end // SLTI
          3'b011: begin valid_o = 1'b1; alu_op_o = ALU_SLTU; end // SLTIU
          3'b100: begin valid_o = 1'b1; alu_op_o = ALU_XOR;  end // XORI
          3'b110: begin valid_o = 1'b1; alu_op_o = ALU_OR;   end // ORI
          3'b111: begin valid_o = 1'b1; alu_op_o = ALU_AND;  end // ANDI
          3'b001: begin
            if (funct7 == 7'b0000000) begin
              valid_o = 1'b1; alu_op_o = ALU_SLL;
            end
          end
          3'b101: begin
            if (funct7 == 7'b0000000) begin
              valid_o = 1'b1; alu_op_o = ALU_SRL;
            end else if (funct7 == 7'b0100000) begin
              valid_o = 1'b1; alu_op_o = ALU_SRA;
            end
          end
          default: ;
        endcase
      end

      7'b0110011: begin // Register-to-register ALU operations
        reg_write_o = 1'b1;
        case ({funct7, funct3})
          10'b0000000_000: begin valid_o = 1'b1; alu_op_o = ALU_ADD;  end
          10'b0100000_000: begin valid_o = 1'b1; alu_op_o = ALU_SUB;  end
          10'b0000000_001: begin valid_o = 1'b1; alu_op_o = ALU_SLL;  end
          10'b0000000_010: begin valid_o = 1'b1; alu_op_o = ALU_SLT;  end
          10'b0000000_011: begin valid_o = 1'b1; alu_op_o = ALU_SLTU; end
          10'b0000000_100: begin valid_o = 1'b1; alu_op_o = ALU_XOR;  end
          10'b0000000_101: begin valid_o = 1'b1; alu_op_o = ALU_SRL;  end
          10'b0100000_101: begin valid_o = 1'b1; alu_op_o = ALU_SRA;  end
          10'b0000000_110: begin valid_o = 1'b1; alu_op_o = ALU_OR;   end
          10'b0000000_111: begin valid_o = 1'b1; alu_op_o = ALU_AND;  end
          default: ;
        endcase
      end

      7'b0001111: begin // FENCE. FENCE.I belongs to the Zifencei extension.
        if (funct3 == 3'b000) begin
          valid_o = 1'b1;
          fence_o = 1'b1;
        end
      end

      7'b1110011: begin // The base SYSTEM instructions always trap here.
        if (instruction_i == 32'h0000_0073) begin
          valid_o = 1'b1;
          ecall_o = 1'b1;
        end else if (instruction_i == 32'h0010_0073) begin
          valid_o = 1'b1;
          ebreak_o = 1'b1;
        end
      end

      default: ;
    endcase
  end
endmodule
