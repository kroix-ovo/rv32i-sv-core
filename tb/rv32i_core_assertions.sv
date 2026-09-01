`timescale 1ns/1ps

// Monitor the core boundary for ready/valid stability, aligned fetches,
// mutually exclusive ports, legal store strobes, and sticky traps. The bind at
// the end attaches this simulation-only checker to every rv32i_core instance.

module rv32i_core_assertions (
  // Sampled core interface signals; this monitor drives no DUT signal.
  input logic        clk_i,
  input logic        rst_ni,
  input logic        imem_valid_i,
  input logic        imem_ready_i,
  input logic [31:0] imem_addr_i,
  input logic        dmem_valid_i,
  input logic        dmem_ready_i,
  input logic        dmem_write_i,
  input logic [31:0] dmem_addr_i,
  input logic [31:0] dmem_wdata_i,
  input logic [3:0]  dmem_wstrb_i,
  input logic        trap_valid_i
);
  default clocking monitor_clock @(posedge clk_i); endclocking
  default disable iff (!rst_ni);

  property p_instruction_request_stable;
    imem_valid_i && !imem_ready_i |=> imem_valid_i && $stable(imem_addr_i);
  endproperty
  assert property (p_instruction_request_stable);

  property p_data_request_stable;
    dmem_valid_i && !dmem_ready_i |=> dmem_valid_i &&
      $stable({dmem_write_i, dmem_addr_i, dmem_wdata_i, dmem_wstrb_i});
  endproperty
  assert property (p_data_request_stable);

  assert property (imem_valid_i |-> (imem_addr_i[1:0] == 2'b00));
  assert property (!(imem_valid_i && dmem_valid_i));
  assert property (dmem_write_i |-> (|dmem_wstrb_i));
  assert property (trap_valid_i |=> trap_valid_i);
endmodule

// Binding keeps verification code outside the synthesizable core. Every core
// instance in an assertion-capable simulation receives one monitor.
bind rv32i_core rv32i_core_assertions u_bound_core_assertions (
  .clk_i         (clk_i),
  .rst_ni        (rst_ni),
  .imem_valid_i  (imem_valid_o),
  .imem_ready_i  (imem_ready_i),
  .imem_addr_i   (imem_addr_o),
  .dmem_valid_i  (dmem_valid_o),
  .dmem_ready_i  (dmem_ready_i),
  .dmem_write_i  (dmem_write_o),
  .dmem_addr_i   (dmem_addr_o),
  .dmem_wdata_i  (dmem_wdata_o),
  .dmem_wstrb_i  (dmem_wstrb_o),
  .trap_valid_i  (trap_valid_o)
);
