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
    logic                       decoder_rdy;
    logic [CPU_ADDR_BITS-1:0]   inst_pcs    [PIPE_WIDTH-1:0];
    logic [CPU_INST_BITS-1:0]   insts       [PIPE_WIDTH-1:0];
    logic                       fetch_val;
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
        .decoder_rdy(decoder_rdy),
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
        .decoder_rdy(decoder_rdy),
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
    logic [PIPE_WIDTH-1:0]  alu_rs_rdy,     mdu_rs_rdy,     lsq_rs_rdy;
    logic [PIPE_WIDTH-1:0]  alu_rs_we,      mdu_rs_we,      lsq_rs_we;
    instruction_t           alu_rs_entries  [PIPE_WIDTH-1:0];
    instruction_t           mdu_rs_entries  [PIPE_WIDTH-1:0];
    instruction_t           lsq_rs_entries  [PIPE_WIDTH-1:0];
    logic [PIPE_WIDTH-1:0]  rob_rdy,        rob_we;
    rob_entry_t             rob_entries     [PIPE_WIDTH-1:0];
    dispatch dispatch_stage (
        // Ports from Rename
        .dispatch_rdy(dispatch_rdy),
        .renamed_insts(renamed_insts),
        // Ports to Issue
        .alu_rs_rdy(alu_rs_rdy),
        .mdu_rs_rdy(mdu_rs_rdy),
        .lsq_rs_rdy(lsq_rs_rdy),
        .alu_rs_we(alu_rs_we),
        .mdu_rs_we(mdu_rs_we),
        .lsq_rs_we(lsq_rs_we),
        .alu_rs_entries(alu_rs_entries),
        .mdu_rs_entries(mdu_rs_entries),
        .lsq_rs_entries(lsq_rs_entries),
        // Ports to ROB
        .rob_rdy(rob_rdy),
        .rob_we(rob_we),
        .rob_entries(rob_entries)
    );

    //-------------------------------------------------------------
    // 5-Issue
    //-------------------------------------------------------------
    logic                   alu_rdy     [1:0];
    logic                   agu_rdy, mdu_rdy;
    instruction_t           alu_packet  [1:0];
    instruction_t           agu_packet, mdu_packet;
    writeback_packet_t      agu_result;
    logic [TAG_WIDTH-1:0]   commit_store_ids    [PIPE_WIDTH-1:0];
    logic [PIPE_WIDTH-1:0]  commit_store_vals;
    writeback_packet_t      cdb_ports   [FETCH_WIDTH-1:0];
    issue issue_stage (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Ports from Dispatch
        .alu_rs_rdy(alu_rs_rdy),
        .mdu_rs_rdy(mdu_rs_rdy),
        .lsq_rs_rdy(lsq_rs_rdy),
        .alu_rs_we(alu_rs_we),
        .mdu_rs_we(mdu_rs_we),
        .lsq_rs_we(lsq_rs_we),
        .alu_rs_entries(alu_rs_entries),
        .mdu_rs_entries(mdu_rs_entries),
        .lsq_rs_entries(lsq_rs_entries),
        // Ports to Execute
        .alu_rdy(alu_rdy),
        .agu_rdy(agu_rdy),
        .mdu_rdy(mdu_rdy),
        .alu_packet(alu_packet),
        .agu_packet(agu_packet),
        .mdu_packet(mdu_packet),
        // LSQ AGU Writeback
        .agu_result(agu_result),
        // Ports to DMEM
        .dmem_req_rdy(dmem_req_rdy),
        .dmem_req_packet(dmem_req_packet),
        // Ports from ROB
        .commit_store_ids(commit_store_ids),
        .commit_store_vals(commit_store_vals),
        .cdb_ports(cdb_ports)
    );

    //-------------------------------------------------------------
    // 6-Execute
    //-------------------------------------------------------------
    writeback_packet_t  alu_result  [1:0];
    writeback_packet_t  mdu_result;
    logic [1:0]         alu_cdb_gnt;
    logic               mdu_cdb_gnt;
    execute execute_stage (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Ports from Issue
        .alu_rdy(alu_rdy),
        .agu_rdy(agu_rdy),
        .mdu_rdy(mdu_rdy),
        .alu_packet(alu_packet),
        .agu_packet(agu_packet),
        .mdu_packet(mdu_packet),
        // CDB Ports
        .alu_result(alu_result),
        .mdu_result(mdu_result),
        .alu_cdb_gnt(alu_cdb_gnt),
        .mdu_cdb_gnt(mdu_cdb_gnt),
        // LSQ AGU Writeback
        .agu_result(agu_result)
    );

    //-------------------------------------------------------------
    // 7-Writeback
    //-------------------------------------------------------------
    logic [TAG_WIDTH-1:0]   rob_head,   rob_tail;
    cdb writeback_stage (
        .alu_result(alu_result),
        .mdu_result(mdu_result),
        .dmem_result(dmem_rec_packet),
        .alu_cdb_gnt(alu_cdb_gnt),
        .mdu_cdb_gnt(mdu_cdb_gnt),
        .dmem_cdb_gnt(dmem_rec_rdy),
        .cdb_ports(cdb_ports),
        .rob_head(rob_head),
        .rob_tail(rob_tail)
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
        .rob_head(rob_head),
        .rob_tail(rob_tail)
    );

endmodule