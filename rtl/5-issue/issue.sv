/*
    Issue Stage

    This module encapsulates all Reservation Stations and LSQ.
*/

import riscv_isa_pkg::*;
import uarch_pkg::*;

module issue (
    input  logic clk, rst,

    // Ports from Dispatch
    input  logic [PIPE_WIDTH-1:0]       alu_rs_rdy,
    input  logic [PIPE_WIDTH-1:0]       lsq_rs_rdy,
    input  logic [PIPE_WIDTH-1:0]       mdu_rs_rdy,

    output logic [PIPE_WIDTH-1:0]       alu_rs_we,
    output logic [PIPE_WIDTH-1:0]       lsq_rs_we,
    output logic [PIPE_WIDTH-1:0]       mdu_rs_we,

    output instruction_t                alu_rs_entries [PIPE_WIDTH-1:0],
    output instruction_t                mdu_rs_entries [PIPE_WIDTH-1:0],
    output instruction_t                lsq_rs_entries [PIPE_WIDTH-1:0],

    // Ports to Execute
    output logic [CPU_ADDR_BITS-1:0]    dcache_addr,    // Drive DMEM while also sending packet, need some module to hold packet
    output logic                        dcache_re,
    output logic [CPU_DATA_BITS-1:0]    dcache_din,
    output logic [3:0]                  dcache_we
    input  logic                        dcache_stall,

    input  logic                        alu_rdy     [1:0], 
    input  logic                        mdu_rdy, dmem_rdy,
    output instruction_t                alu_packet  [1:0], 
    output instruction_t                mdu_packet,
    output instruction_t                dmem_packet
);
    //-------------------------------------------------------------
    //
    //-------------------------------------------------------------

endmodule