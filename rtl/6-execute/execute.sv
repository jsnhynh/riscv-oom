/*
    Execute Stage - Execute Unit

    This module encapsulates all Functional Units
*/

import riscv_isa_pkg::*;
import uarch_pkg::*;
module execute (
    input  logic clk, rst,

    // Ports from Issue
    output logic                        alu_rdy     [1:0], 
    output logic                        mdu_rdy, dmem_rdy,
    input  instruction_t                alu_packet  [1:0],
    input  instruction_t                mdu_packet,
    input  instruction_t                dmem_packet,

    input  logic [CPU_DATA_BITS-1:0]    dcache_dout,
    input  logic                        dcache_dout_val,

    // CDB Ports
    output writeback_packet_t           alu_result  [1:0],
    output writeback_packet_t           mdu_result, dmem_result,
    input  logic                        alu_cdb_gnt [1:0], 
    input  logic                        mdu_cdb_gnt, dmem_cdb_gnt,

    input  writeback_packet_t           cdb_ports   [PIPE_WIDTH-1:0]    // Forward Ports
);
    //-------------------------------------------------------------
    //
    //-------------------------------------------------------------

endmodule