`timescale 1ns/1ps

// Couple rv32i_core to a shared synchronous memory and one byte-writable GPIO
// register. The CPU retains separate instruction and data ports while both map
// into the same little-endian word array. MEM_INIT_FILE uses $readmemh format.

module rv32i_soc #(
  parameter integer      MEM_WORDS     = 4096,
  parameter logic [31:0] RESET_PC      = 32'h0000_0000,
  parameter logic [31:0] GPIO_ADDR     = 32'h1000_0000,
  parameter              MEM_INIT_FILE = ""
) (
  // SoC clock/reset and board-visible status.
  input  logic        clk_i,
  input  logic        rst_ni,
  output logic [31:0] gpio_o,
  output logic        trap_valid_o,
  output logic [31:0] trap_cause_o,
  output logic [31:0] trap_pc_o,
  output logic [31:0] debug_pc_o,
  output logic        retire_valid_o
);
  localparam logic [31:0] MEM_BYTES = MEM_WORDS * 4;
  localparam integer MEM_ADDR_W = (MEM_WORDS <= 1) ? 1 : $clog2(MEM_WORDS);

  // Shared instruction/data storage; the attribute requests FPGA block RAM.
  (* ram_style = "block" *) logic [31:0] memory [0:MEM_WORDS-1];

  // Core-native memory ports.
  logic        imem_valid;
  logic [31:0] imem_addr;
  logic        imem_ready;
  logic [31:0] imem_rdata;
  logic        imem_error;

  logic        dmem_valid;
  logic        dmem_write;
  logic [31:0] dmem_addr;
  logic [31:0] dmem_wdata;
  logic [3:0]  dmem_wstrb;
  logic        dmem_ready;
  logic [31:0] dmem_rdata;
  logic        dmem_error;

  logic [31:0] trap_tval_unused;
  logic [31:0] retire_pc_unused;
  logic [31:0] retire_instruction_unused;
  logic [1:0]  debug_state_unused;
  integer byte_index;

  // Simulation and FPGA tools consume the same word-oriented program image.
  initial begin
    if (MEM_INIT_FILE != "")
      $readmemh(MEM_INIT_FILE, memory);
  end

  rv32i_core #(
    .RESET_PC (RESET_PC)
  ) u_core (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),
    .imem_valid_o         (imem_valid),
    .imem_addr_o          (imem_addr),
    .imem_ready_i         (imem_ready),
    .imem_rdata_i         (imem_rdata),
    .imem_error_i         (imem_error),
    .dmem_valid_o         (dmem_valid),
    .dmem_write_o         (dmem_write),
    .dmem_addr_o          (dmem_addr),
    .dmem_wdata_o         (dmem_wdata),
    .dmem_wstrb_o         (dmem_wstrb),
    .dmem_ready_i         (dmem_ready),
    .dmem_rdata_i         (dmem_rdata),
    .dmem_error_i         (dmem_error),
    .trap_valid_o         (trap_valid_o),
    .trap_cause_o         (trap_cause_o),
    .trap_pc_o            (trap_pc_o),
    .trap_tval_o          (trap_tval_unused),
    .retire_valid_o       (retire_valid_o),
    .retire_pc_o          (retire_pc_unused),
    .retire_instruction_o (retire_instruction_unused),
    .debug_pc_o           (debug_pc_o),
    .debug_state_o        (debug_state_unused)
  );

  // The ready registers create a one-cycle response and a one-cycle pulse.
  // Range checks become access-fault inputs to the CPU instead of wrapping.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      imem_ready <= 1'b0;
      imem_rdata <= 32'b0;
      imem_error <= 1'b0;
      dmem_ready <= 1'b0;
      dmem_rdata <= 32'b0;
      dmem_error <= 1'b0;
      gpio_o     <= 32'b0;
    end else begin
      imem_ready <= 1'b0;
      imem_error <= 1'b0;
      dmem_ready <= 1'b0;
      dmem_error <= 1'b0;

      if (imem_valid && !imem_ready) begin
        imem_ready <= 1'b1;
        if ((imem_addr < MEM_BYTES) && (imem_addr[1:0] == 2'b00)) begin
          imem_rdata <= memory[imem_addr[MEM_ADDR_W+1:2]];
        end else begin
          imem_rdata <= 32'b0;
          imem_error <= 1'b1;
        end
      end

      if (dmem_valid && !dmem_ready) begin
        dmem_ready <= 1'b1;

        if (dmem_addr == GPIO_ADDR) begin
          dmem_rdata <= gpio_o;
          if (dmem_write) begin
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
              if (dmem_wstrb[byte_index])
                gpio_o[byte_index*8 +: 8] <= dmem_wdata[byte_index*8 +: 8];
          end
        end else if (dmem_addr < MEM_BYTES) begin
          dmem_rdata <= memory[dmem_addr[MEM_ADDR_W+1:2]];
          if (dmem_write) begin
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
              if (dmem_wstrb[byte_index])
                memory[dmem_addr[MEM_ADDR_W+1:2]][byte_index*8 +: 8]
                  <= dmem_wdata[byte_index*8 +: 8];
          end
        end else begin
          dmem_rdata <= 32'b0;
          dmem_error <= 1'b1;
        end
      end
    end
  end

endmodule
