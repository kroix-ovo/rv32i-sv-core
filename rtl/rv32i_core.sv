`timescale 1ns/1ps

// Five-stage in-order RV32I core: IF, ID, EX, MEM, WB.
//
// Read this module as one instruction moving through four register boundaries.
// IF asks instruction memory for the word at fetch_pc_q. A response enters
// if_instruction_q. ID decodes that word and reads its source registers into
// id_q. EX computes an ALU value, address, or branch target into ex_q. MEM
// finishes a load/store and puts the final value into wb_q. WB writes the
// register file and reports retirement (the instruction's completion).
//
// A stage's valid bit says whether its stored fields belong to a real
// instruction. The fields may keep old bits when valid is zero; those bits
// must never cause a register write, memory request, or retirement.
// always_ff updates stage registers at a rising clock edge. Its nonblocking
// assignments (<=) all read the OLD stage values, so stages can move together.
//
// This baseline has no forwarding. For example, ADD x3,x1,x2 waits in ID
// while an older instruction is still going to write x1 or x2. A data-memory
// wait holds younger stages. A branch pauses fetch until EX knows the target.
// A fault removes younger instructions, lets older ones finish, and then
// publishes a sticky trap record. The core has no CSRs, interrupts, caches,
// compressed instructions, or multiply/divide extension.
module rv32i_core #(
  parameter logic [31:0] RESET_PC = 32'h0000_0000
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  output logic        imem_valid_o,
  output logic [31:0] imem_addr_o,
  input  logic        imem_ready_i,
  input  logic [31:0] imem_rdata_i,
  input  logic        imem_error_i,
  output logic        dmem_valid_o,
  output logic        dmem_write_o,
  output logic [31:0] dmem_addr_o,
  output logic [31:0] dmem_wdata_o,
  output logic [3:0]  dmem_wstrb_o,
  input  logic        dmem_ready_i,
  input  logic [31:0] dmem_rdata_i,
  input  logic        dmem_error_i,
  output logic        trap_valid_o,
  output logic [31:0] trap_cause_o,
  output logic [31:0] trap_pc_o,
  output logic [31:0] trap_tval_o,
  output logic        retire_valid_o,
  output logic [31:0] retire_pc_o,
  output logic [31:0] retire_instruction_o,
  output logic [31:0] debug_pc_o,
  output logic [1:0]  debug_state_o
);
  import rv32i_pkg::*;

  // Packed structs group the bits that cross each stage boundary. They are
  // ordinary flip-flops after synthesis, not software objects.
  typedef struct packed {
    logic [31:0] pc, instruction, rs1, rs2, imm;
    logic [4:0] rd;
    alu_op_t alu_op;
    logic lhs_pc, lhs_zero, rhs_imm, reg_write, mem_read, mem_write;
    wb_sel_t wb_sel;
    mem_size_t mem_size;
    logic mem_unsigned;
    branch_op_t branch_op;
    logic jump, jalr, ecall, ebreak, fence, legal;
  } id_ex_t;

  typedef struct packed {
    logic [31:0] pc, instruction, result, addr, wdata;
    logic [3:0] wstrb;
    logic [4:0] rd;
    logic reg_write, mem_read, mem_write;
    mem_size_t mem_size;
    logic mem_unsigned;
  } ex_mem_t;

  typedef struct packed {
    logic [31:0] pc, instruction, result;
    logic [4:0] rd;
    logic reg_write;
  } mem_wb_t;

  // The _q suffix means a value held in a clocked register. These four valid
  // bits correspond to IF/ID, ID/EX, EX/MEM, and MEM/WB respectively.
  logic [31:0] fetch_pc_q, if_pc_q, if_instruction_q;
  logic if_valid_q, id_valid_q, ex_valid_q, wb_valid_q;
  id_ex_t id_q;
  ex_mem_t ex_q;
  mem_wb_t wb_q;
  // A pending fault remembers the cause while older stages drain. The
  // external trap outputs change only after those stages are empty.
  logic fault_pending_q;
  logic [31:0] fault_cause_q, fault_pc_q, fault_tval_q;

  logic dec_valid, dec_lhs_pc, dec_lhs_zero, dec_rhs_imm;
  logic dec_reg_write, dec_mem_read, dec_mem_write, dec_unsigned;
  logic dec_jump, dec_jalr, dec_ecall, dec_ebreak, dec_fence;
  alu_op_t dec_alu_op;
  imm_sel_t dec_imm_sel;
  wb_sel_t dec_wb_sel;
  mem_size_t dec_mem_size;
  branch_op_t dec_branch_op;
  logic [31:0] dec_imm, rs1_data, rs2_data;
  logic uses_rs1, uses_rs2, dependency, control_inflight;
  logic mem_wait, mem_fault, ex_fault, ex_branch_taken;
  logic [31:0] alu_lhs, alu_rhs, alu_result, control_target;
  logic [31:0] ex_result, store_wdata, load_shifted, load_result;
  logic [3:0] store_wstrb;
  logic target_misaligned, address_misaligned;
  logic [31:0] ex_fault_cause, ex_fault_tval;
  logic issue_id, accept_fetch, advance_pipe;

  // Decode and register-file reads are combinational: they reflect the
  // instruction currently waiting in IF/ID without consuming a clock edge.
  rv32i_decoder u_decoder (
    .instruction_i(if_instruction_q), .valid_o(dec_valid),
    .alu_op_o(dec_alu_op), .imm_sel_o(dec_imm_sel),
    .alu_lhs_pc_o(dec_lhs_pc), .alu_lhs_zero_o(dec_lhs_zero),
    .alu_rhs_imm_o(dec_rhs_imm), .reg_write_o(dec_reg_write),
    .wb_sel_o(dec_wb_sel), .mem_read_o(dec_mem_read),
    .mem_write_o(dec_mem_write), .mem_size_o(dec_mem_size),
    .mem_unsigned_o(dec_unsigned), .branch_op_o(dec_branch_op),
    .jump_o(dec_jump), .jalr_o(dec_jalr), .ecall_o(dec_ecall),
    .ebreak_o(dec_ebreak), .fence_o(dec_fence)
  );
  rv32i_imm_gen u_imm_gen (
    .instruction_i(if_instruction_q), .select_i(dec_imm_sel),
    .immediate_o(dec_imm)
  );
  rv32i_regfile u_regfile (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .rs1_addr_i(if_instruction_q[19:15]),
    .rs2_addr_i(if_instruction_q[24:20]),
    .rs1_data_o(rs1_data), .rs2_data_o(rs2_data),
    .rd_write_i(wb_valid_q && wb_q.reg_write && !trap_valid_o),
    .rd_addr_i(wb_q.rd), .rd_data_i(wb_q.result)
  );

  // Only architecturally used sources take part in RAW (read-after-write)
  // interlocks. The immediate field of ADDI looks like rs2 bits, but ADDI
  // does not actually read rs2 and must not stall for that apparent match.
  always_comb begin
    uses_rs1 = 1'b0;
    uses_rs2 = 1'b0;
    case (if_instruction_q[6:0])
      7'b1100111, 7'b0000011, 7'b0010011: uses_rs1 = 1'b1;
      7'b1100011, 7'b0100011, 7'b0110011: begin
        uses_rs1 = 1'b1;
        uses_rs2 = 1'b1;
      end
      default: ;
    endcase
  end
  // Any older uncommitted writer of either source holds the instruction in
  // IF/ID. x0 is excluded because writes to x0 have no architectural effect.
  assign dependency =
      (uses_rs1 && (if_instruction_q[19:15] != 5'd0) &&
       ((id_valid_q && id_q.reg_write && id_q.rd == if_instruction_q[19:15]) ||
        (ex_valid_q && ex_q.reg_write && ex_q.rd == if_instruction_q[19:15]) ||
        (wb_valid_q && wb_q.reg_write && wb_q.rd == if_instruction_q[19:15]))) ||
      (uses_rs2 && (if_instruction_q[24:20] != 5'd0) &&
       ((id_valid_q && id_q.reg_write && id_q.rd == if_instruction_q[24:20]) ||
        (ex_valid_q && ex_q.reg_write && ex_q.rd == if_instruction_q[24:20]) ||
        (wb_valid_q && wb_q.reg_write && wb_q.rd == if_instruction_q[24:20])));

  // Fetch pauses at a control instruction, memory operation, fault candidate,
  // or FENCE. The memory interface cannot cancel a request once valid is high,
  // so this rule also prevents a later stall or redirect from withdrawing it.
  assign control_inflight =
      (if_valid_q && (dec_branch_op != BR_NONE || dec_jump || dec_jalr || dec_fence)) ||
      (id_valid_q && (id_q.branch_op != BR_NONE || id_q.jump || id_q.jalr || id_q.fence)) ||
      (if_valid_q && (dec_mem_read || dec_mem_write || !dec_valid ||
                      dec_ecall || dec_ebreak)) ||
      (id_valid_q && (id_q.mem_read || id_q.mem_write || !id_q.legal ||
                      id_q.ecall || id_q.ebreak)) ||
      (ex_valid_q && (ex_q.mem_read || ex_q.mem_write)) ||
      (ex_valid_q && ex_q.instruction[6:0] == 7'b0001111) ||
      (wb_valid_q && wb_q.instruction[6:0] == 7'b0001111);
  // A data transfer completes only when valid and ready meet on a clock edge.
  // Until then, EX/MEM keeps the same address, data, direction, and byte mask.
  assign mem_wait = ex_valid_q && (ex_q.mem_read || ex_q.mem_write) && !dmem_ready_i;
  assign mem_fault = ex_valid_q && (ex_q.mem_read || ex_q.mem_write) &&
                     dmem_ready_i && dmem_error_i;
  assign advance_pipe = !mem_wait && !trap_valid_o;
  // A faulting older instruction overrides the stage-valid assignments at
  // the clock edge below. Its instruction type already blocks fetch, so ID
  // need not wait for the full EX fault calculation to decide whether the
  // IF/ID slot could be consumed. This shortens the fetch-PC enable path.
  assign issue_id = if_valid_q && !dependency && advance_pipe &&
                    !fault_pending_q;
  // The IF/ID slot may be replaced on the same edge that ID consumes it.
  // When ready stays low, fetch_pc_q does not change, so the request address
  // remains fixed. A successful fetch advances the PC by four bytes.
  assign imem_valid_o = rst_ni && (!if_valid_q || issue_id) && !control_inflight &&
                        !fault_pending_q && !trap_valid_o &&
                        (fetch_pc_q[1:0] == 2'b00);
  assign imem_addr_o = fetch_pc_q;
  assign accept_fetch = imem_valid_o && imem_ready_i;

  // EX selects ALU operands from values captured by ID. LUI uses zero,
  // AUIPC uses the instruction PC, and most operations use rs1.
  assign alu_lhs = id_q.lhs_zero ? 32'b0 : id_q.lhs_pc ? id_q.pc : id_q.rs1;
  assign alu_rhs = id_q.rhs_imm ? id_q.imm : id_q.rs2;
  rv32i_alu u_alu (
    .lhs_i(alu_lhs), .rhs_i(alu_rhs), .op_i(id_q.alu_op),
    .result_o(alu_result)
  );

  always_comb begin
    case (id_q.branch_op)
      BR_EQ: ex_branch_taken = (id_q.rs1 == id_q.rs2);
      BR_NE: ex_branch_taken = (id_q.rs1 != id_q.rs2);
      BR_LT: ex_branch_taken = ($signed(id_q.rs1) < $signed(id_q.rs2));
      BR_GE: ex_branch_taken = ($signed(id_q.rs1) >= $signed(id_q.rs2));
      BR_LTU: ex_branch_taken = (id_q.rs1 < id_q.rs2);
      BR_GEU: ex_branch_taken = (id_q.rs1 >= id_q.rs2);
      default: ex_branch_taken = 1'b0;
    endcase
  end
  // JALR clears bit 0 as required by RV32I. With no compressed instructions,
  // bit 1 must also be zero or the target causes an alignment trap.
  assign control_target = id_q.jalr ? ((id_q.rs1 + id_q.imm) & 32'hffff_fffe)
                                   : (id_q.pc + id_q.imm);
  assign target_misaligned =
      (id_q.jump || id_q.jalr ||
       (id_q.branch_op != BR_NONE && ex_branch_taken)) &&
      (control_target[1:0] != 2'b00);
  always_comb begin
    case (id_q.mem_size)
      MEM_BYTE: address_misaligned = 1'b0;
      MEM_HALF: address_misaligned = alu_result[0];
      default:  address_misaligned = |alu_result[1:0];
    endcase
  end
  assign ex_fault = id_valid_q && (!id_q.legal || id_q.ecall || id_q.ebreak ||
                    target_misaligned ||
                    ((id_q.mem_read || id_q.mem_write) && address_misaligned));
  always_comb begin
    ex_fault_cause = TRAP_ILLEGAL_INSTRUCTION;
    ex_fault_tval = id_q.instruction;
    if (id_q.legal) begin
      if (id_q.ecall) begin
        ex_fault_cause = TRAP_ECALL_MMODE;
        ex_fault_tval = 32'b0;
      end else if (id_q.ebreak) begin
        ex_fault_cause = TRAP_BREAKPOINT;
        ex_fault_tval = 32'b0;
      end else if (target_misaligned) begin
        ex_fault_cause = TRAP_INSTR_ADDR_MISALIGNED;
        ex_fault_tval = control_target;
      end else if (id_q.mem_read) begin
        ex_fault_cause = TRAP_LOAD_ADDR_MISALIGNED;
        ex_fault_tval = alu_result;
      end else begin
        ex_fault_cause = TRAP_STORE_ADDR_MISALIGNED;
        ex_fault_tval = alu_result;
      end
    end
  end
  // Jumps write the return address (PC+4); ALU instructions write the ALU
  // result. Loads replace this provisional value when MEM receives data.
  assign ex_result = id_q.wb_sel == WB_PC_PLUS_4 ?
                     id_q.pc + 32'd4 : alu_result;
  // A store broadcasts its low byte or halfword across the 32-bit bus.
  // wstrb selects the addressed lanes, so untouched bytes keep their value.
  always_comb begin
    case (id_q.mem_size)
      MEM_BYTE: begin
        store_wdata = {4{id_q.rs2[7:0]}};
        store_wstrb = 4'b0001 << alu_result[1:0];
      end
      MEM_HALF: begin
        store_wdata = {2{id_q.rs2[15:0]}};
        store_wstrb = 4'b0011 << alu_result[1:0];
      end
      default: begin
        store_wdata = id_q.rs2;
        store_wstrb = 4'b1111;
      end
    endcase
  end

  // Project the EX/MEM register onto the data-memory request pins. This
  // register boundary is why a stalled request does not change underneath
  // the memory agent.
  assign dmem_valid_o = ex_valid_q && (ex_q.mem_read || ex_q.mem_write) &&
                        !trap_valid_o;
  assign dmem_write_o = dmem_valid_o && ex_q.mem_write;
  assign dmem_addr_o = ex_q.addr;
  assign dmem_wdata_o = ex_q.wdata;
  assign dmem_wstrb_o = dmem_write_o ? ex_q.wstrb : 4'b0;
  // Memory returns the containing aligned word. Shift the addressed byte or
  // halfword down, then either sign-extend or zero-extend it to 32 bits.
  assign load_shifted = dmem_rdata_i >> {ex_q.addr[1:0], 3'b000};
  always_comb begin
    case (ex_q.mem_size)
      MEM_BYTE: load_result = ex_q.mem_unsigned ?
        {24'b0, load_shifted[7:0]} :
        {{24{load_shifted[7]}}, load_shifted[7:0]};
      MEM_HALF: load_result = ex_q.mem_unsigned ?
        {16'b0, load_shifted[15:0]} :
        {{16{load_shifted[15]}}, load_shifted[15:0]};
      default: load_result = dmem_rdata_i;
    endcase
  end

  assign debug_pc_o = fetch_pc_q;
  // 0: flowing, 1: dependency/serialization, 2: memory wait, 3: trap.
  assign debug_state_o = trap_valid_o ? 2'd3 :
                         mem_wait ? 2'd2 :
                         (if_valid_q && (dependency || control_inflight)) ? 2'd1 :
                         2'd0;

  // All stage movement happens here. Reset clears valid bits and sets stage
  // registers to known values so simulation waveforms are easy to read.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      fetch_pc_q <= RESET_PC;
      if_pc_q <= 32'b0;
      if_instruction_q <= 32'h0000_0013;
      if_valid_q <= 1'b0;
      id_q <= '0;
      id_valid_q <= 1'b0;
      ex_q <= '0;
      ex_valid_q <= 1'b0;
      wb_q <= '0;
      wb_valid_q <= 1'b0;
      fault_pending_q <= 1'b0;
      fault_cause_q <= 32'b0;
      fault_pc_q <= 32'b0;
      fault_tval_q <= 32'b0;
      trap_valid_o <= 1'b0;
      trap_cause_o <= 32'b0;
      trap_pc_o <= 32'b0;
      trap_tval_o <= 32'b0;
      retire_valid_o <= 1'b0;
      retire_pc_o <= 32'b0;
      retire_instruction_o <= 32'b0;
    end else begin
      retire_valid_o <= 1'b0;
      // WB is allowed to retire once even while MEM holds younger stages.
      // Clearing wb_valid_q first prevents the same instruction from retiring
      // again on every cycle of a long memory wait.
      wb_valid_q <= 1'b0;
      if (wb_valid_q && !trap_valid_o) begin
        retire_valid_o <= 1'b1;
        retire_pc_o <= wb_q.pc;
        retire_instruction_o <= wb_q.instruction;
      end

      // Once every older stage is empty, the saved fault becomes visible.
      // Trap remains high until reset because the trapped branch below does
      // not issue fetches or move stages.
      if (fault_pending_q && !wb_valid_q && !ex_valid_q && !id_valid_q) begin
        trap_valid_o <= 1'b1;
        trap_cause_o <= fault_cause_q;
        trap_pc_o <= fault_pc_q;
        trap_tval_o <= fault_tval_q;
        fault_pending_q <= 1'b0;
      end else if (!trap_valid_o) begin
        if (advance_pipe) begin
          // MEM either completes a bus transfer or passes a non-memory result
          // through. Nonblocking assignments use the OLD ex_q and id_q here.
          wb_valid_q <= ex_valid_q && !mem_fault;
          if (ex_valid_q && !mem_fault) begin
            wb_q.pc <= ex_q.pc;
            wb_q.instruction <= ex_q.instruction;
            wb_q.rd <= ex_q.rd;
            wb_q.reg_write <= ex_q.reg_write;
            wb_q.result <= ex_q.mem_read ? load_result : ex_q.result;
          end
          ex_valid_q <= id_valid_q && !ex_fault && !mem_fault;
          // A control instruction has already stopped fetch. Updating the
          // target also on a fault is harmless: fault_pending_q blocks any
          // later request, while the saved trap record keeps the fault PC.
          // This keeps the ALU alignment check off the fetch-PC enable path.
          if (id_valid_q && (id_q.jump || id_q.jalr ||
              (id_q.branch_op != BR_NONE && ex_branch_taken)))
            fetch_pc_q <= control_target;
          if (id_valid_q && !ex_fault && !mem_fault) begin
            ex_q.pc <= id_q.pc;
            ex_q.instruction <= id_q.instruction;
            ex_q.result <= ex_result;
            ex_q.addr <= alu_result;
            ex_q.wdata <= store_wdata;
            ex_q.wstrb <= store_wstrb;
            ex_q.rd <= id_q.rd;
            ex_q.reg_write <= id_q.reg_write;
            ex_q.mem_read <= id_q.mem_read;
            ex_q.mem_write <= id_q.mem_write;
            ex_q.mem_size <= id_q.mem_size;
            ex_q.mem_unsigned <= id_q.mem_unsigned;
          end

          // A dependency inserts a bubble into ID/EX but keeps IF/ID intact.
          // Once the writer retires, the register file supplies the new value.
          id_valid_q <= issue_id;
          if (issue_id) begin
            id_q.pc <= if_pc_q;
            id_q.instruction <= if_instruction_q;
            id_q.rs1 <= rs1_data;
            id_q.rs2 <= rs2_data;
            id_q.imm <= dec_imm;
            id_q.rd <= if_instruction_q[11:7];
            id_q.alu_op <= dec_alu_op;
            id_q.lhs_pc <= dec_lhs_pc;
            id_q.lhs_zero <= dec_lhs_zero;
            id_q.rhs_imm <= dec_rhs_imm;
            id_q.reg_write <= dec_reg_write;
            id_q.mem_read <= dec_mem_read;
            id_q.mem_write <= dec_mem_write;
            id_q.wb_sel <= dec_wb_sel;
            id_q.mem_size <= dec_mem_size;
            id_q.mem_unsigned <= dec_unsigned;
            id_q.branch_op <= dec_branch_op;
            id_q.jump <= dec_jump;
            id_q.jalr <= dec_jalr;
            id_q.ecall <= dec_ecall;
            id_q.ebreak <= dec_ebreak;
            id_q.fence <= dec_fence;
            id_q.legal <= dec_valid;
          end
          // Two assignments to if_valid_q on one edge are intentional:
          // a simultaneous accepted fetch replaces the issued instruction.
          if (issue_id) if_valid_q <= 1'b0;
          if (accept_fetch && !imem_error_i) begin
            if_valid_q <= 1'b1;
            if_pc_q <= fetch_pc_q;
            if_instruction_q <= imem_rdata_i;
            fetch_pc_q <= fetch_pc_q + 32'd4;
          end
        end

        // Oldest fault wins. A data fault squashes EX and ID. An EX fault
        // leaves the older MEM result in WB; a fetch fault drains all stages.
        // No faulting instruction is copied to WB or counted as retired.
        if (mem_fault) begin
          fault_pending_q <= 1'b1;
          fault_cause_q <= ex_q.mem_read ? TRAP_LOAD_ACCESS_FAULT :
                                             TRAP_STORE_ACCESS_FAULT;
          fault_pc_q <= ex_q.pc;
          fault_tval_q <= ex_q.addr;
          ex_valid_q <= 1'b0;
          id_valid_q <= 1'b0;
          if_valid_q <= 1'b0;
        end else if (ex_fault && !mem_wait) begin
          fault_pending_q <= 1'b1;
          fault_cause_q <= ex_fault_cause;
          fault_pc_q <= id_q.pc;
          fault_tval_q <= ex_fault_tval;
          id_valid_q <= 1'b0;
          if_valid_q <= 1'b0;
        end else if (!fault_pending_q && fetch_pc_q[1:0] != 2'b00 && !if_valid_q &&
                     !control_inflight && !mem_wait) begin
          fault_pending_q <= 1'b1;
          fault_cause_q <= TRAP_INSTR_ADDR_MISALIGNED;
          fault_pc_q <= fetch_pc_q;
          fault_tval_q <= fetch_pc_q;
        end else if (!fault_pending_q && accept_fetch && imem_error_i) begin
          fault_pending_q <= 1'b1;
          fault_cause_q <= TRAP_INSTR_ACCESS_FAULT;
          fault_pc_q <= fetch_pc_q;
          fault_tval_q <= fetch_pc_q;
        end
      end
    end
  end
endmodule
