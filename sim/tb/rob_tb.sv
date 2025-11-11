`timescale 1ns/1ps

import uarch_pkg::*;
import riscv_isa_pkg::*;

module rob_tb;

    // Use parameters from packages
    // localparam CLK_PERIOD = 10; // Already defined in uarch_pkg

    // --- Testbench Signals (DUT Interface) ---
    logic clk;
    logic rst;

    // --- DUT Outputs (Monitored) ---
    logic [1:0]              rob_rdy_o;
    logic                    flush_o;
    logic [CPU_ADDR_BITS-1:0] rob_pc_o;
    logic [1:0]              rob_alloc_gnt_o;
    logic [TAG_WIDTH-1:0]    rob_tag0_o, rob_tag1_o;
    prf_commit_write_port_t  commit_0_write_port_o, commit_1_write_port_o;
    logic [TAG_WIDTH-1:0]    commit_store_id0_o, commit_store_id1_o;
    logic                    commit_store_val0_o, commit_store_val1_o;
    logic [TAG_WIDTH-1:0]    rob_head_o, rob_tail_o;

    // --- DUT Inputs (Stimulus) ---
    logic [1:0]              rob_alloc_req_i;
    rob_entry_t              rob_entry0_i, rob_entry1_i;
    logic [1:0]              rob_we_i;
    writeback_packet_t       cdb_port0_i, cdb_port1_i;


    // Instantiate the DUT (Device Under Test)
    rob #(
        .DEPTH(ROB_ENTRIES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rob_rdy(rob_rdy_o),
        .flush(flush_o),
        .rob_pc(rob_pc_o),
        .rob_alloc_req(rob_alloc_req_i),
        .rob_alloc_gnt(rob_alloc_gnt_o),
        .rob_tag0(rob_tag0_o),
        .rob_tag1(rob_tag1_o),
        .commit_0_write_port(commit_0_write_port_o),
        .commit_1_write_port(commit_1_write_port_o),
        .rob_entry0(rob_entry0_i),
        .rob_entry1(rob_entry1_i),
        .rob_we(rob_we_i),
        .cdb_port0(cdb_port0_i),
        .cdb_port1(cdb_port1_i),
        .commit_store_id0(commit_store_id0_o),
        .commit_store_id1(commit_store_id1_o),
        .commit_store_val0(commit_store_val0_o),
        .commit_store_val1(commit_store_val1_o),
        .rob_head(rob_head_o),
        .rob_tail(rob_tail_o)
    );

    // Clock Generation
    always #(CLK_PERIOD/2) clk = ~clk;

    // --- Helper Tasks ---

    // Task to reset the DUT
    task automatic reset_dut();
        rst = 1'b1;
        rob_alloc_req_i = '0;
        rob_we_i = '0;
        cdb_port0_i = '{default:'0};
        cdb_port1_i = '{default:'0};
        repeat(2) @(posedge clk);
        rst = 1'b0;
        $display("[%0t] Reset Released.", $time);
    endtask

    // Task to simulate a CDB Writeback (Execute Stage)
    // CORRECTED: Does not pass branch_taken, as it's encoded in 'result'
    task automatic writeback(
        input logic [TAG_WIDTH-1:0]     tag,
        input logic [CPU_DATA_BITS-1:0] result,
        input logic                     is_exception,
        input logic                     use_port_1 // 0=CDB0, 1=CDB1
    );
        if (use_port_1) begin
            cdb_port1_i.is_valid     = 1'b1;
            cdb_port1_i.dest_tag     = tag;
            cdb_port1_i.result       = result;
            cdb_port1_i.is_exception = is_exception;
            @(posedge clk);
            cdb_port1_i.is_valid = 1'b0;
        end else begin
            cdb_port0_i.is_valid     = 1'b1;
            cdb_port0_i.dest_tag     = tag;
            cdb_port0_i.result       = result;
            cdb_port0_i.is_exception = is_exception;
            @(posedge clk);
            cdb_port0_i.is_valid = 1'b0;
        end
    endtask

    // Task to simulate Rename/Dispatch handshake (2 cycles)
    task automatic dispatch(
        input rob_entry_t entry0,
        input rob_entry_t entry1,
        input [1:0]       num_to_dispatch // 00, 01, 10, or 11
    );
        logic [TAG_WIDTH-1:0] tag0, tag1;

        // --- Simulate Rename Stage (Cycle 1) ---
        rob_alloc_req_i = num_to_dispatch;
        @(posedge clk); // Wait for ROB to see request and provide grant/tags
        
        // Check if ROB granted the request
        if (num_to_dispatch == 2'b11 && rob_alloc_gnt_o != 2'b11) begin
            $fatal(1, "[%0t] ROB failed to grant 2 slots when requested!", $time);
        end else if (num_to_dispatch > 0 && rob_alloc_gnt_o == 2'b00) begin
            $fatal(1, "[%0t] ROB failed to grant 1 slot when requested!", $time);
        end
        
        // --- Simulate Dispatch Stage (Cycle 2) ---
        rob_alloc_req_i = '0; // De-assert request
        rob_we_i[0] = (num_to_dispatch[0]) && rob_alloc_gnt_o[0];
        rob_we_i[1] = (num_to_dispatch[1]) && rob_alloc_gnt_o[1];
        rob_entry0_i = entry0;
        rob_entry1_i = entry1;
        
        @(posedge clk);
        
        rob_we_i = '0; // De-assert write
    endtask

    // Main Stimulus
    initial begin
        $display("--- ROB Testbench Starting ---");
        clk = 0;
        reset_dut();
        
        // --- Test 1: Simple Dual Alloc, Writeback, Commit ---
        $display("[%0t] Test 1: Allocating 2 instructions...", $time);
        rob_entry_t inst_A = '{is_valid:1, has_rd:1, rd:1, pc:32'h100, default:'0};
        rob_entry_t inst_B = '{is_valid:1, has_rd:1, rd:2, pc:32'h104, default:'0};
        dispatch(inst_A, inst_B, 2'b11); // Takes 2 cycles
        
        assert(rob_tail_o == 2) else $fatal(1, "Tail did not advance to 2");
        assert(rob_head_o == 0) else $fatal(1, "Head moved prematurely");
        $display("[%0t] Test 1: 2 instructions dispatched. Head: %d, Tail: %d", $time, rob_head_o, rob_tail_o);

        writeback(0, 32'hAAAA, 1'b0, 0); // Writeback for Tag 0 on CDB0
        writeback(1, 32'hBBBB, 1'b0, 1); // Writeback for Tag 1 on CDB1 (in parallel)

        $display("[%0t] Test 1: Results written back. Waiting for commit...", $time);
        @(posedge clk); // ROB latches WB results
        
        @(posedge clk); // Commit logic evaluates
        assert(commit_0_write_port_o.we == 1 && commit_0_write_port_o.data == 32'hAAAA);
        assert(commit_1_write_port_o.we == 1 && commit_1_write_port_o.data == 32'hBBBB);
        $display("[%0t] Test 1: Dual commit successful.", $time);

        @(posedge clk); // Pointers advance
        assert(rob_head_o == 2) else $fatal(1, "Head did not advance after commit");
        assert(rob_rdy_o == 2'b11) else $fatal(1, "ROB did not report 2+ free slots (empty)");
        $display("[%0t] Test 1: Pointers advanced, ROB is empty. Head: %d, Tail: %d", $time, rob_head_o, rob_tail_o);

        // --- Test 2: Out-of-Order Writeback, In-Order Commit ---
        $display("[%0t] Test 2: OoO Writeback, In-Order Commit...", $time);
        rob_entry_t inst_C = '{is_valid:1, has_rd:1, rd:3, pc:32'h108, default:'0};
        rob_entry_t inst_D = '{is_valid:1, has_rd:1, rd:4, pc:32'h10C, default:'0};
        dispatch(inst_C, inst_D, 2'b11); // Dispatch C (Tag 2) and D (Tag 3)
        
        writeback(3, 32'hDDDD, 1'b0, 0); // WB for Tag 3 (Inst D) FINISHES FIRST
        
        @(posedge clk); // ROB latches WB for D
        $display("[%0t] Test 2: Inst D (Tag 3) written back. Head: %d", $time, rob_head_o);
        assert(commit_0_write_port_o.we == 1'b0) else $fatal(1, "Inst C should not commit yet");

        writeback(2, 32'hCCCC, 1'b0, 1); // WB for Tag 2 (Inst C) FINISHES SECOND
        
        @(posedge clk); // ROB latches WB for C
        $display("[%0t] Test 2: Inst C (Tag 2) written back. Waiting for commit...", $time);
        
        @(posedge clk); // Commit logic evaluates. C and D should both be ready.
        assert(commit_0_write_port_o.we == 1 && commit_0_write_port_o.data == 32'hCCCC);
        assert(commit_1_write_port_o.we == 1 && commit_1_write_port_o.data == 32'hDDDD);
        $display("[%0t] Test 2: Dual commit of C and D successful.", $time);

        @(posedge clk); // Pointers advance
        assert(rob_head_o == 4) else $fatal(1, "Head did not advance to 4");
        $display("[%0t] Test 2: Pointers advanced. Head: %d, Tail: %d", $time, rob_head_o, rob_tail_o);


        // --- Test 3: Mispredicted Branch (Predict-Not-Taken) ---
        $display("[%0t] Test 3: Mispredicted Branch Test...", $time);
        rob_entry_t inst_E = '{is_valid:1, is_branch:1, pc:32'h110, default:'0};
        rob_entry_t inst_F = '{is_valid:1, has_rd:1, rd:5, pc:32'h114, default:'0}; // Speculated path
        dispatch(inst_E, inst_F, 2'b11); // Dispatch branch (Tag 4) and speculative inst (Tag 5)
        
        // Branch executes, is TAKEN (mispredict), calculates target 0x2000
        // CORRECTED: Send result encoded as {target_pc[31:1], taken_bit}
        logic [CPU_DATA_BITS-1:0] branch_result = {32'h2000[31:1], 1'b1};
        writeback(4, branch_result, 1'b0, 0); // Tag 4, Result=encoded, exception=0
        
        $display("[%0t] Test 3: Branch result (Tag 4) written back. Waiting for commit/flush...", $time);
        @(posedge clk); // ROB latches WB result
        
        @(posedge clk); // Commit logic evaluates
        assert(flush_o == 1'b1) else $fatal(1, "Flush was not asserted!");
        assert(rob_pc_o == 32'h2000) else $fatal(1, "Redirect PC is incorrect!");
        assert(commit_0_write_port_o.we == 1'b0) else $fatal(1, "Branch should not commit to PRF");
        $display("[%0t] Test 3: Flush asserted! Redirect PC: %h", $time, rob_pc_o);

        @(posedge clk); // Pointers reset due to flush
        assert(rob_head_o == 0) else $fatal(1, "Head did not reset on flush");
        assert(rob_tail_o == 0) else $fatal(1, "Tail did not reset on flush");
        assert(rob_rdy_o == 2'b11) else $fatal(1, "ROB is not empty after flush");
        $display("[%0t] Test 3: ROB successfully flushed.", $time);
        
        @(posedge clk);
        $display("--- ROB Testbench Finished Successfully ---");
        $finish;
    end
    
    // Monitor
    initial begin
        @(negedge rst);
        #1;
        $monitor("[%0t] Head: %d, Tail: %d, Avail: %d, Rdy: %b | AllocReq: %b, Gnt: %b | WE: %b | Flush: %b | Cmt0_WE: %b, Cmt1_WE: %b",
                    $time, rob_head_o, rob_tail_o, dut.avail_slots, rob_rdy_o,
                    rob_alloc_req_i, rob_alloc_gnt_o, rob_we_i,
                    flush_o, commit_0_write_port_o.we, commit_1_write_port_o.we);
        end

endmodule