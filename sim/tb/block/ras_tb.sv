`timescale 1ns/1ps
import riscv_isa_pkg::*;
import uarch_pkg::*;

module ras_tb;

    //-------------------------------------------------------------
    // Test Statistics
    //-------------------------------------------------------------
    int tests_passed = 0;
    int tests_failed = 0;

    //-------------------------------------------------------------
    // Clock / Reset
    //-------------------------------------------------------------
    logic clk = 0;
    logic rst;
    always #(CLK_PERIOD/2) clk = ~clk;

    //-------------------------------------------------------------
    // DUT I/O
    //-------------------------------------------------------------
    localparam DEPTH = 16;
    localparam PTR_WIDTH = $clog2(DEPTH);
    
    logic                       push;
    logic                       pop;
    logic [CPU_ADDR_BITS-1:0]   push_addr;
    logic [CPU_ADDR_BITS-1:0]   pop_addr;
    logic                       push_rdy;
    logic                       pop_rdy;
    logic [PTR_WIDTH:0]         ptr;
    logic                       recover;
    logic [PTR_WIDTH:0]         recover_ptr;

    //-------------------------------------------------------------
    // Checkpoint Storage (simulates FTQ/ROB)
    //-------------------------------------------------------------
    logic [PTR_WIDTH:0] saved_checkpoints [32];

    //-------------------------------------------------------------
    // DUT
    //-------------------------------------------------------------
    ras #(
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .push(push),
        .pop(pop),
        .push_addr(push_addr),
        .pop_addr(pop_addr),
        .push_rdy(push_rdy),
        .pop_rdy(pop_rdy),
        .ptr(ptr),
        .recover(recover),
        .recover_ptr(recover_ptr)
    );

    //-------------------------------------------------------------
    // Helper Tasks
    //-------------------------------------------------------------
    task automatic clear_signals();
        push        = 1'b0;
        pop         = 1'b0;
        push_addr   = '0;
        recover     = 1'b0;
        recover_ptr = '0;
    endtask

    task automatic do_reset();
        @(negedge clk);
        rst = 1'b1;
        clear_signals();
        @(negedge clk);
        rst = 1'b0;
    endtask

    task automatic do_push(
        input logic [CPU_ADDR_BITS-1:0] addr
    );
        @(negedge clk);
        push = 1'b1;
        push_addr = addr;
        @(negedge clk);
        push = 1'b0;
    endtask

    task automatic do_pop_check(
        input string test_name,
        input logic [CPU_ADDR_BITS-1:0] expected_addr
    );
        logic [CPU_ADDR_BITS-1:0] captured_addr;
        logic [PTR_WIDTH:0] captured_ptr;
        logic pass;
        string errs;
        
        @(negedge clk);
        captured_addr = pop_addr;
        captured_ptr = ptr;
        pop = 1'b1;
        @(negedge clk);
        pop = 1'b0;
        
        pass = (captured_addr === expected_addr);
        
        if (pass) begin
            $display("  [PASS] %-28s : addr=0x%08h ptr=%0d", 
                     test_name, captured_addr, captured_ptr);
            tests_passed++;
        end else begin
            errs = $sformatf("addr=0x%08h (exp 0x%08h) ptr=%0d",
                            captured_addr, expected_addr, captured_ptr);
            $display("  [FAIL] %-28s : %s", test_name, errs);
            tests_failed++;
        end
    endtask

    task automatic save_checkpoint(input int id);
        saved_checkpoints[id] = ptr;
    endtask

    task automatic do_recover(input int id);
        @(negedge clk);
        recover = 1'b1;
        recover_ptr = saved_checkpoints[id];
        @(negedge clk);
        recover = 1'b0;
    endtask

    task automatic check_ptr(
        input string test_name,
        input logic [PTR_WIDTH:0] expected_ptr
    );
        logic pass;
        string errs;
        
        @(negedge clk);
        pass = (ptr === expected_ptr);
        
        if (pass) begin
            $display("  [PASS] %-28s : ptr=%0d", test_name, ptr);
            tests_passed++;
        end else begin
            errs = $sformatf("ptr=%0d (exp %0d)", ptr, expected_ptr);
            $display("  [FAIL] %-28s : %s", test_name, errs);
            tests_failed++;
        end
    endtask

    //-------------------------------------------------------------
    // Test Stimulus
    //-------------------------------------------------------------
    initial begin
        $dumpfile("ras_tb.vcd");
        $dumpvars(0, ras_tb);

        $display("========================================");
        $display("  RAS Testbench");
        $display("  DEPTH=%0d", DEPTH);
        $display("========================================\n");

        clear_signals();
        do_reset();

        $display("[TEST 1] Basic Push/Pop");
        check_ptr("Initial empty", 0);
        do_push(32'h1000);
        check_ptr("After push", 1);
        do_pop_check("Pop", 32'h1000);
        check_ptr("Back to empty", 0);
        $display("");

        $display("[TEST 2] LIFO Order");
        do_push(32'hAAAA);
        do_push(32'hBBBB);
        do_push(32'hCCCC);
        check_ptr("Three entries", 3);
        do_pop_check("Pop most recent", 32'hCCCC);
        do_pop_check("Pop middle", 32'hBBBB);
        do_pop_check("Pop oldest", 32'hAAAA);
        check_ptr("Empty", 0);
        $display("");

        $display("[TEST 3] Checkpoint & Recovery");
        do_push(32'h1000);
        do_push(32'h2000);
        save_checkpoint(0);
        do_push(32'h3000);
        do_push(32'h4000);
        check_ptr("Four entries", 4);
        do_recover(0);
        check_ptr("After recovery", 2);
        do_pop_check("Pop", 32'h2000);
        do_pop_check("Pop", 32'h1000);
        check_ptr("Empty", 0);
        $display("");

        $display("[TEST 4] Pop from Empty");
        do_reset();
        @(negedge clk);
        pop = 1'b1;
        @(negedge clk);
        pop = 1'b0;
        check_ptr("Ptr stays 0", 0);
        $display("");

        $display("[TEST 5] Fill to DEPTH");
        do_reset();
        for (int i = 0; i < DEPTH; i++) begin
            do_push(32'h7000 + i*4);
        end
        check_ptr("Filled", DEPTH);
        for (int i = DEPTH-1; i >= 0; i--) begin
            do_pop_check("", 32'h7000 + i*4);
        end
        check_ptr("Empty", 0);
        $display("");

        $display("[TEST 6] Overflow");
        do_reset();
        for (int i = 0; i < DEPTH; i++) begin
            do_push(32'h8000 + i*4);
        end
        do_push(32'hFFFF);
        $display("");

        $display("[TEST 7] Multiple Checkpoints");
        do_reset();
        save_checkpoint(0);           // Checkpoint at ptr=0
        do_push(32'hA000);
        save_checkpoint(1);           // Checkpoint at ptr=1
        do_push(32'hB000);
        save_checkpoint(2);           // Checkpoint at ptr=2
        do_push(32'hC000);
        do_recover(1);                // Restore to ptr=1 (stack[0]=A000 intact)
        check_ptr("Back to 1", 1);
        do_pop_check("Pop", 32'hA000);
        check_ptr("Empty", 0);
        
        // Push new values on clean stack
        do_push(32'hD000);
        do_push(32'hE000);
        check_ptr("Two entries", 2);
        
        // Pop them back in LIFO order
        do_pop_check("Pop E000", 32'hE000);
        do_pop_check("Pop D000", 32'hD000);
        $display("");

        $display("[TEST 8] Interleaved Ops");
        do_reset();
        do_push(32'h1111);
        save_checkpoint(10);
        do_push(32'h2222);
        do_pop_check("Pop", 32'h2222);
        do_push(32'h3333);
        save_checkpoint(11);
        do_push(32'h4444);
        do_recover(10);
        check_ptr("Recovered to 1", 1);
        do_pop_check("Pop", 32'h1111);
        $display("");

        $display("[TEST 9] Stress Test");
        do_reset();
        for (int i = 0; i < 8; i++) begin
            do_push(32'hC000 + i*4);
        end
        save_checkpoint(20);
        for (int i = 0; i < 4; i++) begin
            @(negedge clk);
            pop = 1'b1;
            @(negedge clk);
            pop = 1'b0;
        end
        check_ptr("After pops", 4);
        for (int i = 0; i < 4; i++) begin
            do_push(32'hD000 + i*4);
        end
        check_ptr("Back to 8", 8);
        do_recover(20);
        check_ptr("Recovered", 8);
        $display("");

        $display("========================================");
        $display("  Tests Passed: %0d", tests_passed);
        $display("  Tests Failed: %0d", tests_failed);
        $display("========================================");
        if (tests_failed == 0) $display("  ALL TESTS PASSED!");
        else $fatal(1, "FAILURES DETECTED");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Timeout!");
    end

endmodule