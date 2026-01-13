`timescale 1ns/1ps
import riscv_isa_pkg::*;
import uarch_pkg::*;

module btb_tb;

    //-------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------
    localparam ENTRIES   = 64;
    localparam TAG_WIDTH = 12;
    localparam BANK_ENTRIES = ENTRIES / 2;
    localparam IDX_WIDTH = $clog2(BANK_ENTRIES);

    localparam BRANCH_COND = 2'b00;
    localparam BRANCH_JUMP = 2'b01;
    localparam BRANCH_CALL = 2'b10;
    localparam BRANCH_RET  = 2'b11;

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
    logic [CPU_ADDR_BITS-1:0]   pc;
    logic [1:0]                 pred_hit;
    logic [CPU_ADDR_BITS-1:0]   pred_targs [1:0];
    logic [1:0]                 pred_types [1:0];

    logic                       update_val;
    logic [CPU_ADDR_BITS-1:0]   update_pc;
    logic [CPU_ADDR_BITS-1:0]   update_targ;
    logic [1:0]                 update_type;
    logic                       update_taken;

    //-------------------------------------------------------------
    // Test Variables
    //-------------------------------------------------------------
    logic [31:0] diff_tag_pc;
    logic [31:0] aliased_pc;

    //-------------------------------------------------------------
    // DUT
    //-------------------------------------------------------------
    btb #(
        .ENTRIES(ENTRIES),
        .TAG_WIDTH(TAG_WIDTH)
    ) dut (.*);

    //-------------------------------------------------------------
    // Helper Functions
    //-------------------------------------------------------------
    function automatic logic [IDX_WIDTH-1:0] get_index(input logic [CPU_ADDR_BITS-1:0] addr);
        return addr[IDX_WIDTH+2:3];
    endfunction

    function automatic logic [TAG_WIDTH-1:0] get_tag(input logic [CPU_ADDR_BITS-1:0] addr);
        return addr[TAG_WIDTH+IDX_WIDTH+2:IDX_WIDTH+3];
    endfunction

    function automatic string btype_to_str(input logic [1:0] btype);
        case (btype)
            BRANCH_COND: return "COND";
            BRANCH_JUMP: return "JUMP";
            BRANCH_CALL: return "CALL";
            BRANCH_RET:  return "RET";
            default:     return "????";
        endcase
    endfunction

    //-------------------------------------------------------------
    // Tasks
    //-------------------------------------------------------------
    task automatic clear_signals();
        pc           = '0;
        update_val   = 1'b0;
        update_pc    = '0;
        update_targ  = '0;
        update_type  = 2'b00;
        update_taken = 1'b0;
    endtask

    task automatic do_update(
        input logic [CPU_ADDR_BITS-1:0] upc,
        input logic [CPU_ADDR_BITS-1:0] utarg,
        input logic [1:0]               utype,
        input logic                     utaken
    );
        @(negedge clk);
        update_val   = 1'b1;
        update_pc    = upc;
        update_targ  = utarg;
        update_type  = utype;
        update_taken = utaken;
        @(negedge clk);  // Posedge in between latches it
        update_val   = 1'b0;
    endtask

    task automatic check_pred(
        input string                    name,
        input logic [CPU_ADDR_BITS-1:0] check_pc,
        input logic                     exp_hit_0,
        input logic                     exp_hit_1,
        input logic [CPU_ADDR_BITS-1:0] exp_targ_0 = '0,
        input logic [CPU_ADDR_BITS-1:0] exp_targ_1 = '0,
        input logic [1:0]               exp_type_0 = '0,
        input logic [1:0]               exp_type_1 = '0
    );
        string info, errs;
        logic pass;
        
        @(negedge clk);
        pc = check_pc;
        @(negedge clk);  // Wait for combinational to settle
        
        info = $sformatf("hit=[%0d,%0d] targ=[0x%h,0x%h] type=[%s,%s]",
                         pred_hit[0], pred_hit[1],
                         pred_targs[0], pred_targs[1],
                         btype_to_str(pred_types[0]), btype_to_str(pred_types[1]));
        
        pass = 1;
        errs = "";
        
        if (pred_hit[0] !== exp_hit_0) begin pass = 0; errs = $sformatf("%s hit[0]=%0d(exp %0d)", errs, pred_hit[0], exp_hit_0); end
        if (pred_hit[1] !== exp_hit_1) begin pass = 0; errs = $sformatf("%s hit[1]=%0d(exp %0d)", errs, pred_hit[1], exp_hit_1); end
        if (exp_hit_0 && pred_targs[0] !== exp_targ_0) begin pass = 0; errs = $sformatf("%s targ[0]=0x%h(exp 0x%h)", errs, pred_targs[0], exp_targ_0); end
        if (exp_hit_1 && pred_targs[1] !== exp_targ_1) begin pass = 0; errs = $sformatf("%s targ[1]=0x%h(exp 0x%h)", errs, pred_targs[1], exp_targ_1); end
        if (exp_hit_0 && pred_types[0] !== exp_type_0) begin pass = 0; errs = $sformatf("%s type[0]=%s(exp %s)", errs, btype_to_str(pred_types[0]), btype_to_str(exp_type_0)); end
        if (exp_hit_1 && pred_types[1] !== exp_type_1) begin pass = 0; errs = $sformatf("%s type[1]=%s(exp %s)", errs, btype_to_str(pred_types[1]), btype_to_str(exp_type_1)); end
        
        if (pass) begin
            $display("  [PASS] %-28s : %s", name, info);
            tests_passed++;
        end else begin
            $display("  [FAIL] %-28s : %s", name, info);
            $display("         %s", errs);
            tests_failed++;
        end
    endtask

    // Simultaneous read + write test
    // Drive both, wait a cycle, then check read result from BEFORE write latched
    task automatic simul_rw_check(
        input string                    name,
        input logic [CPU_ADDR_BITS-1:0] read_pc,
        input logic [CPU_ADDR_BITS-1:0] write_pc,
        input logic [CPU_ADDR_BITS-1:0] write_targ,
        input logic [1:0]               write_type,
        input logic                     exp_hit_0,
        input logic                     exp_hit_1,
        input logic [CPU_ADDR_BITS-1:0] exp_targ_0 = '0,
        input logic [CPU_ADDR_BITS-1:0] exp_targ_1 = '0,
        input logic [1:0]               exp_type_0 = '0,
        input logic [1:0]               exp_type_1 = '0
    );
        string info, errs;
        logic pass;
        logic [1:0] saved_hit;
        logic [CPU_ADDR_BITS-1:0] saved_targs [1:0];
        logic [1:0] saved_types [1:0];
        
        // Drive read PC and write signals on negedge
        @(negedge clk);
        pc           = read_pc;
        update_val   = 1'b1;
        update_pc    = write_pc;
        update_targ  = write_targ;
        update_type  = write_type;
        update_taken = 1'b1;
        
        // Capture read outputs (async read sees current state before posedge)
        // Small delay for combinational to settle
        #1;
        saved_hit = pred_hit;
        saved_targs[0] = pred_targs[0];
        saved_targs[1] = pred_targs[1];
        saved_types[0] = pred_types[0];
        saved_types[1] = pred_types[1];
        
        // Wait for posedge to latch write, then clear
        @(negedge clk);
        update_val = 1'b0;
        
        // Check saved values
        info = $sformatf("hit=[%0d,%0d] targ=[0x%h,0x%h] type=[%s,%s]",
                         saved_hit[0], saved_hit[1],
                         saved_targs[0], saved_targs[1],
                         btype_to_str(saved_types[0]), btype_to_str(saved_types[1]));
        
        pass = 1;
        errs = "";
        
        if (saved_hit[0] !== exp_hit_0) begin pass = 0; errs = $sformatf("%s hit[0]=%0d(exp %0d)", errs, saved_hit[0], exp_hit_0); end
        if (saved_hit[1] !== exp_hit_1) begin pass = 0; errs = $sformatf("%s hit[1]=%0d(exp %0d)", errs, saved_hit[1], exp_hit_1); end
        if (exp_hit_0 && saved_targs[0] !== exp_targ_0) begin pass = 0; errs = $sformatf("%s targ[0]=0x%h(exp 0x%h)", errs, saved_targs[0], exp_targ_0); end
        if (exp_hit_1 && saved_targs[1] !== exp_targ_1) begin pass = 0; errs = $sformatf("%s targ[1]=0x%h(exp 0x%h)", errs, saved_targs[1], exp_targ_1); end
        if (exp_hit_0 && saved_types[0] !== exp_type_0) begin pass = 0; errs = $sformatf("%s type[0]=%s(exp %s)", errs, btype_to_str(saved_types[0]), btype_to_str(exp_type_0)); end
        if (exp_hit_1 && saved_types[1] !== exp_type_1) begin pass = 0; errs = $sformatf("%s type[1]=%s(exp %s)", errs, btype_to_str(saved_types[1]), btype_to_str(exp_type_1)); end
        
        if (pass) begin
            $display("  [PASS] %-28s : %s", name, info);
            tests_passed++;
        end else begin
            $display("  [FAIL] %-28s : %s", name, info);
            $display("         %s", errs);
            tests_failed++;
        end
    endtask

    task automatic do_reset();
        @(negedge clk);
        rst = 1'b1;
        @(negedge clk);
        rst = 1'b0;
    endtask

    //-------------------------------------------------------------
    // Tests
    //-------------------------------------------------------------
    initial begin
        $dumpfile("btb_tb.vcd");
        $dumpvars(0, btb_tb);

        $display("========================================");
        $display("  BTB Testbench");
        $display("  ENTRIES=%0d, TAG_WIDTH=%0d", ENTRIES, TAG_WIDTH);
        $display("  IDX_WIDTH=%0d (idx from PC[%0d:3])", IDX_WIDTH, IDX_WIDTH+2);
        $display("========================================\n");

        clear_signals();
        do_reset();

        // TEST 1: Empty BTB
        $display("[TEST 1] Empty BTB");
        check_pred("Miss 0x1000", 32'h1000, 0, 0);
        check_pred("Miss 0x2000", 32'h2000, 0, 0);
        $display("");

        // TEST 2: Single slot 0
        $display("[TEST 2] Single Branch - Slot 0");
        do_update(32'h1000, 32'h2000, BRANCH_COND, 1);
        check_pred("Hit slot 0", 32'h1000, 1, 0, 32'h2000, 0, BRANCH_COND, 0);
        $display("");

        // TEST 3: Single slot 1
        $display("[TEST 3] Single Branch - Slot 1");
        do_update(32'h2004, 32'h3000, BRANCH_JUMP, 1);
        check_pred("Hit slot 1", 32'h2000, 0, 1, 0, 32'h3000, 0, BRANCH_JUMP);
        $display("");

        // TEST 4: Both slots
        $display("[TEST 4] Both Slots");
        do_update(32'h2000, 32'h4000, BRANCH_CALL, 1);
        check_pred("Both hit", 32'h2000, 1, 1, 32'h4000, 32'h3000, BRANCH_CALL, BRANCH_JUMP);
        $display("");

        // TEST 5: Not-taken
        $display("[TEST 5] Not-Taken (No Update)");
        do_update(32'h3000, 32'h5000, BRANCH_COND, 0);
        check_pred("Still miss", 32'h3000, 0, 0);
        $display("");

        // TEST 6: All types
        $display("[TEST 6] All Branch Types");
        do_update(32'h4000, 32'h5000, BRANCH_COND, 1);
        do_update(32'h4004, 32'h5004, BRANCH_JUMP, 1);
        check_pred("COND + JUMP", 32'h4000, 1, 1, 32'h5000, 32'h5004, BRANCH_COND, BRANCH_JUMP);
        do_update(32'h5000, 32'h6000, BRANCH_CALL, 1);
        do_update(32'h5004, 32'h6004, BRANCH_RET, 1);
        check_pred("CALL + RET", 32'h5000, 1, 1, 32'h6000, 32'h6004, BRANCH_CALL, BRANCH_RET);
        $display("");

        // TEST 7: Tag mismatch
        $display("[TEST 7] Tag Mismatch");
        diff_tag_pc = 32'h1000 + (1 << (IDX_WIDTH + 3));
        check_pred("Different tag", diff_tag_pc, 0, 0);
        $display("");

        // TEST 8: Overwrite
        $display("[TEST 8] Overwrite Entry");
        do_update(32'h1000, 32'h8000, BRANCH_CALL, 1);
        check_pred("Overwritten", 32'h1000, 1, 0, 32'h8000, 0, BRANCH_CALL, 0);
        $display("");

        // TEST 9: Multiple indices
        $display("[TEST 9] Multiple Indices");
        do_update(32'h1008, 32'hA000, BRANCH_COND, 1);
        do_update(32'h1010, 32'hB000, BRANCH_JUMP, 1);
        do_update(32'h1018, 32'hC000, BRANCH_CALL, 1);
        check_pred("Index 1", 32'h1008, 1, 0, 32'hA000, 0, BRANCH_COND, 0);
        check_pred("Index 2", 32'h1010, 1, 0, 32'hB000, 0, BRANCH_JUMP, 0);
        check_pred("Index 3", 32'h1018, 1, 0, 32'hC000, 0, BRANCH_CALL, 0);
        $display("");

        // TEST 10: Reset
        $display("[TEST 10] Reset");
        do_reset();
        check_pred("After reset", 32'h1000, 0, 0);
        $display("");

        // TEST 11: Aliasing
        $display("[TEST 11] Aliasing");
        do_update(32'h1000, 32'h2000, BRANCH_COND, 1);
        aliased_pc = 32'h1000 + (1 << (TAG_WIDTH + IDX_WIDTH + 3));
        do_update(aliased_pc, 32'h9000, BRANCH_JUMP, 1);
        check_pred("Sees aliased", 32'h1000, 1, 0, 32'h9000, 0, BRANCH_JUMP, 0);
        $display("");

        // TEST 12: Rapid updates
        $display("[TEST 12] Rapid Updates");
        do_update(32'h6000, 32'hA001, BRANCH_COND, 1);
        do_update(32'h6000, 32'hA002, BRANCH_JUMP, 1);
        do_update(32'h6000, 32'hA003, BRANCH_CALL, 1);
        check_pred("Last wins", 32'h6000, 1, 0, 32'hA003, 0, BRANCH_CALL, 0);
        $display("");

        // TEST 13: Bank independence
        $display("[TEST 13] Bank Independence");
        do_reset();
        do_update(32'h7000, 32'hF000, BRANCH_COND, 1);
        do_update(32'h8004, 32'hF004, BRANCH_JUMP, 1);
        check_pred("Only slot 0", 32'h7000, 1, 0, 32'hF000, 0, BRANCH_COND, 0);
        check_pred("Only slot 1", 32'h8000, 0, 1, 0, 32'hF004, 0, BRANCH_JUMP);
        $display("");

        // TEST 14: Simultaneous R/W (different index)
        // Use addresses with DIFFERENT indices to avoid aliasing
        // 0x1000: idx = 0, 0x1008: idx = 1
        $display("[TEST 14] Simultaneous R/W (Different Index)");
        do_reset();
        do_update(32'h1000, 32'hBBBB, BRANCH_COND, 1);  // idx=0
        $display("  Setup: 0x1000 (idx=%0d) -> 0xBBBB", get_index(32'h1000));
        $display("  Write: 0x1008 (idx=%0d) -> 0xDDDD", get_index(32'h1008));
        // Read 0x1000 (idx=0) while writing 0x1008 (idx=1)
        simul_rw_check("Read idx0, Write idx1", 32'h1000, 32'h1008, 32'hDDDD, BRANCH_JUMP,
                       1, 0, 32'hBBBB, 0, BRANCH_COND, 0);
        check_pred("idx0 intact", 32'h1000, 1, 0, 32'hBBBB, 0, BRANCH_COND, 0);
        check_pred("idx1 written", 32'h1008, 1, 0, 32'hDDDD, 0, BRANCH_JUMP, 0);
        $display("");

        // TEST 15: Simultaneous R/W (same addr) - read sees OLD
        $display("[TEST 15] Simultaneous R/W (Same Addr)");
        do_reset();
        do_update(32'hE000, 32'h1111, BRANCH_COND, 1);
        check_pred("Initial", 32'hE000, 1, 0, 32'h1111, 0, BRANCH_COND, 0);
        // Read 0xE000 while writing new value to 0xE000
        simul_rw_check("Read sees OLD", 32'hE000, 32'hE000, 32'h2222, BRANCH_CALL,
                       1, 0, 32'h1111, 0, BRANCH_COND, 0);
        check_pred("Now sees NEW", 32'hE000, 1, 0, 32'h2222, 0, BRANCH_CALL, 0);
        $display("");

        // TEST 16: R/W same addr (entry doesn't exist)
        $display("[TEST 16] R/W Same Addr (New Entry)");
        do_reset();
        simul_rw_check("Misses (not yet)", 32'hF000, 32'hF000, 32'h3333, BRANCH_RET,
                       0, 0);
        check_pred("Now hits", 32'hF000, 1, 0, 32'h3333, 0, BRANCH_RET, 0);
        $display("");

        // Summary
        $display("========================================");
        $display("  Tests Passed: %0d", tests_passed);
        $display("  Tests Failed: %0d", tests_failed);
        $display("========================================");
        if (tests_failed == 0) $display("  ALL TESTS PASSED!");
        else $fatal(1, "FAILURES DETECTED");
        $finish;
    end

    // Timeout
    initial begin
        #100000;
        $fatal(1, "Timeout!");
    end

endmodule