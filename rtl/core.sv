/*
    Core

    This module encapsulates the processing logic.
*/
import riscv_isa_pkg::*;
import uarch_pkg::*;

module core (
    input clk, rst,

    // IMEM Ports
    output logic [CPU_ADDR_BITS-1:0]    icache_addr,
    output logic                        icache_re,
    input  logic [FETCH_WIDTH*CPU_DATA_BITS-1:0]  icache_dout,
    input  logic                        icache_dout_val,
    input  logic                        icache_stall,

    // DMEM Ports
    output logic [CPU_ADDR_BITS-1:0]    dcache_addr,
    output logic                        dcache_re,
    input  logic [CPU_DATA_BITS-1:0]    dcache_dout,
    input  logic                        dcache_dout_val,
    input  logic                        dcache_stall,
    // DMEM Write Ports
    output logic [CPU_DATA_BITS-1:0]    dcache_din,
    output logic [3:0]                  dcache_we
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
        .icache_stall(icache_stall),
        // Ports from ROB
        .pc_sel(pc_sel),
        .rob_pc(rob_pc),
        // IMEM Ports
        .icache_addr(icache_addr),
        .icache_re(icache_re),
        .icache_dout(icache_dout),
        .icache_dout_val(icache_dout_val),
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
    logic [TAG_WIDTH-1:0]   rob_tags            [PIPE_WIDTH-1:0];
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
        .rob_tags(rob_tags),
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
    logic                   mdu_rdy,    dmem_rdy;
    instruction_t           alu_packet  [1:0];
    instruction_t           mdu_packet, dmem_packet;
    logic [TAG_WIDTH-1:0]   commit_store_ids    [PIPE_WIDTH-1:0];
    logic [PIPE_WIDTH-1:0]  commit_store_vals;
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
        .dcache_addr(dcache_addr),
        .dcache_re(dcache_re),
        .dcache_din(dcache_din),
        .dcache_we(dcache_we),
        .dcache_stall(dcache_stall),
        .alu_rdy(alu_rdy),
        .mdu_rdy(mdu_rdy),
        .dmem_rdy(dmem_rdy),
        .alu_packet(alu_packet),
        .mdu_packet(mdu_packet),
        .dmem_packet(dmem_packet),
        // Ports from ROB
        .commit_store_ids(commit_store_ids),
        .commit_store_vals(commit_store_vals)
    );

    //-------------------------------------------------------------
    // 6-Execute
    //-------------------------------------------------------------
    writeback_packet_t  alu_result  [1:0];
    writeback_packet_t  mdu_result,     dmem_result;
    logic [1:0]         alu_cdb_gnt;
    logic               mdu_cdb_gnt,    dmem_cdb_gnt;
    writeback_packet_t  cdb_ports   [FETCH_WIDTH-1:0];
    execute execute_stage (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Ports from Issue
        .alu_rdy(alu_rdy),
        .mdu_rdy(mdu_rdy),
        .dmem_rdy(dmem_rdy),
        .alu_packet(alu_packet),
        .mdu_packet(mdu_packet),
        .dmem_packet(dmem_packet),
        .dcache_dout(dcache_dout),
        .dcache_dout_val(dcache_dout_val),
        // CDB Ports
        .alu_result(alu_result),
        .mdu_result(mdu_result),
        .dmem_result(dmem_result),
        .alu_cdb_gnt(alu_cdb_gnt),
        .mdu_cdb_gnt(mdu_cdb_gnt),
        .dmem_cdb_gnt(dmem_cdb_gnt),
        .cdb_ports(cdb_ports)
    );

    //-------------------------------------------------------------
    // 7-Writeback
    //-------------------------------------------------------------
    logic [TAG_WIDTH-1:0]   rob_head,   rob_tail;
    cdb writeback_stage (
        .alu_result(alu_result),
        .mdu_result(mdu_result),
        .dmem_result(dmem_result),
        .alu_cdb_gnt(alu_cdb_gnt),
        .mdu_cdb_gnt(mdu_cdb_gnt),
        .dmem_cdb_gnt(dmem_cdb_gnt),
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
        .rob_tags(rob_tags),
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