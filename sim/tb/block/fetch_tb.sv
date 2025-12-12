`timescale 1ns/1ps

import riscv_isa_pkg::*;
import uarch_pkg::*;

module fetch_tb;
    //-------------------------------------------------------------
    // Test Configuration
    //-------------------------------------------------------------
    localparam TEST_FILE = "fetch_test.hex";  // Adjust path as needed
    localparam MEM_SIZE = 120;

    //-------------------------------------------------------------
    // Test Statistics
    //-------------------------------------------------------------
    int tests_passed = 0;
    int tests_failed = 0;
    int assertions_checked = 0;

    //-------------------------------------------------------------
    // Clock and Reset
    //-------------------------------------------------------------
    logic clk;
    logic rst;

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //-------------------------------------------------------------
    // Stimulus Signals (inputs to DUT)
    //-------------------------------------------------------------
    logic                       flush_i;
    logic [2:0]                 pc_sel_i;
    logic [CPU_ADDR_BITS-1:0]   rob_pc_i;
    logic                       imem_req_rdy_i;
    logic                       decode_rdy_i;

    //-------------------------------------------------------------
    // Memory Interface Signals
    //-------------------------------------------------------------
    logic [CPU_ADDR_BITS-1:0]               imem_req_packet;
    logic                                   imem_req_val;
    logic                                   imem_rec_rdy;
    logic [FETCH_WIDTH*CPU_INST_BITS-1:0]  imem_rec_packet;
    logic                                   imem_rec_val;

    //-------------------------------------------------------------
    // Monitored Signals (outputs from DUT)
    //-------------------------------------------------------------
    logic [CPU_ADDR_BITS-1:0]   inst_pcs_o  [PIPE_WIDTH-1:0];
    logic [CPU_INST_BITS-1:0]   insts_o     [PIPE_WIDTH-1:0];
    logic                       fetch_val_o;

    //-------------------------------------------------------------
    // Test Variables
    //-------------------------------------------------------------
    logic [CPU_INST_BITS-1:0] expected_sequence [30];
    logic [CPU_ADDR_BITS-1:0] expected_pc;
    logic [CPU_ADDR_BITS-1:0] pc_before_stall;
    logic [CPU_ADDR_BITS-1:0] last_valid_pc;
    logic [CPU_ADDR_BITS-1:0] pc_before_mem_stall;
    logic [CPU_ADDR_BITS-1:0] redirect_target;
    logic [CPU_ADDR_BITS-1:0] redirect_addr;
    logic [CPU_INST_BITS-1:0] inst0_before_stall;
    logic [CPU_INST_BITS-1:0] inst_before_stall;
    logic [CPU_INST_BITS-1:0] expected_next;
    logic [CPU_ADDR_BITS-1:0] targets [3];
    
    int instruction_index;
    int buffer_entries_before;
    int cycles_with_valid_output;
    int drain_cycles;
    int redirect_idx;
    int idx;

    //-------------------------------------------------------------
    // DUT Instantiation
    //-------------------------------------------------------------
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

        .decode_rdy(decode_rdy_i),
        .inst_pcs(inst_pcs_o),
        .insts(insts_o),
        .fetch_val(fetch_val_o)
    );

    //-------------------------------------------------------------
    // Memory Model Instantiation
    //-------------------------------------------------------------
    mem_simple #(
        .IMEM_HEX_FILE(TEST_FILE),
        .IMEM_POSTLOAD_DUMP(1),
        .IMEM_SIZE_BYTES(1024),  // Make sure it's large enough
        .DMEM_SIZE_BYTES(1024)
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
        .dmem_req_packet('{default:'0}),
        .dmem_rec_rdy(1'b0),
        .dmem_rec_packet()
    );

    //-------------------------------------------------------------
    // Helper Tasks
    //-------------------------------------------------------------
    
    // Task: Check assertion with detailed reporting
    task automatic check_assertion(
        input string test_name,
        input logic condition,
        input string fail_msg
    );
        assertions_checked++;
        if (condition) begin
            $display("  [PASS] %s", test_name);
            tests_passed++;
        end else begin
            $display("  [FAIL] %s: %s", test_name, fail_msg);
            tests_failed++;
        end
    endtask

    // Task: Initialize signals
    task automatic init_signals();
        rst = 1;
        flush_i = 0;
        imem_req_rdy_i = 1;
        pc_sel_i = 3'b000;
        rob_pc_i = '0;
        decode_rdy_i = 1;
        
        // Cycle 0 (rst=1): imem_req_addr is read (defaults to 0x00000000)
        //                  PC undetermined, IMEM output is 0
        @(posedge clk);
        
        // Cycle 1 (rst=0): IMEM outputs data from 0x00000000 (0x11111111, 0x22222222)
        //                  PC is now 0x00000000
        //                  imem_req_addr moves to 0x00000008
        rst = 0;
        @(posedge clk);
        
        // Now at Cycle 2: Buffer has received data from 0x00000000
        //                  Ready to check outputs
    endtask

    // Task: Wait for fetch to complete
    task automatic wait_for_fetch(input int cycles);
        repeat(cycles) @(posedge clk);
    endtask

    // Task: Display fetch output
    task automatic display_fetch_output();
        $display("    PC[0]=0x%h Inst[0]=0x%h | PC[1]=0x%h Inst[1]=0x%h | Val=%b",
                 inst_pcs_o[0], insts_o[0], inst_pcs_o[1], insts_o[1], fetch_val_o);
    endtask

    //-------------------------------------------------------------
    // Test Stimulus
    //-------------------------------------------------------------
    initial begin
        $dumpfile("fetch_tb.vcd");
        $dumpvars(0, fetch_tb);
        
        $display("========================================");
        $display("  Fetch Stage Testbench Started");
        $display("========================================\n");
        
        init_signals();
        
        //-------------------------------------------------------------
        // TEST 1: Reset and PC Initialization
        //-------------------------------------------------------------
        $display("[TEST 1] Reset and PC Initialization");
        $display("  PC_RESET constant = 0x%h", PC_RESET);
        
        // At this point (after init_signals):
        // - Cycle 2: Buffer should have data from 0x00000000
        // - inst_pcs_o[0] should be 0x00000000
        // - insts_o should be 0x11111111, 0x22222222
        
        $display("  Current PC output = 0x%h", inst_pcs_o[0]);
        $display("  Current instructions = 0x%h, 0x%h", insts_o[0], insts_o[1]);
        $display("  Fetch valid = %b", fetch_val_o);
        
        #1;

        check_assertion("First instruction PC is 0x00000000",
                       inst_pcs_o[0] == 32'h00000000,
                       $sformatf("Expected PC=0x00000000, got 0x%h", inst_pcs_o[0]));
        
        check_assertion("First instruction is 0x11111111",
                       insts_o[0] == 32'h11111111,
                       $sformatf("Expected inst=0x11111111, got 0x%h", insts_o[0]));
        
        check_assertion("Second instruction is 0x22222222",
                       insts_o[1] == 32'h22222222,
                       $sformatf("Expected inst=0x22222222, got 0x%h", insts_o[1]));
        
        check_assertion("Fetch valid after reset",
                       fetch_val_o == 1'b1,
                       $sformatf("Expected fetch_val=1, got %b", fetch_val_o));
        
        $display("");
        
        //-------------------------------------------------------------
        // TEST 2: Sequential Fetching with Program Order Verification
        //-------------------------------------------------------------
        init_signals();
        $display("[TEST 2] Sequential Fetching and Program Order");
        $display("  Verifying instruction stream matches memory contents...");
        
        // Expected instruction sequence from fetch_test.hex
        // Pattern: 11111111, 22222222, 33333333, ... up to ffffffff
        expected_sequence = '{
            32'h11111111, 32'h22222222, 32'h33333333, 32'h44444444,
            32'h55555555, 32'h66666666, 32'h77777777, 32'h88888888,
            32'h99999999, 32'haaaaaaaa, 32'hbbbbbbbb, 32'hcccccccc,
            32'hdddddddd, 32'heeeeeeee, 32'hffffffff, 32'hffffffff,
            32'heeeeeeee, 32'hdddddddd, 32'hcccccccc, 32'hbbbbbbbb,
            32'haaaaaaaa, 32'h99999999, 32'h88888888, 32'h77777777,
            32'h66666666, 32'h55555555, 32'h44444444, 32'h33333333,
            32'h22222222, 32'h11111111
        };
        
        expected_pc = PC_RESET;
        instruction_index = 0;
        
        $display("  Fetching and verifying 10 instruction pairs (20 instructions)...");
        
        for (int i = 0; i < 10; i++) begin
            // Wait for next valid output
            while (!fetch_val_o) @(posedge clk);
            
            // Now check the output
            // Verify instruction[0]
            check_assertion($sformatf("Inst[0] program order [pair %0d]", i),
                           insts_o[0] == expected_sequence[instruction_index],
                           $sformatf("Expected inst[0]=0x%h, got 0x%h at index %0d", 
                                    expected_sequence[instruction_index], insts_o[0], instruction_index));
            
            // Verify instruction[1]
            check_assertion($sformatf("Inst[1] program order [pair %0d]", i),
                           insts_o[1] == expected_sequence[instruction_index + 1],
                           $sformatf("Expected inst[1]=0x%h, got 0x%h at index %0d", 
                                    expected_sequence[instruction_index + 1], insts_o[1], instruction_index + 1));
            
            // Verify PC addresses
            check_assertion($sformatf("PC[0] address [pair %0d]", i),
                           inst_pcs_o[0] == (PC_RESET + instruction_index * 4),
                           $sformatf("Expected PC[0]=0x%h, got 0x%h", 
                                    PC_RESET + instruction_index * 4, inst_pcs_o[0]));
            
            check_assertion($sformatf("PC[1] = PC[0] + 4 [pair %0d]", i),
                           inst_pcs_o[1] == (inst_pcs_o[0] + 4),
                           $sformatf("Expected PC[1]=0x%h, got 0x%h", 
                                    inst_pcs_o[0] + 4, inst_pcs_o[1]));
            
            $display("  [Pair %0d] PC[0]=0x%h:0x%h | PC[1]=0x%h:0x%h ✓",
                     i, inst_pcs_o[0], insts_o[0], inst_pcs_o[1], insts_o[1]);
            
            instruction_index += 2; // Move to next pair
            @(posedge clk); // Move to next cycle
        end
        
        $display("  Program order verification: %0d instructions checked", instruction_index);
        $display("");
        
        //-------------------------------------------------------------
        // TEST 3: Decoder Stall (Backpressure)
        //-------------------------------------------------------------
        $display("[TEST 3] Decoder Stall (Backpressure)");
        $display("  Stalling decoder for 3 cycles...");
        
        @(posedge clk);
        pc_before_stall = inst_pcs_o[0];
        inst0_before_stall = insts_o[0];
        
        decode_rdy_i = 0; // Assert backpressure
        
        for (int i = 0; i < 3; i++) begin
            @(posedge clk);
            
            check_assertion($sformatf("Fetch output held during stall (cycle %0d)", i),
                           (inst_pcs_o[0] == pc_before_stall) && (insts_o[0] == inst0_before_stall),
                           $sformatf("Output changed during stall: PC=0x%h->0x%h, Inst=0x%h->0x%h",
                                    pc_before_stall, inst_pcs_o[0], 
                                    inst0_before_stall, insts_o[0]));
            
            $display("    [STALLED] PC held at 0x%h", inst_pcs_o[0]);
        end
        
        decode_rdy_i = 1; // Release stall
        
        wait_for_fetch(2);
        
        check_assertion("Fetch resumes after decoder stall",
                       inst_pcs_o[0] != pc_before_stall,
                       "PC did not advance after stall release");
        
        $display("  Stall released, fetch resumed");
        display_fetch_output();
        
        $display("");
        
        //-------------------------------------------------------------
        // TEST 4: I-Cache Stall (Buffer Decoupling)
        //-------------------------------------------------------------
        $display("[TEST 4] I-Cache Stall - Buffer Should Continue Draining");
        $display("  Memory stalled, but buffer should drain to decoder...");
        
        // First, ensure buffer has some data
        decode_rdy_i = 0;  // Stall decoder to fill buffer
        wait_for_fetch(3);
        
        buffer_entries_before = INST_BUF_DEPTH - (dut.ib.write_ptr - dut.ib.read_ptr);
        $display("  Buffer has %0d entries before memory stall", buffer_entries_before);
        
        decode_rdy_i = 1;  // Resume decoder
        imem_req_rdy_i = 0; // Stall memory
        
        cycles_with_valid_output = 0;
        
        // Buffer should continue providing valid output until empty
        for (int i = 0; i < INST_BUF_DEPTH + 2; i++) begin
            @(posedge clk);
            
            if (fetch_val_o) begin
                cycles_with_valid_output++;
                last_valid_pc = inst_pcs_o[0];
                $display("    [Cycle %0d] Buffer draining: PC=0x%h (buffer_empty=%b)", 
                         i, inst_pcs_o[0], dut.ib.is_empty);
            end else begin
                $display("    [Cycle %0d] Buffer empty, fetch stalled", i);
            end
        end
        
        check_assertion("Buffer drained while memory stalled",
                       cycles_with_valid_output > 0,
                       "Buffer should have provided valid output before draining");
        
        check_assertion("Fetch stalls when buffer empty",
                       dut.ib.is_empty == 1'b1,
                       "Buffer should be empty after draining");
        
        check_assertion("No valid output when buffer empty",
                       fetch_val_o == 1'b0,
                       "fetch_val should be 0 when buffer empty");
        
        imem_req_rdy_i = 1; // Release memory stall
        
        wait_for_fetch(2);
        
        check_assertion("Fetch resumes after memory ready",
                       fetch_val_o == 1'b1,
                       "Fetch should resume after memory becomes ready");
        
        $display("  Memory resumed, buffer refilling");
        display_fetch_output();
        
        $display("");
        
        //-------------------------------------------------------------
        // TEST 5: Branch/Jump Redirect (Flush)
        //-------------------------------------------------------------
        $display("[TEST 5] Branch/Jump Redirect (Flush)");
        redirect_target = 32'h0000_0010;
        $display("  Redirecting to PC = 0x%h", redirect_target);
        
        pc_sel_i = 3'b001;      // Select ROB PC
        rob_pc_i = redirect_target;
        flush_i  = 1;           // Assert flush
        
        @(posedge clk);
        
        check_assertion("PC redirected on flush",
                       imem_req_packet == redirect_target,
                       $sformatf("Expected PC=0x%h, got 0x%h", redirect_target, imem_req_packet));
        
        flush_i = 0;            // De-assert flush
        pc_sel_i = 3'b000;      // Back to sequential
        
        // Wait for instruction buffer to refill
        wait_for_fetch(2);
        
        check_assertion("Fetch from redirected PC",
                       inst_pcs_o[0] == redirect_target,
                       $sformatf("Expected inst PC=0x%h, got 0x%h", redirect_target, inst_pcs_o[0]));
        
        $display("  Redirect successful");
        display_fetch_output();
        
        // Continue sequential from new PC
        wait_for_fetch(1);
        
        check_assertion("Sequential fetch after redirect",
                       inst_pcs_o[0] == (redirect_target + 8),
                       $sformatf("Expected PC=0x%h, got 0x%h", redirect_target + 8, inst_pcs_o[0]));
        
        $display("");
        
        //-------------------------------------------------------------
        // TEST 6: Instruction Buffer Behavior
        //-------------------------------------------------------------
        $display("[TEST 6] Instruction Buffer Fill and Drain Independence");
        $display("  Testing buffer decoupling between fetch and decode...");
        
        // Scenario 1: Fill buffer (decoder stalled, memory running)
        $display("  Scenario 1: Filling buffer...");
        decode_rdy_i = 0;  // Stall decoder
        imem_req_rdy_i = 1; // Memory running
        
        wait_for_fetch(INST_BUF_DEPTH + 2);
        
        check_assertion("Buffer fills when decoder stalled and memory running",
                       dut.ib.is_full == 1'b1,
                       $sformatf("Buffer full flag=%b, expected 1", dut.ib.is_full));
        
        $display("    Buffer filled: is_full=%b, entries=%0d", 
                 dut.ib.is_full, dut.ib.write_ptr - dut.ib.read_ptr);
        
        // Scenario 2: Drain buffer (memory stalled, decoder running)
        $display("  Scenario 2: Draining buffer...");
        decode_rdy_i = 1;  // Resume decoder
        imem_req_rdy_i = 0; // Stall memory
        
        drain_cycles = 0;
        while (!dut.ib.is_empty && drain_cycles < INST_BUF_DEPTH + 5) begin
            @(posedge clk);
            drain_cycles++;
            if (fetch_val_o) begin
                $display("    [Drain cycle %0d] PC=0x%h, remaining=%0d", 
                         drain_cycles, inst_pcs_o[0], dut.ib.write_ptr - dut.ib.read_ptr);
            end
        end
        
        check_assertion("Buffer drains independently when memory stalled",
                       dut.ib.is_empty == 1'b1,
                       $sformatf("Buffer empty flag=%b, expected 1", dut.ib.is_empty));
        
        $display("    Buffer drained in %0d cycles", drain_cycles);
        
        // Scenario 3: Both running (normal operation)
        $display("  Scenario 3: Normal operation (both running)...");
        decode_rdy_i = 1;
        imem_req_rdy_i = 1;
        
        wait_for_fetch(5);
        
        check_assertion("Buffer operates normally",
                       !dut.ib.is_empty && !dut.ib.is_full,
                       "Buffer should be neither empty nor full during normal operation");
        
        $display("    Normal operation: is_empty=%b, is_full=%b", 
                 dut.ib.is_empty, dut.ib.is_full);
        
        $display("");
        
        //-------------------------------------------------------------
        // TEST 7: Multiple Redirects
        //-------------------------------------------------------------
        $display("[TEST 7] Multiple Consecutive Redirects");
        
        targets = '{32'h0000_0020, 32'h0000_0030, 32'h0000_0040};
        
        for (int i = 0; i < 3; i++) begin
            $display("  Redirect %0d to 0x%h", i, targets[i]);
            
            pc_sel_i = 3'b001;
            rob_pc_i = targets[i];
            flush_i = 1;
            
            @(posedge clk);
            
            check_assertion($sformatf("Redirect %0d PC updated", i),
                           imem_req_packet == targets[i],
                           $sformatf("Expected PC=0x%h, got 0x%h", targets[i], imem_req_packet));
            
            flush_i = 0;
            pc_sel_i = 3'b000;
            
            wait_for_fetch(2);
        end
        
        $display("");
        
        //-------------------------------------------------------------
        // TEST 9: Program Order Maintained Through Stalls
        //-------------------------------------------------------------
        $display("[TEST 9] Program Order Maintained Through Stalls and Redirects");
        
        // Reset to known state
        pc_sel_i = 3'b001;
        rob_pc_i = PC_RESET;
        flush_i = 1;
        @(posedge clk);
        flush_i = 0;
        pc_sel_i = 3'b000;
        
        wait_for_fetch(2);
        
        // Scenario 1: Decoder stall shouldn't affect order
        $display("  Scenario 1: Program order through decoder stall...");
        
        @(posedge clk);
        if (fetch_val_o) begin
            inst_before_stall = insts_o[0];
            pc_before_stall = inst_pcs_o[0];
        end
        
        decode_rdy_i = 0; // Stall
        repeat(2) @(posedge clk);
        
        check_assertion("Output held during decoder stall",
                       insts_o[0] == inst_before_stall,
                       $sformatf("Instruction changed during stall: 0x%h->0x%h", 
                                inst_before_stall, insts_o[0]));
        
        decode_rdy_i = 1; // Resume
        @(posedge clk);
        
        if (fetch_val_o) begin
            idx = (pc_before_stall - PC_RESET) / 4;
            expected_next = expected_sequence[idx + 2]; // Next in sequence after the pair
            
            check_assertion("Next instruction in sequence after stall",
                           insts_o[0] == expected_next,
                           $sformatf("Expected 0x%h, got 0x%h", expected_next, insts_o[0]));
            
            $display("    Order maintained: 0x%h -> 0x%h ✓", inst_before_stall, insts_o[0]);
        end
        
        // Scenario 2: Redirect and verify new sequence
        $display("  Scenario 2: Program order after redirect...");
        
        redirect_addr = 32'h00000020; // Byte address 32 = word 8
        redirect_idx = redirect_addr / 4; // Index 8 in sequence
        
        pc_sel_i = 3'b001;
        rob_pc_i = redirect_addr;
        flush_i = 1;
        
        @(posedge clk);
        flush_i = 0;
        pc_sel_i = 3'b000;
        
        wait_for_fetch(2);
        
        if (fetch_val_o) begin
            check_assertion("First inst after redirect matches target",
                           insts_o[0] == expected_sequence[redirect_idx],
                           $sformatf("Expected 0x%h at addr 0x%h, got 0x%h", 
                                    expected_sequence[redirect_idx], redirect_addr, insts_o[0]));
            
            check_assertion("Second inst after redirect is sequential",
                           insts_o[1] == expected_sequence[redirect_idx + 1],
                           $sformatf("Expected 0x%h, got 0x%h", 
                                    expected_sequence[redirect_idx + 1], insts_o[1]));
            
            $display("    Redirect to 0x%h: got 0x%h, 0x%h ✓", 
                     redirect_addr, insts_o[0], insts_o[1]);
        end
        
        // Continue and verify next pair
        @(posedge clk);
        
        if (fetch_val_o) begin
            check_assertion("Sequence continues correctly",
                           insts_o[0] == expected_sequence[redirect_idx + 2],
                           $sformatf("Expected 0x%h, got 0x%h", 
                                    expected_sequence[redirect_idx + 2], insts_o[0]));
            
            $display("    Next pair: 0x%h, 0x%h ✓", insts_o[0], insts_o[1]);
        end
        
        $display("");
        
        //-------------------------------------------------------------
        // End of Tests
        //-------------------------------------------------------------
        wait_for_fetch(5);
        
        $display("========================================");
        $display("  All Tests Complete!");
        $display("========================================");
        $display("  Tests Passed:  %0d", tests_passed);
        $display("  Tests Failed:  %0d", tests_failed);
        $display("  Total Checks:  %0d", assertions_checked);
        $display("========================================");
        
        if (tests_failed == 0) begin
            $display("  ✓ ALL TESTS PASSED!");
        end else begin
            $display("  ✗ SOME TESTS FAILED!");
            $fatal(1, "Test failures detected");
        end
        
        $finish;
    end

    //-------------------------------------------------------------
    // Timeout Watchdog
    //-------------------------------------------------------------
    initial begin
        #100000;
        $display("\n[ERROR] Testbench timeout!");
        $finish;
    end

endmodule