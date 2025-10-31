/*
    Writeback Stage

    This module grants 2 FU's access to the CDB's
*/

import riscv_isa_pkg::*;
import uarch_pkg::*;

module cdb (
    input  logic clk, rst, 

    // Ports from Execute
    input  writeback_packet_t   alu_result0, alu_result1, mdu_result, dcache_result,
    output logic                alu_cdb_gnt0, alu_cdb_gnt1, mdu_cdb_gnt, dcache_cdb_gnt,

    // Ports to ROB & Execute
    output writeback_packet_t cdb_port0, cdb_port1
);

endmodule