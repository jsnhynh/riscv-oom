/*
  Core

  This module encapsulates the processing logic of our
  cpu and contains ports to memory.
*/
import riscv_isa_pkg::*;
import uarch_pkg::*;

module core (
  input clk, rst,

  // IMEM Ports
  output logic [CPU_ADDR_BITS-1:0]    icache_addr,
  output logic                        icache_re,
  input  logic [2*CPU_DATA_BITS-1:0]  icache_dout,
  input  logic                        icache_dout_val,
  input  logic                        icache_stall,

  // DMEM Ports
  output logic [CPU_ADDR_BITS-1:0]  dcache_addr,
  output logic                      dcache_re,
  input  logic [CPU_DATA_BITS-1:0]  dcache_dout,
  input  logic                      dcache_dout_val,
  input  logic                      dcache_stall,
  // DMEM Write Ports
  output logic [CPU_DATA_BITS-1:0]  dcache_din,
  output logic [3:0]                dcache_we
);

endmodule