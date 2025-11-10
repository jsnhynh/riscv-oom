/*
    Execute Stage - Execute Unit

    This module encapsulates all Functional Units
*/

import riscv_isa_pkg::*;
import uarch_pkg::*;
module execute (
    input  logic clk, rst, flush,

    // Ports from Issue
    output logic                        alu_rdy     [1:0], 
    output logic                        agu_rdy, mdu_rdy,
    input  instruction_t                alu_packet  [1:0],
    input  instruction_t                agu_packet, mdu_packet,

    // CDB Ports
    output writeback_packet_t           alu_result  [1:0],
    output writeback_packet_t           agu_result, mdu_result,
    input  logic                        alu_cdb_gnt [1:0], 
    input  logic                        mdu_cdb_gnt
);
    //-------------------------------------------------------------
    //
    //-------------------------------------------------------------

endmodule