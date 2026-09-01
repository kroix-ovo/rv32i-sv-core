`timescale 1ns/1ps

// Store the 32 RV32I integer registers with two combinational read ports and one
// synchronous write port. Architectural register x0 is protected on both reads
// and writes; reset clearing keeps simulation waveforms deterministic.

module rv32i_regfile (
  // Clock/reset, two source-register reads, and one destination-register write.
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [4:0]  rs1_addr_i,
  input  logic [4:0]  rs2_addr_i,
  output logic [31:0] rs1_data_o,
  output logic [31:0] rs2_data_o,
  input  logic        rd_write_i,
  input  logic [4:0]  rd_addr_i,
  input  logic [31:0] rd_data_i
);
  logic [31:0] registers [0:31];
  integer index;

  // The x0 tests make the architectural rule explicit even if its stored bits
  // were ever disturbed by an unknown value during simulation.
  assign rs1_data_o = (rs1_addr_i == 5'd0) ? 32'b0 : registers[rs1_addr_i];
  assign rs2_data_o = (rs2_addr_i == 5'd0) ? 32'b0 : registers[rs2_addr_i];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (index = 0; index < 32; index = index + 1)
        registers[index] <= 32'b0;
    end else begin
      if (rd_write_i && (rd_addr_i != 5'd0))
        registers[rd_addr_i] <= rd_data_i;

      // Keep the physical storage clean as well as masking x0 reads.
      registers[0] <= 32'b0;
    end
  end
endmodule
