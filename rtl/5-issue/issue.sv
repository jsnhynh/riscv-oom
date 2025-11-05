/*
    Issue Stage

    This module encapsulates all Reservation Stations and LSQ.
*/

import riscv_isa_pkg::*;
import uarch_pkg::*;

module issue (
    input  logic clk, rst,

    // Ports from Dispatch
    input  logic [1:0]      alu_rs_rdy,
    input  logic [1:0]      mdu_rs_rdy,
    input  logic [1:0]      lsq_rs_rdy,

    output logic [1:0]      alu_rs_we,
    output logic [1:0]      mdu_rs_we,
    output logic [1:0]      lsq_rs_we,

    output instruction_t    alu_rs_entry0, alu_rs_entry1,
    output instruction_t    mdu_rs_entry0, mdu_rs_entry1,
    output instruction_t    lsq_rs_entry0, lsq_rs_entry1,

    // Ports to Execute
    output logic [CPU_ADDR_BITS-1:0]    dcache_addr,    // Drive DMEM while also sending packet, need some module to hold packet
    output logic                        dcache_re,
    output logic [CPU_DATA_BITS-1:0]    dcache_din,
    output logic [3:0]                  dcache_we
    input  logic                        dcache_stall,

    input  logic            alu_rdy0, alu_rdy1, mdu_rdy, dmem_rdy,
    output instruction_t    dmem_packet,
    output instruction_t    alu_packet0, 
    output instruction_t    alu_packet1, 
    output instruction_t    mdu_packet
);
    //-------------------------------------------------------------
    //
    //-------------------------------------------------------------

endmodule