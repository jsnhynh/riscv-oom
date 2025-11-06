/*
    Writeback Stage

    This module grants 2 FU's access to the CDB's
*/

import riscv_isa_pkg::*;
import uarch_pkg::*;

module cdb (
    input  logic clk, rst, 

    // Ports from Execute
    input  writeback_packet_t   alu_result  [1:0],
    input  writeback_packet_t   mdu_result, dmem_result,
    output logic                alu_cdb_gnt [1:0], 
    output logic                mdu_cdb_gnt, dmem_cdb_gnt,

    // Ports to ROB & Execute
    output writeback_packet_t   cdb_ports   [PIPE_WIDTH-1:0]
);
    //-------------------------------------------------------------
    //
    //-------------------------------------------------------------

endmodule