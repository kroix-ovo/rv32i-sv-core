`timescale 1ns/1ps

// Run the directed ISA program. LD0=pass, LD1=fail/trap, LD2=complete,
// LD3=independent heartbeat. CPU RESET reruns the program.
module nexys_a7_selftest_top (
  input wire CLK100MHZ,
  input wire CPU_RESETN,
  output wire [15:0] LED
);
  nexys_a7_100t_top #(
    .MEM_INIT_FILE ("fpga_selftest.hex"),
    .SELF_TEST     (1'b1)
  ) u_board (
    .CLK100MHZ (CLK100MHZ),
    .CPU_RESETN (CPU_RESETN),
    .LED (LED)
  );
endmodule
