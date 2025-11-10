/*
    Issue Stage

    This module encapsulates all Reservation Stations and LSQ.
*/

import riscv_isa_pkg::*;
import uarch_pkg::*;

module issue (
    input  logic clk, rst, flush,

    // Ports from Dispatch
    output logic [PIPE_WIDTH-1:0]       alu_rs_rdy,
    output logic [PIPE_WIDTH-1:0]       lsq_rs_rdy,
    output logic [PIPE_WIDTH-1:0]       mdu_rs_rdy,

    input  logic [PIPE_WIDTH-1:0]       alu_rs_we,
    input  logic [PIPE_WIDTH-1:0]       lsq_rs_we,
    input  logic [PIPE_WIDTH-1:0]       mdu_rs_we,

    input  instruction_t                alu_rs_entries [PIPE_WIDTH-1:0],
    input  instruction_t                mdu_rs_entries [PIPE_WIDTH-1:0],
    input  instruction_t                lsq_rs_entries [PIPE_WIDTH-1:0],

    // Ports to Execute
    input  logic                        alu_rdy     [1:0], 
    input  logic                        agu_rdy, mdu_rdy,
    output instruction_t                alu_packet  [1:0], 
    output instruction_t                agu_packet, mdu_packet,

    // LSQ AGU Writeback
    input  writeback_packet_t           agu_result,

    // Ports to DMEM
    input  logic                        dmem_req_rdy,
    output instruction_t                dmem_req_packet,

    // Ports from ROB
    input  logic [TAG_WIDTH-1:0]        commit_store_ids    [PIPE_WIDTH-1:0],
    input  logic [PIPE_WIDTH-1:0]       commit_store_vals,

    input  writeback_packet_t           cdb_ports   [PIPE_WIDTH-1:0]
);
    //-------------------------------------------------------------
    //
    //-------------------------------------------------------------

endmodule