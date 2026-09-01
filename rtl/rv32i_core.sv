`timescale 1ns/1ps

// Join decode, register, ALU, branch, memory, writeback, and trap logic into a
// small multicycle RV32I core. FETCH and MEMORY hold their ready/valid requests
// stable until accepted; TRAP preserves the external fault record until reset.
// Privileged CSRs, interrupts, compressed instructions, and the M extension are
// intentionally outside this teaching core's contract.

module rv32i_core #(
  parameter logic [31:0] RESET_PC = 32'h0000_0000
) (
  // Clock and active-low asynchronous reset.
  input  logic        clk_i,
  input  logic        rst_ni,

  // Instruction-memory ready/valid request. Addresses are byte addresses.
  output logic        imem_valid_o,
  output logic [31:0] imem_addr_o,
  input  logic        imem_ready_i,
  input  logic [31:0] imem_rdata_i,
  input  logic        imem_error_i,

  // Data-memory ready/valid request. wstrb selects little-endian byte lanes.
  output logic        dmem_valid_o,
  output logic        dmem_write_o,
  output logic [31:0] dmem_addr_o,
  output logic [31:0] dmem_wdata_o,
  output logic [3:0]  dmem_wstrb_o,
  input  logic        dmem_ready_i,
  input  logic [31:0] dmem_rdata_i,
  input  logic        dmem_error_i,

  // Sticky external trap record; reset starts instruction fetch again.
  output logic        trap_valid_o,
  output logic [31:0] trap_cause_o,
  output logic [31:0] trap_pc_o,
  output logic [31:0] trap_tval_o,

  // Retirement and debug signals for waveforms and architectural scoreboards.
  output logic        retire_valid_o,
  output logic [31:0] retire_pc_o,
  output logic [31:0] retire_instruction_o,
  output logic [31:0] debug_pc_o,
  output logic [1:0]  debug_state_o
);
  import rv32i_pkg::*;

  // One instruction owns the datapath at a time, so no pipeline hazard state is
  // needed. Loads and stores alone visit STATE_MEMORY.
  typedef enum logic [1:0] {
    STATE_FETCH, STATE_EXECUTE, STATE_MEMORY, STATE_TRAP
  } state_t;

  // Architectural progress registers.
  state_t state_q;
  logic [31:0] pc_q;
  logic [31:0] instruction_q;

  // Decoder outputs describe the instruction currently in instruction_q.
  logic        dec_valid;
  alu_op_t     dec_alu_op;
  imm_sel_t    dec_imm_sel;
  logic        dec_alu_lhs_pc;
  logic        dec_alu_lhs_zero;
  logic        dec_alu_rhs_imm;
  logic        dec_reg_write;
  wb_sel_t     dec_wb_sel;
  logic        dec_mem_read;
  logic        dec_mem_write;
  mem_size_t   dec_mem_size;
  logic        dec_mem_unsigned;
  branch_op_t  dec_branch_op;
  logic        dec_jump;
  logic        dec_jalr;
  logic        dec_ecall;
  logic        dec_ebreak;
  // FENCE is legal decode metadata; serialization is implicit because only one
  // memory request can be outstanding in this multicycle core.
  /* verilator lint_off UNUSEDSIGNAL */
  logic        dec_fence_unused;
  /* verilator lint_on UNUSEDSIGNAL */

  // Combinational datapath values.
  logic [31:0] immediate;
  logic [31:0] rs1_data;
  logic [31:0] rs2_data;
  logic [31:0] alu_lhs;
  logic [31:0] alu_rhs;
  logic [31:0] alu_result;

  // Register-file writeback transaction.
  logic        rf_write;
  logic [4:0]  rf_write_addr;
  logic [31:0] rf_write_data;

  // Control-transfer, alignment, and execute-stage fault decisions.
  logic        branch_taken;
  logic        control_transfer_taken;
  logic [31:0] control_target;
  logic        control_target_misaligned;
  logic        memory_address_misaligned;
  logic        execute_trap;
  logic [31:0] execute_result;

  // A memory request is prepared in EXECUTE and held stable in these registers.
  logic [31:0] memory_addr_q;
  logic [31:0] memory_wdata_q;
  logic [3:0]  memory_wstrb_q;
  logic [31:0] store_wdata;
  logic [3:0]  store_wstrb;
  logic        memory_is_load_q;
  mem_size_t   memory_size_q;
  logic        memory_unsigned_q;
  logic [4:0]  memory_rd_q;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] load_shifted;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [31:0] load_result;

  // Decode and execute datapath.
  rv32i_decoder u_decoder (
    .instruction_i  (instruction_q),
    .valid_o        (dec_valid),
    .alu_op_o       (dec_alu_op),
    .imm_sel_o      (dec_imm_sel),
    .alu_lhs_pc_o   (dec_alu_lhs_pc),
    .alu_lhs_zero_o (dec_alu_lhs_zero),
    .alu_rhs_imm_o  (dec_alu_rhs_imm),
    .reg_write_o    (dec_reg_write),
    .wb_sel_o       (dec_wb_sel),
    .mem_read_o     (dec_mem_read),
    .mem_write_o    (dec_mem_write),
    .mem_size_o     (dec_mem_size),
    .mem_unsigned_o (dec_mem_unsigned),
    .branch_op_o    (dec_branch_op),
    .jump_o         (dec_jump),
    .jalr_o         (dec_jalr),
    .ecall_o        (dec_ecall),
    .ebreak_o       (dec_ebreak),
    .fence_o        (dec_fence_unused)
  );

  rv32i_imm_gen u_imm_gen (
    .instruction_i (instruction_q),
    .select_i      (dec_imm_sel),
    .immediate_o   (immediate)
  );

  rv32i_regfile u_regfile (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .rs1_addr_i  (instruction_q[19:15]),
    .rs2_addr_i  (instruction_q[24:20]),
    .rs1_data_o  (rs1_data),
    .rs2_data_o  (rs2_data),
    .rd_write_i  (rf_write),
    .rd_addr_i   (rf_write_addr),
    .rd_data_i   (rf_write_data)
  );

  assign alu_lhs = dec_alu_lhs_zero ? 32'b0 :
                   dec_alu_lhs_pc   ? pc_q   : rs1_data;
  assign alu_rhs = dec_alu_rhs_imm ? immediate : rs2_data;

  rv32i_alu u_alu (
    .lhs_i    (alu_lhs),
    .rhs_i    (alu_rhs),
    .op_i     (dec_alu_op),
    .result_o (alu_result)
  );

  // Signed and unsigned branch comparisons are kept next to each other so the
  // difference is easy to spot in a waveform or code review.
  always_comb begin
    case (dec_branch_op)
      BR_EQ:   branch_taken = (rs1_data == rs2_data);
      BR_NE:   branch_taken = (rs1_data != rs2_data);
      BR_LT:   branch_taken = ($signed(rs1_data) < $signed(rs2_data));
      BR_GE:   branch_taken = ($signed(rs1_data) >= $signed(rs2_data));
      BR_LTU:  branch_taken = (rs1_data < rs2_data);
      BR_GEU:  branch_taken = (rs1_data >= rs2_data);
      default: branch_taken = 1'b0;
    endcase
  end

  assign control_transfer_taken = dec_jump || dec_jalr ||
                                  ((dec_branch_op != BR_NONE) && branch_taken);
  assign control_target = dec_jalr ? ((rs1_data + immediate) & 32'hffff_fffe)
                                   : (pc_q + immediate);
  assign control_target_misaligned = control_transfer_taken &&
                                     (control_target[1:0] != 2'b00);

  always_comb begin
    case (dec_mem_size)
      MEM_BYTE: memory_address_misaligned = 1'b0;
      MEM_HALF: memory_address_misaligned = alu_result[0];
      default:  memory_address_misaligned = |alu_result[1:0];
    endcase
  end

  assign execute_trap = !dec_valid || dec_ecall || dec_ebreak ||
                        control_target_misaligned ||
                        ((dec_mem_read || dec_mem_write) &&
                         memory_address_misaligned);

  always_comb begin
    case (dec_wb_sel)
      WB_PC_PLUS_4: execute_result = pc_q + 32'd4;
      default:      execute_result = alu_result;
    endcase
  end

  // Byte and halfword store data is repeated across the bus. The byte-enable
  // mask chooses which copy reaches memory.
  always_comb begin
    store_wdata = 32'b0;
    store_wstrb = 4'b0000;
    case (dec_mem_size)
      MEM_BYTE: begin
        store_wdata = {4{rs2_data[7:0]}};
        store_wstrb = 4'b0001 << alu_result[1:0];
      end
      MEM_HALF: begin
        store_wdata = {2{rs2_data[15:0]}};
        store_wstrb = 4'b0011 << alu_result[1:0];
      end
      default: begin
        store_wdata = rs2_data;
        store_wstrb = 4'b1111;
      end
    endcase
  end

  // Memory returns an aligned 32-bit word. Shift the addressed byte or halfword
  // into the low bits before applying signed or unsigned extension.
  assign load_shifted = dmem_rdata_i >> {memory_addr_q[1:0], 3'b000};
  always_comb begin
    case (memory_size_q)
      MEM_BYTE: begin
        if (memory_unsigned_q)
          load_result = {24'b0, load_shifted[7:0]};
        else
          load_result = {{24{load_shifted[7]}}, load_shifted[7:0]};
      end
      MEM_HALF: begin
        if (memory_unsigned_q)
          load_result = {16'b0, load_shifted[15:0]};
        else
          load_result = {{16{load_shifted[15]}}, load_shifted[15:0]};
      end
      default: load_result = dmem_rdata_i;
    endcase
  end

  // Register writes occur on the last cycle of an instruction. A faulting JAL
  // or JALR must not write its link register.
  always_comb begin
    rf_write      = 1'b0;
    rf_write_addr = instruction_q[11:7];
    rf_write_data = execute_result;

    if ((state_q == STATE_EXECUTE) && dec_reg_write &&
        !dec_mem_read && !dec_mem_write && !execute_trap) begin
      rf_write = 1'b1;
    end else if ((state_q == STATE_MEMORY) && memory_is_load_q &&
                 dmem_ready_i && !dmem_error_i) begin
      rf_write      = 1'b1;
      rf_write_addr = memory_rd_q;
      rf_write_data = load_result;
    end
  end

  // Native memory-port projections from the registered controller state.
  assign imem_valid_o = (state_q == STATE_FETCH) && (pc_q[1:0] == 2'b00);
  assign imem_addr_o  = pc_q;

  assign dmem_valid_o = (state_q == STATE_MEMORY);
  assign dmem_write_o = (state_q == STATE_MEMORY) && !memory_is_load_q;
  assign dmem_addr_o  = memory_addr_q;
  assign dmem_wdata_o = memory_wdata_q;
  assign dmem_wstrb_o = dmem_write_o ? memory_wstrb_q : 4'b0000;

  assign debug_pc_o    = pc_q;
  assign debug_state_o = state_q;

  // Advance only on accepted memory transactions or completed execute work.
  // Trap state is intentionally sticky and produces no further bus requests.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q              <= STATE_FETCH;
      pc_q                 <= RESET_PC;
      instruction_q        <= 32'h0000_0013; // ADDI x0, x0, 0
      memory_addr_q        <= 32'b0;
      memory_wdata_q       <= 32'b0;
      memory_wstrb_q       <= 4'b0;
      memory_is_load_q     <= 1'b0;
      memory_size_q        <= MEM_WORD;
      memory_unsigned_q    <= 1'b0;
      memory_rd_q          <= 5'b0;
      trap_valid_o         <= 1'b0;
      trap_cause_o         <= 32'b0;
      trap_pc_o            <= 32'b0;
      trap_tval_o          <= 32'b0;
      retire_valid_o       <= 1'b0;
      retire_pc_o          <= 32'b0;
      retire_instruction_o <= 32'b0;
    end else begin
      retire_valid_o <= 1'b0;

      case (state_q)
        STATE_FETCH: begin
          if (pc_q[1:0] != 2'b00) begin
            trap_valid_o <= 1'b1;
            trap_cause_o <= TRAP_INSTR_ADDR_MISALIGNED;
            trap_pc_o    <= pc_q;
            trap_tval_o  <= pc_q;
            state_q      <= STATE_TRAP;
          end else if (imem_ready_i) begin
            if (imem_error_i) begin
              trap_valid_o <= 1'b1;
              trap_cause_o <= TRAP_INSTR_ACCESS_FAULT;
              trap_pc_o    <= pc_q;
              trap_tval_o  <= pc_q;
              state_q      <= STATE_TRAP;
            end else begin
              instruction_q <= imem_rdata_i;
              state_q       <= STATE_EXECUTE;
            end
          end
        end

        STATE_EXECUTE: begin
          if (execute_trap) begin
            trap_valid_o <= 1'b1;
            trap_pc_o    <= pc_q;

            if (!dec_valid) begin
              trap_cause_o <= TRAP_ILLEGAL_INSTRUCTION;
              trap_tval_o  <= instruction_q;
            end else if (dec_ecall) begin
              trap_cause_o <= TRAP_ECALL_MMODE;
              trap_tval_o  <= 32'b0;
            end else if (dec_ebreak) begin
              trap_cause_o <= TRAP_BREAKPOINT;
              trap_tval_o  <= 32'b0;
            end else if (control_target_misaligned) begin
              trap_cause_o <= TRAP_INSTR_ADDR_MISALIGNED;
              trap_tval_o  <= control_target;
            end else if (dec_mem_read) begin
              trap_cause_o <= TRAP_LOAD_ADDR_MISALIGNED;
              trap_tval_o  <= alu_result;
            end else begin
              trap_cause_o <= TRAP_STORE_ADDR_MISALIGNED;
              trap_tval_o  <= alu_result;
            end

            state_q <= STATE_TRAP;
          end else if (dec_mem_read || dec_mem_write) begin
            memory_addr_q     <= alu_result;
            memory_wdata_q    <= store_wdata;
            memory_wstrb_q    <= store_wstrb;
            memory_is_load_q  <= dec_mem_read;
            memory_size_q     <= dec_mem_size;
            memory_unsigned_q <= dec_mem_unsigned;
            memory_rd_q       <= instruction_q[11:7];
            state_q           <= STATE_MEMORY;
          end else begin
            pc_q <= control_transfer_taken ? control_target : (pc_q + 32'd4);
            retire_valid_o       <= 1'b1;
            retire_pc_o          <= pc_q;
            retire_instruction_o <= instruction_q;
            state_q              <= STATE_FETCH;
          end
        end

        STATE_MEMORY: begin
          if (dmem_ready_i) begin
            if (dmem_error_i) begin
              trap_valid_o <= 1'b1;
              trap_cause_o <= memory_is_load_q ? TRAP_LOAD_ACCESS_FAULT
                                               : TRAP_STORE_ACCESS_FAULT;
              trap_pc_o    <= pc_q;
              trap_tval_o  <= memory_addr_q;
              state_q      <= STATE_TRAP;
            end else begin
              pc_q                 <= pc_q + 32'd4;
              retire_valid_o       <= 1'b1;
              retire_pc_o          <= pc_q;
              retire_instruction_o <= instruction_q;
              state_q              <= STATE_FETCH;
            end
          end
        end

        default: begin // STATE_TRAP is intentionally quiet and sticky.
          state_q <= STATE_TRAP;
        end
      endcase
    end
  end

endmodule
