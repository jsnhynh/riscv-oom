`timescale 1ns/1ps
import riscv_isa_pkg::*;
import uarch_pkg::*;

module cpu_tb;

    //-------------------------------------------------------------
    // Test Configuration
    //-------------------------------------------------------------
    localparam TEST_FILE = "rv32im_test_fixed.hex";
    localparam MAX_CYCLES = 2000;

    //-------------------------------------------------------------
    // Test Statistics
    //-------------------------------------------------------------
    int tests_passed = 0;
    int tests_failed = 0;
    int assertions_checked = 0;
    int cycle_count = 0;
    int instruction_count = 0;
    real ipc;

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
    // DUT Instantiation
    //-------------------------------------------------------------
    cpu #(
        .SIMPLE_MEM_MODE(1)
    ) dut (
        .clk(clk),
        .rst(rst)
    );

    //-------------------------------------------------------------
    // Helper Tasks
    //-------------------------------------------------------------
    
    task automatic check_register(
        input string test_name,
        input int reg_num,
        input logic [31:0] expected_value
    );
        logic [31:0] actual_value;
        actual_value = dut.core0.rename_stage.prf_inst.data_reg[reg_num];
        
        assertions_checked++;
        if (actual_value == expected_value) begin
            $display("  [PASS] %s: x%0d = 0x%08h", test_name, reg_num, actual_value);
            tests_passed++;
        end else begin
            $display("  [FAIL] %s: x%0d = 0x%08h (expected 0x%08h)", 
                     test_name, reg_num, actual_value, expected_value);
            tests_failed++;
        end
    endtask

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

    task automatic wait_for_completion();
        logic [31:0] completion_reg;
        logic done;
        instruction_count = 0;
        done = 0;
        cycle_count = 1;
        
        $display("\n[INFO] Waiting for program completion (x31 = 0xFF)...\n");
        
        while (!done && cycle_count < MAX_CYCLES) begin
            @(posedge clk);
            cycle_count++;
            instruction_count += dut.core0.commit_stage.commit_cnt;
            ipc = real'(instruction_count) / real'(cycle_count);

            completion_reg = dut.core0.rename_stage.prf_inst.data_reg[31];
            
            if (completion_reg == 32'hFF) begin
                done = 1;
                $display("[INFO] Program completed after %0d cycles", cycle_count);
                $display("[INFO] Instructions committed: %0d", instruction_count);
            end
        end
        
        if (!done) begin
            $display("[WARNING] Program did not complete within %0d cycles", MAX_CYCLES);
            $display("[WARNING] Final instruction count: %0d", instruction_count);
            $display("[WARNING] x31 = 0x%08h\n", completion_reg);
        end
        
        // Wait for pipeline to settle
        repeat(10) @(posedge clk);
        cycle_count += 10;
    endtask

    task automatic dump_registers();
        $display("\n========================================");
        $display("  Register File State");
        $display("========================================");
        for (int i = 0; i < 32; i += 4) begin
            $display("  x%02d=0x%08h  x%02d=0x%08h  x%02d=0x%08h  x%02d=0x%08h",
                     i,   dut.core0.rename_stage.prf_inst.data_reg[i],
                     i+1, dut.core0.rename_stage.prf_inst.data_reg[i+1],
                     i+2, dut.core0.rename_stage.prf_inst.data_reg[i+2],
                     i+3, dut.core0.rename_stage.prf_inst.data_reg[i+3]);
        end
        $display("========================================\n");
    endtask

    task automatic dump_performance_stats();
        $display("\n========================================");
        $display("  Performance Statistics");
        $display("========================================");
        $display("  Total Cycles:           %0d", cycle_count);
        $display("  Instructions Committed: %0d", instruction_count);
        if (cycle_count > 0 && instruction_count > 0) begin
            ipc = real'(instruction_count) / real'(cycle_count);
            $display("  IPC (Instructions/Cycle): %0.3f", ipc);
            $display("  CPI (Cycles/Instruction): %0.3f", 1.0/ipc);
        end
        $display("========================================\n");
    endtask

    //-------------------------------------------------------------
    // Test Stimulus
    //-------------------------------------------------------------
    initial begin
        $dumpfile("cpu_tb.vcd");
        $dumpvars(0, cpu_tb);
        
        $display("========================================");
        $display("  RV32IM CPU Testbench");
        $display("========================================");
        $display("  Test Program: %s", TEST_FILE);
        $display("  Max Cycles: %0d", MAX_CYCLES);
        $display("========================================\n");
        
        // Reset
        rst = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        
        // Wait for program to complete
        wait_for_completion();
        
        // Dump performance statistics
        dump_performance_stats();
        
        // Dump register file
        dump_registers();
        
        //-------------------------------------------------------------
        // Verify Results
        //-------------------------------------------------------------
        $display("\n========================================");
        $display("  Test Verification");
        $display("========================================\n");
        
        // Test 1: Basic Arithmetic
        $display("=== Test 1: Basic Arithmetic ===");
        check_register("ADD: 5 + 7", 3, 32'd12);
        check_register("SUB: 7 - 5", 4, 32'd2);
        
        // Test 2: Logical Operations
        $display("\n=== Test 2: Logical Operations ===");
        check_register("AND: 5 & 7", 5, 32'd5);
        check_register("OR: 5 | 7", 6, 32'd7);
        check_register("XOR: 5 ^ 7", 7, 32'd2);
        check_register("ANDI: 7 & 3", 8, 32'd3);
        check_register("ORI: 5 | 8", 9, 32'd13);
        check_register("XORI: 7 ^ 15", 10, 32'd8);
        
        // Test 3: Shifts
        $display("\n=== Test 3: Shift Operations ===");
        check_register("SLLI: 5 << 2", 11, 32'd20);
        check_register("SRLI: 7 >> 1", 12, 32'd3);
        check_register("ADDI: -8", 13, 32'hFFFFFFF8);
        check_register("SRAI: -8 >> 1", 14, 32'hFFFFFFFC);  // -4
        check_register("SLL: 5 << 7", 15, 32'd640);
        check_register("SRL: 7 >> 5", 16, 32'd0);
        check_register("SRA: -8 >> 5", 17, 32'hFFFFFFFF);  // -1
        
        // Test 4: Comparisons
        $display("\n=== Test 4: Comparison Operations ===");
        check_register("SLT: 5 < 7", 18, 32'd1);
        check_register("SLT: 7 < 5", 19, 32'd0);
        check_register("SLTU: 0xFFFFFFF8 < 5", 20, 32'd0);
        check_register("SLTI: 5 < 10", 21, 32'd1);
        check_register("SLTIU: 5 < 3", 22, 32'd0);
        
        // Test 5: Upper Immediates
        $display("\n=== Test 5: Upper Immediate Operations ===");
        check_register("LUI: 0x12345000", 23, 32'h12345000);
        check_assertion("AUIPC executed", 
                       dut.core0.rename_stage.prf_inst.data_reg[24] != 32'h0,
                       "AUIPC result is zero");
        
        // Test 6: Branches
        $display("\n=== Test 6: Branch Operations ===");
        check_register("Branches completed", 25, 32'd11);
        
        // Test 7: JAL/JALR
        $display("\n=== Test 7: JAL/JALR Operations ===");
        check_register("JAL/JALR completed", 25, 32'd11);
        check_assertion("JAL saved return address",
                       dut.core0.rename_stage.prf_inst.data_reg[26] != 32'h0,
                       "x26 is zero");
        check_assertion("JAL backward saved return",
                       dut.core0.rename_stage.prf_inst.data_reg[27] != 32'h0,
                       "x27 is zero");
        check_assertion("JALR saved return address",
                       dut.core0.rename_stage.prf_inst.data_reg[29] != 32'h0,
                       "x29 is zero");
        
        // Test 8: Memory Operations (Store then Load)
        $display("\n=== Test 9: Memory Operations ===");
        check_register("LW: Word load (42)", 11, 32'd42);
        check_register("LW: Word load (100)", 12, 32'd100);
        check_register("LBU: Unsigned byte (0xAB)", 13, 32'hAB);
        check_register("LB: Signed byte (0xAB)", 14, 32'hFFFFFFAB);
        check_register("LHU: Unsigned halfword (0x123)", 15, 32'h123);
        check_register("LH: Signed halfword (0x123)", 16, 32'h123);
        check_register("LB: Signed byte (0xFF)", 17, 32'hFFFFFFFF);
        check_register("LBU: Unsigned byte (0xFF)", 18, 32'hFF);
        check_register("LH: Signed halfword (0xFFFF)", 19, 32'hFFFFFFFF);
        check_register("LHU: Unsigned halfword (0xFFFF)", 20, 32'hFFFF);
        
        // Test 9: Multiply/Divide
        $display("\n=== Test 8: Multiply/Divide (M extension) ===");
        check_register("MUL: 6 * 7", 3, 32'd42);
        check_register("MUL: 100 * 10", 6, 32'd1000);
        check_register("DIV: 100 / 10", 7, 32'd10);
        check_register("MUL: 6 * -3", 10, 32'hFFFFFFEE);  // -18
        
        // Completion marker
        $display("\n=== Completion Check ===");
        check_register("Completion marker", 31, 32'hFF);
        
        //-------------------------------------------------------------
        // Test Summary
        //-------------------------------------------------------------
        $display("\n========================================");
        $display("  Test Summary");
        $display("========================================");
        $display("  Execution Cycles:     %0d", cycle_count);
        $display("  Instructions Retired: %0d", instruction_count);
        $display("  IPC:                  %0.3f", ipc);
        $display("  Tests Passed:         %0d", tests_passed);
        $display("  Tests Failed:         %0d", tests_failed);
        $display("  Total Checks:         %0d", assertions_checked);
        $display("========================================");
        
        if (tests_failed == 0) begin
            $display("\n  ✓✓✓ ALL TESTS PASSED! ✓✓✓\n");
        end else begin
            $display("\n  ✗✗✗ SOME TESTS FAILED! ✗✗✗\n");
        end
        $display("========================================\n");
        
        if (tests_failed > 0) begin
            $fatal(1, "Test failures detected");
        end
        
        $finish;
    end

    //-------------------------------------------------------------
    // Timeout Watchdog
    //-------------------------------------------------------------
    initial begin
        #(MAX_CYCLES * CLK_PERIOD * 2);
        $display("\n[ERROR] Global testbench timeout!");
        $display("[ERROR] Cycles: %0d, Instructions: %0d", cycle_count, instruction_count);
        $finish;
    end

endmodule