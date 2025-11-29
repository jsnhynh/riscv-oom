/*
    Core

    This module encapsulates the processing logic.
*/
import riscv_isa_pkg::*;
import uarch_pkg::*;

module core (
    input clk, rst,

    // IMEM Ports
    input  logic                        imem_req_rdy,
    output logic                        imem_req_val,
    output logic [CPU_ADDR_BITS-1:0]    imem_req_packet,

    output logic                        imem_rec_rdy,
    input  logic                        imem_rec_val,
    input  logic [FETCH_WIDTH*CPU_INST_BITS-1:0]    imem_rec_packet,

    // DMEM Ports
    input  logic                        dmem_req_rdy,
    output instruction_t                dmem_req_packet,

    output logic                        dmem_rec_rdy,
    input  writeback_packet_t           dmem_rec_packet
);
    //-------------------------------------------------------------
    // 1-Fetch
    //-------------------------------------------------------------
    logic                       flush;
    logic [2:0]                 pc_sel;
    logic [CPU_ADDR_BITS-1:0]   rob_pc;
    logic                       decode_rdy;
    logic [CPU_ADDR_BITS-1:0]   inst_pcs    [PIPE_WIDTH-1:0];
    logic [CPU_INST_BITS-1:0]   insts       [PIPE_WIDTH-1:0];
    logic                       fetch_val;
    assign flush = '0;
    assign pc_sel = {2'b0, flush};
    assign rob_pc = '{default:'0};
    fetch fetch_stage (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Ports from ROB
        .pc_sel(pc_sel),
        .rob_pc(rob_pc),
        // IMEM Ports
        .imem_req_rdy(imem_req_rdy),
        .imem_req_val(imem_req_val),
        .imem_req_packet(imem_req_packet),
        .imem_rec_rdy(imem_rec_rdy),
        .imem_rec_val(imem_rec_val),
        .imem_rec_packet(imem_rec_packet),
        // Ports to Decode
        .decode_rdy(decode_rdy),
        .inst_pcs(inst_pcs),
        .insts(insts),
        .fetch_val(fetch_val)
    );
    
    //-------------------------------------------------------------
    // 2-Decode
    //-------------------------------------------------------------
    logic           rename_rdy;
    instruction_t   decoded_insts   [PIPE_WIDTH-1:0];
    decode decode_stage (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Ports from Fetch
        .decode_rdy(decode_rdy),
        .inst_pcs(inst_pcs),
        .insts(insts),
        .fetch_val(fetch_val),
        // Ports to Rename
        .rename_rdy(rename_rdy),
        .decoded_insts(decoded_insts)
    );

    //-------------------------------------------------------------
    // 3-Rename
    //-------------------------------------------------------------
    logic                   dispatch_rdy;
    instruction_t           renamed_insts       [PIPE_WIDTH-1:0];
    logic [PIPE_WIDTH-1:0]  rob_alloc_req, rob_alloc_gnt;
    logic [TAG_WIDTH-1:0]   rob_alloc_tags      [PIPE_WIDTH-1:0];
    prf_commit_write_port_t commit_write_ports  [PIPE_WIDTH-1:0];
    rename rename_stage (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Ports from Decode
        .rename_rdy(rename_rdy),
        .decoded_insts(decoded_insts),
        // Ports to Dispatch
        .dispatch_rdy(dispatch_rdy),
        .renamed_insts(renamed_insts),
        // Ports from ROB
        .rob_alloc_req(rob_alloc_req),
        .rob_alloc_gnt(rob_alloc_gnt),
        .rob_alloc_tags(rob_alloc_tags),
        .commit_write_ports(commit_write_ports)
    );

    //-------------------------------------------------------------
    // 4-Dispatch
    //-------------------------------------------------------------
    logic [PIPE_WIDTH-1:0]  rs_rdys             [NUM_RS-1:0];
    logic [PIPE_WIDTH-1:0]  rs_wes              [NUM_RS-1:0];
    instruction_t           rs_issue_ports      [NUM_RS-1:0][PIPE_WIDTH-1:0];
    logic [PIPE_WIDTH-1:0]  rob_rdy,            rob_we;
    rob_entry_t             rob_entries         [PIPE_WIDTH-1:0];
    dispatch dispatch_stage (
        // Ports from Rename
        .dispatch_rdy(dispatch_rdy),
        .renamed_insts(renamed_insts),
        // Ports to Issue
        .rs_rdys(rs_rdys),
        .rs_wes(rs_wes),
        .rs_issue_ports(rs_issue_ports),
        // Ports to ROB
        .rob_rdy(rob_rdy),
        .rob_we(rob_we),
        .rob_entries(rob_entries)
    );

    //-------------------------------------------------------------
    // 5-Issue
    //-------------------------------------------------------------
    logic [NUM_FU-1:0]      fu_rdys;
    instruction_t           fu_packets          [NUM_FU-1:0];
    logic [TAG_WIDTH-1:0]   commit_store_ids    [PIPE_WIDTH-1:0];
    logic [PIPE_WIDTH-1:0]  commit_store_vals;
    writeback_packet_t      cdb_ports           [FETCH_WIDTH-1:0];
    writeback_packet_t      agu_result;
    writeback_packet_t      forward_pkt;
    logic [TAG_WIDTH-1:0]   rob_head;
    issue issue_stage (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Ports from Dispatch
        .rs_rdys(rs_rdys),
        .rs_wes(rs_wes),
        .rs_issue_ports(rs_issue_ports),
        // Ports to Execute
        .fu_rdys(fu_rdys),
        .fu_packets(fu_packets),
        // Ports from ROB
        .commit_store_ids(commit_store_ids),
        .commit_store_vals(commit_store_vals),
        // CDB
        .cdb_ports(cdb_ports),
        // AGU Writeback
        .agu_result(agu_result),
        // LSQ Forward
        .forward_pkt(forward_pkt),
        // ROB Head
        .rob_head(rob_head)
    );

    //-------------------------------------------------------------
    // 6-Execute
    //-------------------------------------------------------------
    writeback_packet_t  fu_results      [NUM_FU-1:0];
    logic               fu_cdb_gnts     [NUM_FU-1:0];
    execute execute_stage (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Ports from Issue
        .fu_rdys(fu_rdys),
        .fu_packets(fu_packets),
        // CDB Ports
        .fu_results(fu_results),
        .fu_cdb_gnts(fu_cdb_gnts),
        // LSQ AGU Writeback
        .agu_result(agu_result),
        // DMEM Ports
        .dmem_rec_rdy(dmem_rec_rdy),
        .dmem_rec_packet(dmem_rec_packet),
        .forward_pkt(forward_pkt)
    );

    //-------------------------------------------------------------
    // 7-Writeback
    //-------------------------------------------------------------
    cdb writeback_stage (
        .fu_results(fu_results),
        .fu_cdb_gnts(fu_cdb_gnts),
        .cdb_ports(cdb_ports),
        .rob_head(rob_head)
    );

    //-------------------------------------------------------------
    // 8-Commit
    //-------------------------------------------------------------
    rob commit_stage (
        .clk(clk),
        .rst(rst),
        // Ports to Fetch
        .flush(flush),
        .rob_pc(rob_pc),
        // Ports to Rename
        .rob_alloc_req(rob_alloc_req),
        .rob_alloc_gnt(rob_alloc_gnt),
        .rob_alloc_tags(rob_alloc_tags),
        .commit_write_ports(commit_write_ports),
        /// Ports from Dispatch
        .rob_rdy(rob_rdy),
        .rob_we(rob_we),
        .rob_entries(rob_entries),
        // Ports from CDB
        .cdb_ports(cdb_ports),
        // Ports to LSQ
        .commit_store_ids(commit_store_ids),
        .commit_store_vals(commit_store_vals),
        // ROB Pointers
        .rob_head(rob_head)
    );

    assign dmem_req_packet = fu_packets[2];
    
endmodule