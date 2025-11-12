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
    logic [TAG_WIDTH-1:0]    rob_alloc_tags_o             [PIPE_WIDTH-1:0];
    prf_commit_write_port_t  commit_write_ports_o   [PIPE_WIDTH-1:0];
    logic [TAG_WIDTH-1:0]    commit_store_ids_o     [PIPE_WIDTH-1:0];
    logic [PIPE_WIDTH-1:0]   commit_store_vals_o;
    logic [TAG_WIDTH-1:0]    rob_head_o, rob_tail_o;

    // --- DUT Inputs (Stimulus) ---
    logic [1:0]              rob_alloc_req_i;
    rob_entry_t              rob_entries_i          [PIPE_WIDTH-1:0];
    logic [1:0]              rob_we_i;  
    writeback_packet_t       cdb_ports_i            [PIPE_WIDTH-1:0];

    // Instantiate the DUT (Device Under Test)
    rob dut (
        .clk(clk),
        .rst(rst),
        .flush(flush_o),
        .rob_pc(rob_pc_o),
        .rob_alloc_req(rob_alloc_req_i),
        .rob_alloc_gnt(rob_alloc_gnt_o),
        .rob_alloc_tags(rob_alloc_tags_o),
        .commit_write_ports(commit_write_ports_o),
        .rob_entries(rob_entries_i),
        .rob_rdy(rob_rdy_o),
        .rob_we(rob_we_i),
        .cdb_ports(cdb_ports_i),
        .commit_store_ids(commit_store_ids_o),
        .commit_store_vals(commit_store_vals_o),
        .rob_head(rob_head_o),
        .rob_tail(rob_tail_o)
    );

    // Clock Generation
    always #(CLK_PERIOD/2) clk = ~clk;

    // --- Helper Tasks ---
    rob_entry_t inst_A, inst_B;    

    // Task to reset the DUT
    task automatic reset_dut();
        rst = 1'b1;
        rob_alloc_req_i = '0;
        rob_we_i = '0;
        cdb_ports_i = '{default:'0};
        repeat(2) @(posedge clk);
        rst = 1'b0;
        $display("[%0t] Reset Released.", $time);
    endtask

    // Task to simulate a CDB Writeback (Execute Stage)
    task automatic writeback(
        input logic [TAG_WIDTH-1:0]     tag,
        input logic [CPU_DATA_BITS-1:0] result,
        input logic                     exception,
        input logic                     use_port_1 // 0=CDB0, 1=CDB1
    );
        if (use_port_1) begin
            cdb_ports_i[1].is_valid     = 1'b1;
            cdb_ports_i[1].dest_tag     = tag;
            cdb_ports_i[1].result       = result;
            cdb_ports_i[1].exception    = exception;
        end else begin
            cdb_ports_i[0].is_valid     = 1'b1;
            cdb_ports_i[0].dest_tag     = tag;
            cdb_ports_i[0].result       = result;
            cdb_ports_i[0].exception    = exception;
        end
    endtask

    task automatic close_writeback;
            @(posedge clk);
            cdb_ports_i = '{default: '0};
    endtask

    // Task to simulate Rename/Dispatch handshake (2 cycles)
    task automatic dispatch (
        input rob_entry_t entry0,
        input rob_entry_t entry1,
        input logic [1:0] num_to_dispatch // 00, 01, 10, or 11
    );
        logic [TAG_WIDTH-1:0] tags  [PIPE_WIDTH-1:0];

        // --- Simulate Rename Stage (Cycle 1) ---
        rob_alloc_req_i = num_to_dispatch;
        @(posedge clk); // Wait for ROB to see request and provide grant/tags
        
        // Check if ROB granted the request
        if (num_to_dispatch == 2'b11 && rob_alloc_gnt_o != 2'b11) begin
            //$fatal(1, "[%0t] ROB failed to grant 2 slots when requested!", $time);
        end else if (num_to_dispatch > 0 && rob_alloc_gnt_o == 2'b00) begin
            //$fatal(1, "[%0t] ROB failed to grant 1 slot when requested!", $time);
        end
        
        // --- Simulate Dispatch Stage (Cycle 2) ---
        rob_alloc_req_i = '0; // De-assert request
        rob_we_i[0] = (num_to_dispatch[0]) && rob_alloc_gnt_o[0];
        rob_we_i[1] = (num_to_dispatch[1]) && rob_alloc_gnt_o[1];
        rob_entries_i[0] = entry0;
        rob_entries_i[1] = entry1;
    endtask

    task automatic close_dispatch();
        @(posedge clk);
        inst_A = '{default:'0};
        inst_B = '{default:'0};
        rob_entries_i = '{default:'0};
        rob_we_i = '0; // De-assert write
    endtask
    
    function automatic rob_entry_t gen_entry(
        input logic [CPU_ADDR_BITS-1:0] pc,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        rob_entry_t entry;
        entry = '{default:'0};
        entry.is_valid = 1;
        entry.pc = pc;
        entry.rd = rd;
        entry.has_rd = 1'b1;
        entry.opcode = opcode;
        return entry;
    endfunction


    // Main Stimulus
    initial begin
        $display("--- ROB Testbench Starting ---");
        clk = 0;
        reset_dut();
        
        // --- Test 1: In Order Alloc, OoO Writeback, In Order Commit ---
        $display("[%0t] Test 1: Allocating 6 instructions...", $time);
        inst_A = gen_entry(32'h100, 5'd1, OPC_ARI_ITYPE);
        inst_B = gen_entry(32'h104, 5'd2, OPC_ARI_ITYPE);
        dispatch(inst_A, inst_B, 2'b11); // Takes 2 cycles
        inst_A = gen_entry(32'h108, 5'd3, OPC_ARI_ITYPE);
        inst_B = gen_entry(32'h10c, 5'd4, OPC_ARI_ITYPE);
        dispatch(inst_A, inst_B, 2'b11); // Takes 2 cycles
        inst_A = gen_entry(32'h110, 5'd5, OPC_ARI_ITYPE);
        inst_B = gen_entry(32'h114, 5'd6, OPC_ARI_ITYPE);
        dispatch(inst_A, inst_B, 2'b11); // Takes 2 cycles
        close_dispatch();
        $display("[%0t] Test 1: 6 instructions dispatched. Head: %d, Tail: %d", $time, rob_head_o, rob_tail_o);

        writeback(0, 32'hAAAAAAAA, 1'b0, 0); // Writeback for Tag 0 on CDB0
        writeback(1, 32'hBBBBBBBB, 1'b0, 1); // Writeback for Tag 1 on CDB1 (in parallel)
        @(posedge clk); // ROB latches WB results
        writeback(4, 32'hEEEEEEEE, 1'b0, 1);
        writeback(5, 32'hFFFFFFFF, 1'b0, 0);
        @(posedge clk); // ROB latches WB results
        writeback(2, 32'hCCCCCCCC, 1'b0, 0);
        writeback(3, 32'hDDDDDDDD, 1'b0, 1);
        close_writeback(); // ROB latches WB results
        $display("[%0t] Test 1: Results written back. Waiting for commit...", $time);

        assert(commit_write_ports_o[0].we == 1 && commit_write_ports_o[0].data == 32'hCCCCCCCC);
        assert(commit_write_ports_o[1].we == 1 && commit_write_ports_o[1].data == 32'hDDDDDDDD);
        @(posedge clk); // Pointers advance
        @(posedge clk); // Pointers advance
        assert(rob_head_o == 6) else $fatal(1, "Head did not advance after commit");
        assert(rob_rdy_o == 2'b00) else $fatal(1, "ROB did not report 2+ free slots (empty)");
        $display("[%0t] Test 1: Pointers advanced, ROB is empty. Head: %d, Tail: %d", $time, rob_head_o, rob_tail_o);

        $display("[%0t] Test 1: ---- In Order Alloc, OoO Writeback, In Order Commit PASS ----", $time);

        // --- Test 2: Mispredicted Branch (Predict-Not-Taken) ---
        $display("[%0t] Test 2: Mispredicted @ isnt0 Branch Test...", $time);
        inst_A = gen_entry(32'h100, 5'd1, OPC_BRANCH);
        inst_B = gen_entry(32'h104, 5'd2, OPC_BRANCH);
        dispatch(inst_A, inst_B, 2'b11);
        close_dispatch();
        @(posedge clk);
        // Branch executes, is TAKEN (mispredict)
        writeback(6, 32'hAAAA0001, 1'b0, 0);
        writeback(7, 32'hFFFF0001, 1'b0, 1);
        close_writeback();
        // Branch result written back. Waiting for commit/flush
        assert(flush_o == 1'b1) else $fatal(1, "Flush was not asserted!");
        assert(rob_pc_o == 32'hAAAA0000) else $fatal(1, "Redirect PC is incorrect!");
        repeat (2) @(posedge clk); // ROB latches WB result
        
        $display("[%0t] Test 2: Mispredicted @ inst1 Branch Test...", $time);
        inst_A = gen_entry(32'h100, 5'd1, OPC_ARI_ITYPE);
        inst_B = gen_entry(32'h104, 5'd2, OPC_BRANCH);
        dispatch(inst_A, inst_B, 2'b11);
        close_dispatch();
        @(posedge clk);
        // Commit inst0, inst1 Branch executes, is TAKEN (mispredict)
        writeback(0, 32'hAAAAAAAA, 1'b0, 1);
        writeback(1, 32'hFFFF0001, 1'b0, 0);
        close_writeback();
        // Branch result written back. Waiting for commit/flush
        assert(flush_o == 1'b1) else $fatal(1, "Flush was not asserted!");
        assert(rob_pc_o == 32'hFFFF0000) else $fatal(1, "Redirect PC is incorrect!");

        $display("[%0t] Test 2: Correct Prediction @ inst1 Branch Test...", $time);
        inst_A = gen_entry(32'h100, 5'd1, OPC_ARI_ITYPE);
        inst_B = gen_entry(32'h104, 5'd2, OPC_BRANCH);
        dispatch(inst_A, inst_B, 2'b11);
        close_dispatch();
        @(posedge clk);
        // Commit inst0, inst1 Branch executes, is TAKEN (mispredict)
        writeback(0, 32'hAAAAAAAA, 1'b0, 1);
        writeback(1, 32'hFFFF0000, 1'b0, 0);
        close_writeback();
        // Branch result written back. Waiting for commit/flush
        assert(flush_o == 1'b0) else $fatal(1, "Flush was asserted!");

        $display("[%0t] Test 2: Jump @ isnt1 Branch Test...", $time);
        inst_A = gen_entry(32'h100, 5'd1, OPC_BRANCH);
        inst_B = gen_entry(32'h104, 5'd2, OPC_JAL);
        dispatch(inst_A, inst_B, 2'b11);
        close_dispatch();
        @(posedge clk);
        // Jump executes
        writeback(2, 32'hAAAA0000, 1'b0, 0);
        writeback(3, 32'hFFFF0000, 1'b0, 1);
        close_writeback();
        // Branch result written back. Waiting for commit/flush
        assert(flush_o == 1'b1) else $fatal(1, "Flush was not asserted!");
        assert(rob_pc_o == 32'hFFFF0000) else $fatal(1, "Redirect PC is incorrect!");
        repeat (2) @(posedge clk); // ROB latches WB result

        $display("[%0t] Test 3: Store", $time);
        inst_A = gen_entry(32'h100, 5'd1, OPC_STORE);
        inst_B = gen_entry(32'h104, 5'd2, OPC_STORE);
        dispatch(inst_A, inst_B, 2'b11);
        close_dispatch();
        repeat (5) @(posedge clk);
        repeat (2) @(posedge clk); // ROB latches WB result

        // --- Test 4: ROB Full ---
        $display("[%0t] Test 1: Allocating MAX instructions...", $time);
        inst_A = gen_entry(32'h100, 5'd0, OPC_ARI_ITYPE);
        inst_B = gen_entry(32'h104, 5'd1, OPC_ARI_ITYPE);
        dispatch(inst_A, inst_B, 2'b11); // Takes 2 cycles
        inst_A = gen_entry(32'h108, 5'd2, OPC_ARI_ITYPE);
        inst_B = gen_entry(32'h10c, 5'd3, OPC_ARI_ITYPE);
        dispatch(inst_A, inst_B, 2'b11); // Takes 2 cycles
        inst_A = gen_entry(32'h110, 5'd4, OPC_ARI_ITYPE);
        inst_B = gen_entry(32'h114, 5'd5, OPC_ARI_ITYPE);
        dispatch(inst_A, inst_B, 2'b11); // Takes 2 cycles
        inst_A = gen_entry(32'h100, 5'd6, OPC_ARI_ITYPE);
        inst_B = gen_entry(32'h104, 5'd7, OPC_ARI_ITYPE);
        dispatch(inst_A, inst_B, 2'b11); // Takes 2 cycles
        inst_A = gen_entry(32'h108, 5'd0, OPC_ARI_ITYPE);
        inst_B = gen_entry(32'h10c, 5'd1, OPC_ARI_ITYPE);
        dispatch(inst_A, inst_B, 2'b11); // Takes 2 cycles
        close_dispatch();
        $display("[%0t] Test 1: MAX instructions dispatched. Head: %d, Tail: %d", $time, rob_head_o, rob_tail_o);

        writeback(0, 32'hAAAAAAAA, 1'b0, 0); // Writeback for Tag 0 on CDB0
        writeback(1, 32'hBBBBBBBB, 1'b0, 1); // Writeback for Tag 1 on CDB1 (in parallel)
        @(posedge clk); // ROB latches WB results
        writeback(2, 32'hCCCCCCCC, 1'b0, 0);
        writeback(3, 32'hDDDDDDDD, 1'b0, 1);
        @(posedge clk); // ROB latches WB results
        writeback(4, 32'hEEEEEEEE, 1'b0, 0);
        writeback(5, 32'hFFFFFFFF, 1'b0, 1);
        close_writeback(); // ROB latches WB results
        $display("[%0t] Test 1: Results written back. Waiting for commit...", $time);

        assert(commit_write_ports_o[0].we == 1 && commit_write_ports_o[0].data == 32'hCCCCCCCC);
        assert(commit_write_ports_o[1].we == 1 && commit_write_ports_o[1].data == 32'hDDDDDDDD);
        @(posedge clk); // Pointers advance
        @(posedge clk); // Pointers advance
        assert(rob_head_o == 6) else $fatal(1, "Head did not advance after commit");
        assert(rob_rdy_o == 2'b00) else $fatal(1, "ROB did not report 2+ free slots (empty)");
        $display("[%0t] Test 1: Pointers advanced, ROB is empty. Head: %d, Tail: %d", $time, rob_head_o, rob_tail_o);

        $display("[%0t] Test 1: ---- In Order Alloc, OoO Writeback, In Order Commit PASS ----", $time);

        @(posedge clk);
        $display("--- ROB Testbench Finished Successfully ---");
        $finish;
    end
    
    // Monitor
    initial begin
        @(negedge rst);
        #1;
        $monitor("[%0t] Head: %d, Tail: %d, Avail: %d, Rdy: %b | AllocReq: %b, Gnt: %b | WE: %b | Flush: %b | Cmt0_WE: %b",
                    $time, rob_head_o, rob_tail_o, dut.avail_slots, rob_rdy_o,
                    rob_alloc_req_i, rob_alloc_gnt_o, rob_we_i,
                    flush_o, {commit_write_ports_o[1].we, commit_write_ports_o[0].we});
        end

endmodule