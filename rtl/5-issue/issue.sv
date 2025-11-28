/*
    Issue Stage

    This module encapsulates all Reservation Stations and LSQ.
*/

import riscv_isa_pkg::*;
import uarch_pkg::*;

module issue (
    input  logic clk, rst, flush,

    // Ports from Dispatch
    output logic [PIPE_WIDTH-1:0]   rs_rdys         [NUM_RS-1:0],
    input  logic [PIPE_WIDTH-1:0]   rs_wes          [NUM_RS-1:0],
    input  instruction_t            rs_issue_ports  [NUM_RS-1:0][PIPE_WIDTH-1:0],

    // Ports to Execute
    input  logic [NUM_FU-1:0]       fu_rdys,
    output instruction_t            fu_packets      [NUM_FU-1:0],

    // Ports from ROB
    input  logic [TAG_WIDTH-1:0]    commit_store_ids    [PIPE_WIDTH-1:0],
    input  logic [PIPE_WIDTH-1:0]   commit_store_vals,

    // CDB
    input  writeback_packet_t       cdb_ports       [PIPE_WIDTH-1:0],

    // AGU Writeback
    input  writeback_packet_t       agu_result,

    // LSQ Forward
    output writeback_packet_t       forward_pkt,
    
    // ROB Head
    input  logic [TAG_WIDTH-1:0]    rob_head
);
    //-------------------------------------------------------------
    // ALU RS                                                   (0)
    //-------------------------------------------------------------
    alu_rs alu_rs_inst (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Ports from Dispatch
        .rs_rdy(rs_rdys[0]),
        .rs_we(rs_wes[0]),
        .rs_entry(rs_issue_ports[0]),
        // Ports to Execute
        .alu_rdy(fu_rdys[1:0]),
        .execute_pkt(fu_packets[1:0]),
        // CDB
        .cdb_ports(cdb_ports)
    );

    //-------------------------------------------------------------
    // LSQ                                                   (1, 2)
    //-------------------------------------------------------------
    lsq lsq_inst (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Ports from Dispatch
        .ld_lsq_rdy(rs_rdys[1]),
        .st_lsq_rdy(rs_rdys[2]),
        .ld_lsq_we(rs_wes[1]),
        .st_lsq_we(rs_wes[2]),
        .ld_lsq_entry(rs_issue_ports[1]),
        .st_lsq_entry(rs_issue_ports[2]),
        // Ports to Execute
        .cache_stall(~fu_rdys[2]),
        .execute_pkt(fu_packets[2]),
        .agu_rdy(fu_rdys[3]),
        .agu_execute_pkt(fu_packets[3]),

        .agu_result(agu_result),

        .alu_rdy('0),     // ?
        .forward_pkt(), 
        .forward_rdy(),
        .forward_re('0),
        
        // CDB
        .cdb_ports(cdb_ports)
    );

    //-------------------------------------------------------------
    // MDU RS                                                   (3)
    //-------------------------------------------------------------

endmodule