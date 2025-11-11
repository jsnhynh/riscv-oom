`timescale 1ns/1ps

import riscv_isa_pkg::*;
import uarch_pkg::*;

module fetch_tb;
    localparam TEST_FILE = "fetch_test.hex";
    localparam MEM_SIZE = 120;

    // Testbench Signals
    logic clk;
    logic rst;
    logic flush_i;
    logic imem_req_rdy_i;

    logic [2:0]                 pc_sel_i;
    logic [CPU_ADDR_BITS-1:0]   rob_pc_i;

    // Interface between DUT and Memory Model
    logic [CPU_ADDR_BITS-1:0]   imem_req_packet;
    logic                       imem_req_val;
    logic [FETCH_WIDTH*CPU_INST_BITS-1:0] imem_rec_packet;
    logic                       imem_rec_val;

    // Decoder Ports
    logic                       decoder_rdy_i;
    logic [CPU_ADDR_BITS-1:0]   inst_pcs_o  [PIPE_WIDTH-1:0];
    logic [CPU_INST_BITS-1:0]   insts_o     [PIPE_WIDTH-1:0];
    logic                       fetch_val_o;

    fetch dut (
        .clk(clk),
        .rst(rst),
        .flush(flush_i),

        .pc_sel(pc_sel_i),
        .rob_pc(rob_pc_i),

        .imem_req_rdy(imem_req_rdy_i),
        .imem_req_val(imem_req_val),
        .imem_req_packet(imem_req_packet),
        .imem_rec_rdy(imem_rec_rdy),
        .imem_rec_val(imem_rec_val),
        .imem_rec_packet(imem_rec_packet),

        .decoder_rdy(decoder_rdy_i),
        .inst_pcs(inst_pcs_o),
        .insts(insts_o),
        .fetch_val(fetch_val_o)
    );

    mem_simple #(
        .IMEM_HEX_FILE(TEST_FILE)
    ) mem (
        .clk(clk),
        .rst(rst),
        // IMEM Ports
        .imem_req_rdy(imem_req_rdy_i),
        .imem_req_val(imem_req_val),
        .imem_req_packet(imem_req_packet),
        .imem_rec_rdy(imem_rec_rdy),
        .imem_rec_val(imem_rec_val),
        .imem_rec_packet(imem_rec_packet),

        // DMEM Ports (Unconnected)
        .dmem_req_rdy(),
        .dmem_req_packet('0),
        .dmem_rec_rdy('0),
        .dmem_rec_packet()
    );

    // Clock Generation
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        $display("Starting Fetch Stage Testbench...");
        // Initialize signals
        clk = 0;
        rst = 1;
        flush_i = 0;
        imem_req_rdy_i = 1;
        pc_sel_i = '0;
        pc_sel_i[0] = flush_i;
        rob_pc_i = '0;
        decoder_rdy_i = 1;

        // Reset Sequence
        #1; @(posedge clk); rst = 0;
        $display("[%0t] Reset Released. PC should be at reset vector %h.", $time, PC_RESET);
        @(posedge clk);

        // -- Test 1: Sequential Fetch --
        $display("[%0t] Test 1: Sequential Fetching...", $time);
        // assert (imem_req_packet == PC_RESET) else $fatal(1, "[%0t] PC did not reset correctly. Addr=%h", $time, imem_req_packet);
        repeat (5) @(posedge clk); // Let a few fetches happen
        
        
        // -- Test 2: Decoder Stall --
        $display("[%0t] Test 2: Decoder Stall...", $time);
        decoder_rdy_i = 0; // Stall the decoder
        repeat (3) begin
            @(posedge clk); // Hold stall
            $display("OUT: PC:%h Inst0:%h | PC4:%h Inst1:%h | Inst Val:%b | ***STALLED",
            inst_pcs_o[0], insts_o[0], inst_pcs_o[1], insts_o[1], fetch_val_o);
        end        decoder_rdy_i = 1; // Release stall
        repeat (2) @(posedge clk);    // Allow recovery

        // -- Test 3: I-Cache Stall --
        $display("[%0t] Test 3: Cache Stall...", $time);
        imem_req_rdy_i = 0; // Stall the fetch stage
        repeat (5) begin
            @(posedge clk); // Hold stall
            $display("OUT: PC:%h Inst0:%h | PC4:%h Inst1:%h | Inst Val:%b | ***STALLED",
            inst_pcs_o[0], insts_o[0], inst_pcs_o[1], insts_o[1], fetch_val_o);
        end
        imem_req_rdy_i = 1; // Release stall
        repeat (3) @(posedge clk);     // Allow recovery

        // --- Test 4: Branch/Jump Redirect ---
        $display("[%0t] Test 4: Redirect...", $time);
        pc_sel_i = 3'b001; // Select ROB PC
        rob_pc_i = 32'h0000_0004;
        flush_i  = 1;       // Assert flush to force redirect
        @(posedge clk);
        flush_i = 0;        // De-assert flush for next cycle fetch
        pc_sel_i = '0;
        repeat(2) @(posedge clk);     // PC updates, new fetch issued to 0004
        assert (inst_pcs_o[0] == 32'h0000_0004) else $fatal(1, "[%0t] Redirect failed. Addr=%h", $time, imem_req_packet);
        repeat (5) @(posedge clk);
        

        #100; // Run for a bit longer
        $display("[%0t] Testbench Finished.", $time);
        $finish;
    end

    initial begin
        @(negedge rst);
        #1;
        $monitor ("IN: flush:%b | imem_rec_rdy:%b | decode_rdy:%b",
            flush_i, imem_rec_rdy, decoder_rdy_i);
        $monitor("OUT: PC:%h Inst0:%h | PC4:%h Inst1:%h | Inst Val:%b | IB_EMPTY:%d",
            inst_pcs_o[0], insts_o[0], inst_pcs_o[1], insts_o[1], fetch_val_o, dut.ib.is_empty);

    end

endmodule