`timescale 1ns/1ps
import riscv_isa_pkg::*;
import uarch_pkg::*;

module dispatch_tb;
    

    //-------------------------------------------------------------
    // Test Statistics
    //-------------------------------------------------------------
    int tests_passed = 0;
    int tests_failed = 0;
    int assertions_checked = 0;

    //-------------------------------------------------------------
    // Clock Generation
    //-------------------------------------------------------------
    logic clk;
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //-------------------------------------------------------------
    // Stimulus Signals (inputs to DUT)
    //-------------------------------------------------------------
    instruction_t            renamed_insts_i    [PIPE_WIDTH-1:0];
    logic [PIPE_WIDTH-1:0]   alu_rs_rdy_i;
    logic [PIPE_WIDTH-1:0]   mdu_rs_rdy_i;
    logic [PIPE_WIDTH-1:0]   lsq_ld_rdy_i;
    logic [PIPE_WIDTH-1:0]   lsq_st_rdy_i;
    logic [PIPE_WIDTH-1:0]   rob_rdy_i;

    //-------------------------------------------------------------
    // Monitored Signals (outputs from DUT)
    //-------------------------------------------------------------
    logic                    dispatch_rdy_o;
    logic [PIPE_WIDTH-1:0]   alu_rs_we_o;
    logic [PIPE_WIDTH-1:0]   mdu_rs_we_o;
    logic [PIPE_WIDTH-1:0]   lsq_ld_we_o;
    logic [PIPE_WIDTH-1:0]   lsq_st_we_o;
    logic [PIPE_WIDTH-1:0]   rob_we_o;
    instruction_t            alu_rs_entries_o   [PIPE_WIDTH-1:0];
    instruction_t            mdu_rs_entries_o   [PIPE_WIDTH-1:0];
    instruction_t            lsq_ld_entries_o   [PIPE_WIDTH-1:0];
    instruction_t            lsq_st_entries_o   [PIPE_WIDTH-1:0];
    rob_entry_t              rob_entries_o      [PIPE_WIDTH-1:0];

    //-------------------------------------------------------------
    // DUT Instantiation
    //-------------------------------------------------------------
    dispatch dut (
        .dispatch_rdy(dispatch_rdy_o),
        .renamed_insts(renamed_insts_i),
        
        .alu_rs_rdy(alu_rs_rdy_i),
        .mdu_rs_rdy(mdu_rs_rdy_i),
        .lsq_ld_rdy(lsq_ld_rdy_i),
        .lsq_st_rdy(lsq_st_rdy_i),
        
        .alu_rs_we(alu_rs_we_o),
        .mdu_rs_we(mdu_rs_we_o),
        .lsq_ld_we(lsq_ld_we_o),
        .lsq_st_we(lsq_st_we_o),
        
        .alu_rs_entries(alu_rs_entries_o),
        .mdu_rs_entries(mdu_rs_entries_o),
        .lsq_ld_entries(lsq_ld_entries_o),
        .lsq_st_entries(lsq_st_entries_o),
        
        .rob_rdy(rob_rdy_i),
        .rob_we(rob_we_o),
        .rob_entries(rob_entries_o)
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
    
    // Task: Initialize all stimulus signals
    task automatic init_signals();
        for (int i = 0; i < PIPE_WIDTH; i++) begin
            renamed_insts_i[i] = '{default:'0};
        end
        alu_rs_rdy_i = '1;
        mdu_rs_rdy_i = '1;
        lsq_ld_rdy_i = '1;
        lsq_st_rdy_i = '1;
        rob_rdy_i = 2'b11;  // Both slots available
        #1;
    endtask

    // Task: Create a renamed instruction
    task automatic create_renamed_inst(
        output instruction_t inst,
        input logic [CPU_ADDR_BITS-1:0] pc,
        input logic [4:0] rd,
        input logic has_rd,
        input logic [6:0] opcode,
        input logic [6:0] funct7,
        input logic [TAG_WIDTH-1:0] dest_tag
    );
        inst = '{default:'0};
        inst.is_valid = 1'b1;
        inst.pc = pc;
        inst.rd = rd;
        inst.has_rd = has_rd;
        inst.opcode = opcode;
        inst.funct7 = funct7;
        inst.dest_tag = dest_tag;
    endtask

    //-------------------------------------------------------------
    // Test Stimulus
    //-------------------------------------------------------------
    initial begin
        $dumpfile("dispatch_tb.vcd");
        $dumpvars(0, dispatch_tb);
        
        $display("========================================");
        $display("  Dispatch Stage Testbench Started");
        $display("========================================\n");
        
        init_signals();
        
        //-------------------------------------------------------------
        // TEST 1: Single ALU Instruction
        //-------------------------------------------------------------
        $display("[TEST 1] Single ALU Instruction Dispatch");
        $display("  Sending: ADD (ALU instruction) in slot 0");
        
        create_renamed_inst(renamed_insts_i[0], 32'h1000, 5'd3, 1'b1, OPC_ARI_RTYPE, 7'b0000000, 5'd10);
        renamed_insts_i[1] = '{default:'0};
        
        alu_rs_rdy_i = 2'b11;
        rob_rdy_i = 2'b11;
        
        #1;
        
        check_assertion("Dispatch ready",
                       dispatch_rdy_o == 1'b1,
                       $sformatf("Expected dispatch_rdy=1, got %b", dispatch_rdy_o));
        
        check_assertion("ALU RS write enable [0]",
                       alu_rs_we_o[0] == 1'b1,
                       $sformatf("Expected alu_rs_we[0]=1, got %b", alu_rs_we_o[0]));
        
        check_assertion("No ALU RS write [1]",
                       alu_rs_we_o[1] == 1'b0,
                       $sformatf("Expected alu_rs_we[1]=0, got %b", alu_rs_we_o[1]));
        
        check_assertion("ROB write enable [0]",
                       rob_we_o[0] == 1'b1,
                       $sformatf("Expected rob_we[0]=1, got %b", rob_we_o[0]));
        
        check_assertion("No LSQ/MDU writes",
                       (lsq_ld_we_o == 2'b00) && (lsq_st_we_o == 2'b00) && (mdu_rs_we_o == 2'b00),
                       "Expected no LSQ or MDU writes");
        
        $display("");
        
        //-------------------------------------------------------------
        // TEST 2: Two ALU Instructions
        //-------------------------------------------------------------
        $display("[TEST 2] Two ALU Instructions Dispatch");
        
        create_renamed_inst(renamed_insts_i[0], 32'h1004, 5'd5, 1'b1, OPC_ARI_RTYPE, 7'b0000000, 5'd11);
        create_renamed_inst(renamed_insts_i[1], 32'h1008, 5'd6, 1'b1, OPC_ARI_ITYPE, 7'b0000000, 5'd12);
        
        alu_rs_rdy_i = 2'b11;
        rob_rdy_i = 2'b11;
        
        #1;
        
        check_assertion("Both ALU writes",
                       alu_rs_we_o == 2'b11,
                       $sformatf("Expected alu_rs_we=11, got %b", alu_rs_we_o));
        
        check_assertion("Both ROB writes",
                       rob_we_o == 2'b11,
                       $sformatf("Expected rob_we=11, got %b", rob_we_o));
        
        $display("");
        
        //-------------------------------------------------------------
        // TEST 3: Load Instruction
        //-------------------------------------------------------------
        $display("[TEST 3] Load Instruction Dispatch");
        
        create_renamed_inst(renamed_insts_i[0], 32'h100C, 5'd7, 1'b1, OPC_LOAD, 7'b0000000, 5'd13);
        renamed_insts_i[1] = '{default:'0};
        
        lsq_ld_rdy_i = 2'b11;
        rob_rdy_i = 2'b11;
        
        #1;
        
        check_assertion("LSQ LD write enable",
                       lsq_ld_we_o[0] == 1'b1,
                       $sformatf("Expected lsq_ld_we[0]=1, got %b", lsq_ld_we_o[0]));
        
        check_assertion("No ALU write",
                       alu_rs_we_o == 2'b00,
                       $sformatf("Expected alu_rs_we=00, got %b", alu_rs_we_o));
        
        $display("");
        
        //-------------------------------------------------------------
        // TEST 4: Store Instruction
        //-------------------------------------------------------------
        $display("[TEST 4] Store Instruction Dispatch");
        
        create_renamed_inst(renamed_insts_i[0], 32'h1010, 5'd0, 1'b0, OPC_STORE, 7'b0000000, 5'd14);
        renamed_insts_i[1] = '{default:'0};
        
        lsq_st_rdy_i = 2'b11;
        rob_rdy_i = 2'b11;
        
        #1;
        
        check_assertion("LSQ ST write enable",
                       lsq_st_we_o[0] == 1'b1,
                       $sformatf("Expected lsq_st_we[0]=1, got %b", lsq_st_we_o[0]));
        
        check_assertion("ROB entry has_rd=0 for store",
                       rob_entries_o[0].has_rd == 1'b0,
                       $sformatf("Expected has_rd=0, got %b", rob_entries_o[0].has_rd));
        
        $display("");
        
        //-------------------------------------------------------------
        // TEST 5: MDU Instruction
        //-------------------------------------------------------------
        $display("[TEST 5] MDU (MUL) Instruction Dispatch");
        
        create_renamed_inst(renamed_insts_i[0], 32'h1014, 5'd8, 1'b1, OPC_ARI_RTYPE, FNC7_MULDIV, 5'd15);
        renamed_insts_i[1] = '{default:'0};
        
        mdu_rs_rdy_i = 2'b11;
        rob_rdy_i = 2'b11;
        
        #1;
        
        check_assertion("MDU RS write enable",
                       mdu_rs_we_o[0] == 1'b1,
                       $sformatf("Expected mdu_rs_we[0]=1, got %b", mdu_rs_we_o[0]));
        
        check_assertion("No ALU write for MDU",
                       alu_rs_we_o == 2'b00,
                       $sformatf("Expected alu_rs_we=00, got %b", alu_rs_we_o));
        
        $display("");
        
        //-------------------------------------------------------------
        // TEST 6: Mixed Instructions (ALU + Load)
        //-------------------------------------------------------------
        $display("[TEST 6] Mixed Instructions (ALU + Load)");
        
        create_renamed_inst(renamed_insts_i[0], 32'h1018, 5'd9, 1'b1, OPC_ARI_RTYPE, 7'b0000000, 5'd16);
        create_renamed_inst(renamed_insts_i[1], 32'h101C, 5'd10, 1'b1, OPC_LOAD, 7'b0000000, 5'd17);
        
        alu_rs_rdy_i = 2'b11;
        lsq_ld_rdy_i = 2'b11;
        rob_rdy_i = 2'b11;
        
        #1;
        
        check_assertion("ALU write for inst[0]",
                       alu_rs_we_o[0] == 1'b1,
                       $sformatf("Expected alu_rs_we[0]=1, got %b", alu_rs_we_o[0]));
        
        check_assertion("LSQ LD write for inst[1]",
                       lsq_ld_we_o[1] == 1'b1,
                       $sformatf("Expected lsq_ld_we[1]=1, got %b", lsq_ld_we_o[1]));
        
        check_assertion("Both ROB writes",
                       rob_we_o == 2'b11,
                       $sformatf("Expected rob_we=11, got %b", rob_we_o));
        
        $display("");
        
        //-------------------------------------------------------------
        // TEST 7: ALU RS Full (slot 0 only available)
        //-------------------------------------------------------------
        $display("[TEST 7] ALU RS Partial Availability - Should Stall");
        $display("  Two ALU instructions, but only slot[0] available");
        
        create_renamed_inst(renamed_insts_i[0], 32'h1020, 5'd11, 1'b1, OPC_ARI_RTYPE, 7'b0000000, 5'd18);
        create_renamed_inst(renamed_insts_i[1], 32'h1024, 5'd12, 1'b1, OPC_ARI_RTYPE, 7'b0000000, 5'd19);
        
        alu_rs_rdy_i = 2'b01;  // Only slot[0] available
        rob_rdy_i = 2'b11;
        
        #1;
        
        check_assertion("Dispatch NOT ready (stalled)",
                       dispatch_rdy_o == 1'b0,
                       $sformatf("Expected dispatch_rdy=0 (stall), got %b", dispatch_rdy_o));
        
        check_assertion("No writes during stall",
                       (alu_rs_we_o == 2'b00) && (rob_we_o == 2'b00),
                       "Expected no writes during stall");
        
        $display("");
        
        //-------------------------------------------------------------
        // TEST 8: ROB Full (only 1 slot available)
        //-------------------------------------------------------------
        $display("[TEST 8] ROB Partial Availability - Should Stall");
        
        create_renamed_inst(renamed_insts_i[0], 32'h1028, 5'd13, 1'b1, OPC_ARI_RTYPE, 7'b0000000, 5'd20);
        create_renamed_inst(renamed_insts_i[1], 32'h102C, 5'd14, 1'b1, OPC_ARI_RTYPE, 7'b0000000, 5'd21);
        
        alu_rs_rdy_i = 2'b11;
        rob_rdy_i = 2'b01;  // Only 1 ROB slot available
        
        #1;
        
        check_assertion("Dispatch NOT ready (ROB full)",
                       dispatch_rdy_o == 1'b0,
                       $sformatf("Expected dispatch_rdy=0, got %b", dispatch_rdy_o));
        
        $display("");
        
        //-------------------------------------------------------------
        // TEST 9: Invalid Instructions Pass Through
        //-------------------------------------------------------------
        $display("[TEST 9] Invalid Instructions (Bubbles)");
        
        renamed_insts_i[0] = '{default:'0};
        renamed_insts_i[1] = '{default:'0};
        
        alu_rs_rdy_i = 2'b11;
        rob_rdy_i = 2'b11;
        
        #1;
        
        check_assertion("Dispatch ready for invalid insts",
                       dispatch_rdy_o == 1'b1,
                       $sformatf("Expected dispatch_rdy=1, got %b", dispatch_rdy_o));
        
        check_assertion("No writes for invalid insts",
                       (alu_rs_we_o == 2'b00) && (rob_we_o == 2'b00) && 
                       (lsq_ld_we_o == 2'b00) && (lsq_st_we_o == 2'b00) && (mdu_rs_we_o == 2'b00),
                       "Expected no writes");
        
        $display("");
        
        //-------------------------------------------------------------
        // TEST 10: Same Queue Collision (2 ALUs to same RS)
        //-------------------------------------------------------------
        $display("[TEST 10] Same Queue Collision Handling");
        $display("  Two ALU instructions targeting same RS");
        
        create_renamed_inst(renamed_insts_i[0], 32'h1030, 5'd15, 1'b1, OPC_ARI_RTYPE, 7'b0000000, 5'd22);
        create_renamed_inst(renamed_insts_i[1], 32'h1034, 5'd16, 1'b1, OPC_ARI_ITYPE, 7'b0000000, 5'd23);
        
        alu_rs_rdy_i = 2'b11;  // Both slots available
        rob_rdy_i = 2'b11;
        
        #1;
        
        check_assertion("Both dispatch successfully",
                       dispatch_rdy_o == 1'b1,
                       $sformatf("Expected dispatch_rdy=1, got %b", dispatch_rdy_o));
        
        check_assertion("ALU writes to both slots",
                       alu_rs_we_o == 2'b11,
                       $sformatf("Expected alu_rs_we=11, got %b", alu_rs_we_o));
        
        $display("");
        
        //-------------------------------------------------------------
        // End of Tests
        //-------------------------------------------------------------
        #10;
        
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
        #10000;
        $display("\n[ERROR] Testbench timeout!");
        $finish;
    end

endmodule