`timescale 1ns/1ps
module tb_board_reset;
  logic clk = 0;
  logic ck_rst = 0;
  wire [3:0] led;
  wire [15:0] nexys_led;
  always #5 clk = ~clk;
  arty_a7_100t_top dut (.CLK100MHZ(clk), .ck_rst(ck_rst), .led(led));
  nexys_a7_100t_top nexys (.CLK100MHZ(clk), .CPU_RESETN(ck_rst), .LED(nexys_led));
  always @(negedge clk) begin
    if (nexys_led[15:4] !== 0 || nexys_led[3:0] !== led)
      $fatal(1, "Nexys LED adapter differs from shared board logic");
  end
  initial begin
    // The red button pulls C2 low; hold it through startup.
    repeat (3) @(negedge clk);
    if (dut.rst_n !== 0 || led !== 0) $fatal(1, "Reset did not assert");
    ck_rst = 1;
    @(negedge clk);
    if (dut.rst_n !== 0) $fatal(1, "Reset released before two edges");
    @(negedge clk);
    if (dut.rst_n !== 1) $fatal(1, "Reset did not release after two edges");
    repeat (200) @(negedge clk);
    if (led[0] !== 1 || led[1] !== 0)
      $fatal(1, "Software did not reach first GPIO write without trap");
    #2 ck_rst = 0;
    #1;
    if (dut.rst_n !== 0 || dut.heartbeat_q !== 0 || led !== 0)
      $fatal(1, "Button press did not asynchronously reset board state");
    repeat (3) @(negedge clk);
    ck_rst = 1;
    repeat (202) @(negedge clk);
    if (dut.rst_n !== 1 || led[0] !== 1 || led[1] !== 0)
      $fatal(1, "Software did not restart after button release");
    $display("PASS: active-low board reset, synchronized release, GPIO startup and restart");
    $finish;
  end
endmodule
