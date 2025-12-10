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
    
    // AGU Writeback
    input  writeback_packet_t       agu_result,

    // Ports from ROB
    input  logic [TAG_WIDTH-1:0]    commit_store_ids    [PIPE_WIDTH-1:0],
    input  logic [PIPE_WIDTH-1:0]   commit_store_vals,

    // CDB
    input  writeback_packet_t       cdb_ports       [PIPE_WIDTH-1:0],

    // LSQ Forward
    output writeback_packet_t       forward_pkt,
    
    // ROB Head
    input  logic [TAG_WIDTH-1:0]    rob_head
);
    //-------------------------------------------------------------
    // ALU RS                                                   (0)
    //-------------------------------------------------------------
    reservation_station #(.NUM_ENTRIES(ALU_RS_ENTRIES), .ISSUE_WIDTH(2)) alu_rs_isnt (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Dispatch Interface
        .rs_rdy(rs_rdys[0]),
        .rs_we(rs_wes[0]),
        .rs_entries_in(rs_issue_ports[0]),
        // Issue Interface
        .fu_rdy(fu_rdys[1:0]),
        .fu_packets(fu_packets[1:0]),
        // Wakeup Interface
        .cdb_ports(cdb_ports),
        // Age Tracking
        .rob_head(rob_head)
    );

    //-------------------------------------------------------------
    // LSQ                                                   (1, 2)
    //-------------------------------------------------------------
    LSQ lsq_inst (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Ports from Dispatch
        .ld_rdy(rs_rdys[1]),
        .ld_we(rs_wes[1]),
        .ld_entries_in(rs_issue_ports[1]),
        .st_rdy(rs_rdys[2]),
        .st_we(rs_wes[2]),
        .st_entries_in(rs_issue_ports[2]),
        // Ports to/from Execute
        .dmem_rdy(fu_rdys[2]),
        .dmem_pkt(fu_packets[2]),
        .agu_rdy(fu_rdys[3]),
        .agu_pkt(fu_packets[3]),
        .agu_result(agu_result),        
        // CDB
        .cdb_ports(cdb_ports),
        // ROB
        .rob_head(rob_head),
        .commit_store_ids(commit_store_ids),
        .commit_store_vals(commit_store_vals)
    );

    //-------------------------------------------------------------
    // MDU RS                                                   (3)
    //-------------------------------------------------------------
    // Local array for the MDU RS (ISSUE_WIDTH = 1)
    instruction_t mdu_packet [0:0];
    assign fu_packets[4] = mdu_packet[0];
    reservation_station #(.NUM_ENTRIES(MDU_RS_ENTRIES), .ISSUE_WIDTH(1)) mdu_rs_isnt (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Dispatch Interface
        .rs_rdy(rs_rdys[3]),
        .rs_we(rs_wes[3]),
        .rs_entries_in(rs_issue_ports[3]),
        // Issue Interface
        .fu_rdy(fu_rdys[4]),
        .fu_packets(mdu_packet),
        // Wakeup Interface
        .cdb_ports(cdb_ports),
        // Age Tracking
        .rob_head(rob_head)
    );


endmodule