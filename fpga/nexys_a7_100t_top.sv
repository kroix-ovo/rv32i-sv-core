`timescale 1ns/1ps

// The Nexys uses the same 100 MHz demo logic and active-low reset behavior.
// Its separate constraints map CPU_RESETN and the sixteen user LEDs.
module nexys_a7_100t_top #(
  parameter MEM_INIT_FILE = "fpga_demo.hex",
  parameter bit SELF_TEST = 1'b0
) (
  input  logic        CLK100MHZ,
  input  logic        CPU_RESETN,
  output wire [15:0]  LED
);
  arty_a7_100t_top #(
    .MEM_INIT_FILE (MEM_INIT_FILE),
    .SELF_TEST     (SELF_TEST)
  ) u_demo (
    .CLK100MHZ (CLK100MHZ),
    .ck_rst    (CPU_RESETN),
    .led       (LED[3:0])
  );
  assign LED[15:4] = 12'b0;
endmodule
