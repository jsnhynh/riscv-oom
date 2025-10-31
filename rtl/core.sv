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
    // Wires
    //-------------------------------------------------------------
    logic flush;
    logic pc_sel;
    logic rob_pc;

    logic decoder_rdy;
    logic inst0_pc, inst0_pc;
    logic inst0, inst1;
    logic inst_val;

    logic rename_rdy;
    logic decode_inst0, decode_inst1;

    logic dispatch_rdy;
    logic renamed_inst0, renamed_inst1;

    logic alu_rs_rdy, alu_rs_we;
    logic lsq_rs_rdy, lsq_rs_we;
    logic mdu_rs_rdy, mdu_rs_we;

    logic rob_alloc_req, rob_alloc_gnt;
    logic rob_tag0, rob_tag1;
    logic commit_0_write_port, commit_1_write_port;

    logic rob_rdy, rob_we;
    logic rob_entry0, rob_entry1;

    //-------------------------------------------------------------
    // 1-Fetch
    //-------------------------------------------------------------
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
        .inst0_pc(inst0_pc),
        .inst1_pc(inst1_pc),
        .inst0(inst0),
        .inst1(inst1),
        .inst_val(inst_val)
    );

    //-------------------------------------------------------------
    // 2-Decode
    //-------------------------------------------------------------
    decode decode_stage (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Ports from Fetch
        .decoder_rdy(decoder_rdy),
        .inst0_pc(inst0_pc),
        .inst1_pc(inst1_pc),
        .inst0(inst0),
        .inst1(inst1),
        .inst_val(inst_val),
        // Ports to Rename
        .rename_rdy(rename_rdy),
        .decode_inst0(decode_inst0),
        .decode_inst1(decode_inst1),
    );

    //-------------------------------------------------------------
    // 3-Rename
    //-------------------------------------------------------------
    rename rename_stage (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Ports from Decode
        .rename_rdy(rename_rdy),
        .decode_inst0(decode_inst0),
        .decode_inst1(decode_inst1),
        // Ports to Dispatch
        .dispatch_rdy(dispatch_rdy),
        .renamed_inst0(renamed_inst0),
        .renamed_inst1(renamed_inst1),
        // Ports from ROB
        .rob_alloc_req(rob_alloc_req),
        .rob_alloc_gnt(rob_alloc_gnt),
        .rob_tag0(rob_tag0),
        .rob_tag1(rob_tag1),
        .commit_0_write_port(commit_0_write_port),
        .commit_1_write_port(commit_1_write_port)
    );

    //-------------------------------------------------------------
    // 4-Dispatch
    //-------------------------------------------------------------
    dispatch dispatch_stage (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        // Ports from Rename
        .dispatch_rdy(dispatch_rdy),
        .renamed_inst0(renamed_inst0),
        .renamed_inst1(renamed_inst1),
        // Ports to Issue
        .alu_rs_rdy(alu_rs_rdy),
        .mdu_rs_rdy(mdu_rs_rdy),
        .lsq_rs_rdy(lsq_rs_rdy),
        .alu_rs_we(alu_rs_we),
        .mdu_rs_we(mdu_rs_we),
        .lsq_rs_we(lsq_rs_we),
        .alu_rs_entry0(alu_rs_entry0),
        .alu_rs_entry1(alu_rs_entry1),
        .mdu_rs_entry0(mdu_rs_entry0),
        .mdu_rs_entry1(mdu_rs_entry1),
        .lsq_rs_entry0(lsq_rs_entry0),
        .lsq_rs_entry1(lsq_rs_entry1),
        // Ports to ROB
        .rob_rdy(rob_rdy),
        .rob_we(rob_we),
        .rob_entry0(rob_entry0),
        .rob_entry1(rob_entry1)
    );

    //-------------------------------------------------------------
    // 5-Issue
    //-------------------------------------------------------------

    //-------------------------------------------------------------
    // 6-Execute
    //-------------------------------------------------------------

    //-------------------------------------------------------------
    // 7-Writeback
    //-------------------------------------------------------------

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
        .rob_tag0(rob_tag0),
        .rob_tag1(rob_tag1),
        .commit_0_write_port(commit_0_write_port),
        .commit_1_write_port(commit_1_write_port),
        /// Ports from Dispatch
        .rob_rdy(rob_rdy),
        .rob_we(rob_we),
        .rob_entry0(rob_entry0),
        .rob_entry1(rob_entry1),
        // Ports from CDB
        .cdb_port0(cdb_port0),
        .cdb_port1(cdb_port1),
        // Ports to LSQ
        .commit_store_id0(commit_store_id0),
        .commit_store_id1(commit_store_id1),
        // ROB Pointers
        .rob_head(rob_head),
        .rob_tail(rob_tail)
    );

endmodule