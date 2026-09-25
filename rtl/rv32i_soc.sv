`timescale 1ns/1ps

// Couple rv32i_core to a shared synchronous memory and one byte-writable GPIO
// register. The CPU retains separate instruction and data ports while both map
// into the same little-endian word array. MEM_INIT_FILE uses $readmemh format.
// A request sampled on one rising edge produces ready and data for the next
// edge. The core must keep its request stable until it sees that ready. Byte
// strobes let a store change one or two bytes without changing nearby bytes.

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
  logic [31:0] ram_dmem_rdata_q;
  logic [31:0] gpio_rdata_q;
  logic        dmem_gpio_response_q;

  logic [31:0] trap_tval_unused;
  logic [31:0] retire_pc_unused;
  logic [31:0] retire_instruction_unused;
  logic [1:0]  debug_state_unused;
  integer gpio_byte_index;
  integer ram_byte_index;

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

  // The two clocked blocks below describe two physical RAM ports. Port A
  // reads instructions. Port B reads data and writes selected byte lanes.
  // Neither port has an asynchronous reset: block RAM cannot reset all its
  // stored words at once. The program image initializes those words, and the
  // core looks at read data only when the matching ready pulse is high.
  // Keeping each read output directly registered follows Vivado's block-RAM
  // inference pattern and avoids a large distributed-RAM implementation.
  always_ff @(posedge clk_i) begin
    if (imem_valid && !imem_ready &&
        (imem_addr < MEM_BYTES) && (imem_addr[1:0] == 2'b00))
      imem_rdata <= memory[imem_addr[MEM_ADDR_W+1:2]];
  end

  always_ff @(posedge clk_i) begin
    if (dmem_valid && !dmem_ready && (dmem_addr < MEM_BYTES)) begin
      if (dmem_write) begin
        for (ram_byte_index = 0; ram_byte_index < 4;
             ram_byte_index = ram_byte_index + 1)
          if (dmem_wstrb[ram_byte_index])
            memory[dmem_addr[MEM_ADDR_W+1:2]][ram_byte_index*8 +: 8]
              <= dmem_wdata[ram_byte_index*8 +: 8];
      end
      ram_dmem_rdata_q <= memory[dmem_addr[MEM_ADDR_W+1:2]];
    end
  end

  // GPIO is outside RAM. Capture its read value at the request edge, then
  // select it during the same ready cycle used by normal data-memory reads.
  always_ff @(posedge clk_i) begin
    if (dmem_valid && !dmem_ready) begin
      dmem_gpio_response_q <= (dmem_addr == GPIO_ADDR);
      gpio_rdata_q <= gpio_o;
    end
  end
  assign dmem_rdata = dmem_gpio_response_q ? gpio_rdata_q : ram_dmem_rdata_q;

  // Only control/status registers reset. They say when the registered data
  // above is meaningful and turn out-of-range accesses into bus faults.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      imem_ready <= 1'b0;
      imem_error <= 1'b0;
      dmem_ready <= 1'b0;
      dmem_error <= 1'b0;
      gpio_o     <= 32'b0;
    end else begin
      imem_ready <= 1'b0;
      imem_error <= 1'b0;
      dmem_ready <= 1'b0;
      dmem_error <= 1'b0;

      if (imem_valid && !imem_ready) begin
        imem_ready <= 1'b1;
        if ((imem_addr >= MEM_BYTES) || (imem_addr[1:0] != 2'b00)) begin
          imem_error <= 1'b1;
        end
      end

      if (dmem_valid && !dmem_ready) begin
        dmem_ready <= 1'b1;

        if (dmem_addr == GPIO_ADDR) begin
          if (dmem_write) begin
            for (gpio_byte_index = 0; gpio_byte_index < 4;
                 gpio_byte_index = gpio_byte_index + 1)
              if (dmem_wstrb[gpio_byte_index])
                gpio_o[gpio_byte_index*8 +: 8]
                  <= dmem_wdata[gpio_byte_index*8 +: 8];
          end
        end else if (dmem_addr >= MEM_BYTES) begin
          dmem_error <= 1'b1;
        end
      end
    end
  end

endmodule
