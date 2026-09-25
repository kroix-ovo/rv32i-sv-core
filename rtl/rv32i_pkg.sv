`timescale 1ns/1ps

// Define the shared control vocabulary for the RV32I datapath. Named enums keep
// decode intent visible in RTL reviews and waveform viewers; this package does
// not elaborate into hardware by itself.

package rv32i_pkg;

  // ALU operation selected by the instruction decoder.
  typedef enum logic [3:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR, ALU_AND
  } alu_op_t;

  // Encoded immediate layout reconstructed by rv32i_imm_gen.
  typedef enum logic [2:0] {
    IMM_I, IMM_S, IMM_B, IMM_U, IMM_J
  } imm_sel_t;

  // Source placed on the register-file writeback port.
  typedef enum logic [1:0] {
    WB_ALU, WB_MEMORY, WB_PC_PLUS_4
  } wb_sel_t;

  // Conditional branch predicate; BR_NONE disables the comparator result.
  typedef enum logic [2:0] {
    BR_NONE, BR_EQ, BR_NE, BR_LT, BR_GE, BR_LTU, BR_GEU
  } branch_op_t;

  // Native memory transfer width before byte-lane alignment.
  typedef enum logic [1:0] {
    MEM_BYTE, MEM_HALF, MEM_WORD
  } mem_size_t;

  // Exception numbers follow the RISC-V privileged architecture convention.
  localparam logic [31:0] TRAP_INSTR_ADDR_MISALIGNED = 32'd0;
  localparam logic [31:0] TRAP_INSTR_ACCESS_FAULT    = 32'd1;
  localparam logic [31:0] TRAP_ILLEGAL_INSTRUCTION  = 32'd2;
  localparam logic [31:0] TRAP_BREAKPOINT           = 32'd3;
  localparam logic [31:0] TRAP_LOAD_ADDR_MISALIGNED = 32'd4;
  localparam logic [31:0] TRAP_LOAD_ACCESS_FAULT    = 32'd5;
  localparam logic [31:0] TRAP_STORE_ADDR_MISALIGNED= 32'd6;
  localparam logic [31:0] TRAP_STORE_ACCESS_FAULT   = 32'd7;
  localparam logic [31:0] TRAP_ECALL_MMODE          = 32'd11;

endpackage
