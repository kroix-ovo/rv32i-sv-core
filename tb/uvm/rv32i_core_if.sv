`timescale 1ns/1ps

// UVM drives only memory responses. All requests and architectural results are
// observed at the public core boundary; no pipeline register is forced.
interface rv32i_core_if(input logic clk);
  logic rst_n;
  logic imem_valid, imem_ready, imem_error;
  logic [31:0] imem_addr, imem_rdata;
  logic dmem_valid, dmem_write, dmem_ready, dmem_error;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  logic [3:0] dmem_wstrb;
  logic trap_valid, retire_valid;
  logic [31:0] trap_cause, trap_pc, trap_tval;
  logic [31:0] retire_pc, retire_instruction;
  logic [31:0] debug_pc;
  logic [1:0] debug_state;
  // Observation only: these taps prove that the intended pipeline stalls
  // occurred. Scoreboard correctness checks still use public core ports.
  logic raw_stall, load_use_stall;

  clocking drive_cb @(negedge clk);
    output imem_ready, imem_rdata, imem_error;
    output dmem_ready, dmem_rdata, dmem_error;
  endclocking
endinterface
