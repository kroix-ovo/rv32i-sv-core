`timescale 1ns/1ps

// XSim UVM test top. The test owns reset and memory contents through the
// virtual interface; this module only wires the synthesizable core to it.
module tb_core_uvm;
  import uvm_pkg::*;
  import rv32i_uvm_pkg::*;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  rv32i_core_if bus(clk);

  rv32i_core dut (
    .clk_i(clk), .rst_ni(bus.rst_n),
    .imem_valid_o(bus.imem_valid), .imem_addr_o(bus.imem_addr),
    .imem_ready_i(bus.imem_ready), .imem_rdata_i(bus.imem_rdata),
    .imem_error_i(bus.imem_error),
    .dmem_valid_o(bus.dmem_valid), .dmem_write_o(bus.dmem_write),
    .dmem_addr_o(bus.dmem_addr), .dmem_wdata_o(bus.dmem_wdata),
    .dmem_wstrb_o(bus.dmem_wstrb), .dmem_ready_i(bus.dmem_ready),
    .dmem_rdata_i(bus.dmem_rdata), .dmem_error_i(bus.dmem_error),
    .trap_valid_o(bus.trap_valid), .trap_cause_o(bus.trap_cause),
    .trap_pc_o(bus.trap_pc), .trap_tval_o(bus.trap_tval),
    .retire_valid_o(bus.retire_valid), .retire_pc_o(bus.retire_pc),
    .retire_instruction_o(bus.retire_instruction),
    .debug_pc_o(bus.debug_pc), .debug_state_o(bus.debug_state)
  );
  assign bus.raw_stall = dut.if_valid_q && dut.dependency;
  assign bus.load_use_stall = bus.raw_stall &&
      ((dut.id_valid_q && dut.id_q.mem_read) ||
       (dut.ex_valid_q && dut.ex_q.mem_read) ||
       (dut.wb_valid_q && dut.wb_q.instruction[6:0] == 7'h03));

  initial begin
    bus.rst_n = 0;
    bus.imem_ready = 0;
    bus.imem_rdata = 0;
    bus.imem_error = 0;
    bus.dmem_ready = 0;
    bus.dmem_rdata = 0;
    bus.dmem_error = 0;
    uvm_config_db#(virtual rv32i_core_if)::set(null, "*", "vif", bus);
    run_test("rv32i_uvm_test");
  end
endmodule
