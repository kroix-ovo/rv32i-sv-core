`timescale 1ns/1ps
module tb_board_selftest;
  logic clk = 0;
  logic reset_n = 0;
  wire [15:0] good_led, bad_led, trap_led;
  always #5 clk = ~clk;
  nexys_a7_selftest_top good (.CLK100MHZ(clk), .CPU_RESETN(reset_n), .LED(good_led));
  nexys_a7_100t_top #(.MEM_INIT_FILE("fpga_selftest_bad.hex"), .SELF_TEST(1)) bad
    (.CLK100MHZ(clk), .CPU_RESETN(reset_n), .LED(bad_led));
  nexys_a7_100t_top #(.MEM_INIT_FILE("fpga_selftest_trap.hex"), .SELF_TEST(1)) trapped
    (.CLK100MHZ(clk), .CPU_RESETN(reset_n), .LED(trap_led));
  initial begin
    // Exercise real software pass, comparison failure, and EBREAK trap paths.
    // Repeat reset to check that scratch RAM retained across reset is harmless.
    for (int trial = 0; trial < 5; trial++) begin
      reset_n = 0;
      repeat (3) @(negedge clk);
      if (good_led !== 0 || bad_led !== 0 || trap_led !== 0)
        $fatal(1, "Status did not clear during reset");
      reset_n = 1;
      repeat (2000) @(negedge clk);
      if (good_led[2:0] !== 3'b101 || good.u_board.u_demo.gpio !== 32'h600d600d)
        $fatal(1, "Directed program did not report exact pass signature");
      if (bad_led[2:0] !== 3'b110 || bad.u_demo.gpio !== 32'hbad00001)
        $fatal(1, "Corrupted arithmetic did not report exact failure signature");
      if (trap_led[2:0] !== 3'b110 || !trapped.u_demo.trap_valid)
        $fatal(1, "EBREAK did not report a trap failure");
      if (good_led[15:4] !== 0 || bad_led[15:4] !== 0 || trap_led[15:4] !== 0)
        $fatal(1, "Unused LEDs are active");
    end
    $display("PASS: board self-test pass, injected comparison failure, EBREAK trap, five reset/retests");
    $finish;
  end
endmodule
