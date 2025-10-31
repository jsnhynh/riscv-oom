/*
    Execute Stage - Execute Unit

    This module encapsulates all Functional Units
*/

import riscv_isa_pkg::*;
import uarch_pkg::*;
module execute (
    input  logic clk, rst,

    // Ports from Issue
    output logic                alu_rdy0, alu_rdy1, mdu_rdy,
    input  execute_packet_t     dmem_packet,
    input  execute_packet_t     alu_packet0, 
    input  execute_packet_t     alu_packet1, 
    input  execute_packet_t     mdu_packet,

    input  logic [CPU_DATA_BITS-1:0]    dcache_dout,
    input  logic                        dcache_dout_val,

    // CDB Ports
    output writeback_packet_t   alu_result0, alu_result1, mdu_result, dcache_result,
    input  logic                alu_cdb_gnt0, alu_cdb_gnt1, mdu_cdb_gnt, dcache_cdb_gnt,

    input  writeback_packet_t   cdb_port0, cdb_port1    // Forward Ports
);

endmodule