`timescale 1ns/1ps

// Adapt the teaching SoC to the Arty A7-100T clock, reset button, and four LEDs.
// LED[0] is software GPIO, LED[1] reports a trap, LED[2] samples the PC, and
// LED[3] is a hardware heartbeat independent of CPU progress.

module arty_a7_100t_top (
  // Digilent board clock, active-high reset button, and discrete LEDs.
  input  logic       CLK100MHZ,
  input  logic       ck_rst,
  output logic [3:0] led
);
  logic [1:0]  reset_sync_q;
  logic        rst_n;
  logic [31:0] gpio;
  logic        trap_valid;
  logic [31:0] trap_cause_unused;
  logic [31:0] trap_pc_unused;
  logic [31:0] debug_pc;
  logic        retire_unused;
  logic [25:0] heartbeat_q;

  // Assert reset immediately. Release it only after two clean clock edges.
  always_ff @(posedge CLK100MHZ or posedge ck_rst) begin
    if (ck_rst)
      reset_sync_q <= 2'b00;
    else
      reset_sync_q <= {reset_sync_q[0], 1'b1};
  end
  assign rst_n = reset_sync_q[1];

  always_ff @(posedge CLK100MHZ or negedge rst_n) begin
    if (!rst_n)
      heartbeat_q <= 26'b0;
    else
      heartbeat_q <= heartbeat_q + 1'b1;
  end

  rv32i_soc #(
    .MEM_WORDS     (4096),
    .MEM_INIT_FILE ("fpga_demo.hex")
  ) u_soc (
    .clk_i          (CLK100MHZ),
    .rst_ni         (rst_n),
    .gpio_o         (gpio),
    .trap_valid_o   (trap_valid),
    .trap_cause_o   (trap_cause_unused),
    .trap_pc_o      (trap_pc_unused),
    .debug_pc_o     (debug_pc),
    .retire_valid_o (retire_unused)
  );

  always_comb begin
    led[0] = gpio[0];
    led[1] = trap_valid;
    led[2] = debug_pc[4];
    led[3] = heartbeat_q[25];
  end
endmodule
