`timescale 1ns/1ps
import riscv_isa_pkg::*;
import uarch_pkg::*;

module reservation_station_tb;

    //-------------------------------------------------------------
    // Test Configuration
    //-------------------------------------------------------------
    localparam NUM_ENTRIES = 8;
    localparam ISSUE_WIDTH = 2;

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
    logic flush;

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //-------------------------------------------------------------
    // DUT Signals
    //-------------------------------------------------------------
    logic [PIPE_WIDTH-1:0]      rs_rdy;
    logic [PIPE_WIDTH-1:0]      rs_we;
    instruction_t               rs_entries_in [PIPE_WIDTH-1:0];
    
    logic [ISSUE_WIDTH-1:0]     fu_rdy;
    instruction_t               fu_packets [ISSUE_WIDTH-1:0];
    
    writeback_packet_t          cdb_ports [PIPE_WIDTH-1:0];
    logic [TAG_WIDTH-1:0]       rob_head;

    //-------------------------------------------------------------
    // DUT Instantiation
    //-------------------------------------------------------------
    reservation_station #(
        .NUM_ENTRIES(NUM_ENTRIES),
        .ISSUE_WIDTH(ISSUE_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .rs_rdy(rs_rdy),
        .rs_we(rs_we),
        .rs_entries_in(rs_entries_in),
        .fu_rdy(fu_rdy),
        .fu_packets(fu_packets),
        .cdb_ports(cdb_ports),
        .rob_head(rob_head)
    );

    //-------------------------------------------------------------
    // Helper Tasks
    //-------------------------------------------------------------
    
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

    // Create a simple test instruction with tag and source dependencies
    function automatic instruction_t make_test_inst(
        input logic [TAG_WIDTH-1:0] dest_tag,
        input logic [TAG_WIDTH-1:0] src_0_a_tag,
        input logic                 src_0_a_ready,
        input logic [TAG_WIDTH-1:0] src_0_b_tag,
        input logic                 src_0_b_ready,
        input logic                 valid = 1'b1
    );
        instruction_t inst;
        inst = '{default: '0};
        inst.is_valid = valid;
        inst.dest_tag = dest_tag;
        
        // Source 0_a
        inst.src_0_a.is_renamed = !src_0_a_ready;
        inst.src_0_a.tag = src_0_a_tag;
        inst.src_0_a.data = src_0_a_ready ? 32'hAAAA_AAAA : 32'h0;
        
        // Source 0_b
        inst.src_0_b.is_renamed = !src_0_b_ready;
        inst.src_0_b.tag = src_0_b_tag;
        inst.src_0_b.data = src_0_b_ready ? 32'hBBBB_BBBB : 32'h0;
        
        // Sources 1_a and 1_b default to ready (not used in most tests)
        inst.src_1_a.is_renamed = 0;
        inst.src_1_a.data = 32'hCCCC_CCCC;
        inst.src_1_b.is_renamed = 0;
        inst.src_1_b.data = 32'hDDDD_DDDD;
        
        return inst;
    endfunction

    // Create a CDB writeback packet
    function automatic writeback_packet_t make_cdb_packet(
        input logic [TAG_WIDTH-1:0]     tag,
        input logic [CPU_DATA_BITS-1:0] result,
        input logic                     valid = 1'b1
    );
        writeback_packet_t pkt;
        pkt.dest_tag = tag;
        pkt.result = result;
        pkt.is_valid = valid;
        pkt.exception = 1'b0;
        return pkt;
    endfunction

    // Initialize all signals
    task automatic init_signals();
        rst = 1;
        flush = 0;
        rs_we = '0;
        fu_rdy = '1;  // FUs always ready unless specified
        rob_head = '0;
        
        for (int i = 0; i < PIPE_WIDTH; i++) begin
            rs_entries_in[i] = '{default: '0};
            cdb_ports[i] = '{default: '0};
        end
        
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        @(posedge clk);
    endtask

    // Display RS state (for debugging)
    task automatic display_rs_state();
        $display("    RS State:");
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (dut.entries[i].is_valid) begin
                $display("      [%0d] tag=0x%02h, ready=%b, age=%0d", 
                         i,
                         dut.entries[i].dest_tag,
                         dut.entry_ready[i],
                         dut.entry_ages[i]);
            end
        end
    endtask

    //-------------------------------------------------------------
    // Test Stimulus
    //-------------------------------------------------------------
    initial begin
        $dumpfile("reservation_station_tb.vcd");
        $dumpvars(0, reservation_station_tb);
        
        $display("========================================");
        $display("  Reservation Station Testbench");
        $display("========================================");
        $display("  NUM_ENTRIES = %0d", NUM_ENTRIES);
        $display("  ISSUE_WIDTH = %0d", ISSUE_WIDTH);
        $display("========================================\n");
        
        init_signals();

        //-------------------------------------------------------------
        // TEST 1: Basic Allocation
        //-------------------------------------------------------------
        $display("[TEST 1] Basic Allocation (2 ready instructions)");
        
        // Drive inputs on posedge
        @(posedge clk);
        rob_head = 5'h00;
        rs_we = 2'b11;
        rs_entries_in[0] = make_test_inst(5'h05, 5'h00, 1'b1, 5'h00, 1'b1);
        rs_entries_in[1] = make_test_inst(5'h06, 5'h00, 1'b1, 5'h00, 1'b1);
        
        // Check outputs on negedge
        @(negedge clk);
        
        check_assertion("RS ready to accept instructions",
                       rs_rdy == 2'b11,
                       $sformatf("Expected rs_rdy=11, got %b", rs_rdy));
        
        @(posedge clk);
        rs_we = 2'b00;
        rs_entries_in[0] = '{default:'0};
        rs_entries_in[1] = '{default:'0};
        
        @(negedge clk);
        
        check_assertion("Both instructions stored",
                       dut.entries[0].is_valid && dut.entries[1].is_valid,
                       "Instructions stored in RS");
        
        check_assertion("Both instructions issued",
                       dut.issue_grants == 8'b0000_0011,
                       $sformatf("Expected ready=0x03, got 0x%02h", dut.entry_ready));

        
        $display("");

        //-------------------------------------------------------------
        // TEST 2: Age-Based Selection
        //-------------------------------------------------------------
        $display("[TEST 2] Age-Based Selection");
        
        init_signals();
        
        // Drive inputs on posedge
        @(posedge clk);
        rob_head = 5'h00;
        rs_we = 2'b11;
        rs_entries_in[0] = make_test_inst(5'h03, 5'h00, 1'b1, 5'h00, 1'b1);  // Age 3
        rs_entries_in[1] = make_test_inst(5'h01, 5'h00, 1'b1, 5'h00, 1'b1);  // Age 1 (oldest)
        
        @(posedge clk);
        rs_we = 2'b01;
        rs_entries_in[0] = make_test_inst(5'h02, 5'h00, 1'b1, 5'h00, 1'b1);  // Age 2
        rs_entries_in[1] = '{default:'0};

        @(negedge clk);

        check_assertion("Oldest instruction (age 1) issued to FU[0]",
                       fu_packets[0].dest_tag == 5'h01,
                       $sformatf("Expected tag=0x01, got 0x%02h", fu_packets[0].dest_tag));
        
        check_assertion("2nd oldest instruction (age 3) issued to FU[1]",
                       fu_packets[1].dest_tag == 5'h03,
                       $sformatf("Expected tag=0x03, got 0x%02h", fu_packets[1].dest_tag));
        
        @(posedge clk);
        rs_we = 2'b00;
        
        // Check outputs on negedge
        @(negedge clk);
        
        display_rs_state();
        
        check_assertion("Oldest instruction (age 2) issued to FU[0]",
                       fu_packets[0].dest_tag == 5'h02,
                       $sformatf("Expected tag=0x02, got 0x%02h", fu_packets[0].dest_tag));
        
        $display("");

        //-------------------------------------------------------------
        // TEST 3: Simple Wakeup
        //-------------------------------------------------------------
        $display("[TEST 3] Simple Wakeup on CDB");
        
        init_signals();
        
        // Drive inputs on posedge
        @(posedge clk);
        rob_head = 5'h00;
        rs_we = 2'b01;
        rs_entries_in[0] = make_test_inst(5'h05, 5'h0A, 1'b0, 5'h00, 1'b1);  // src_0_a waits for 0x0A
        rs_entries_in[1] = '{default:'0};
        @(posedge clk);
        rs_we = 2'b00;
        rs_entries_in[0] = '{default:'0};
        rs_entries_in[1] = '{default:'0};
        
        // Check on negedge
        @(negedge clk);
        
        check_assertion("Instruction NOT ready (waiting for 0x0A)",
                       dut.entry_ready[0] == 1'b0,
                       "Instruction should not be ready yet");
        
        // Broadcast tag 0x0A on CDB (drive on posedge)
        @(posedge clk);
        cdb_ports[0] = make_cdb_packet(5'h0A, 32'hDEAD_BEEF);
        
        // Check on negedge - RS SHOULD ISSUE SAME CYCLE
        @(negedge clk);
        
        check_assertion("Instruction woke up (next cycle)",
                       dut.entry_ready[0] == 1'b1,
                       "Instruction should be ready next cycle after CDB");
        
        check_assertion("Instruction issued with correct data",
                       fu_packets[0].dest_tag == 5'h05 && 
                       fu_packets[0].src_0_a.data == 32'hDEAD_BEEF,
                       $sformatf("Expected issued with data=0xDEADBEEF"));
        
        $display("");

        //-------------------------------------------------------------
        // TEST 4: Wraparound Age Calculation
        //-------------------------------------------------------------
        $display("[TEST 4] Wraparound Age Calculation");
        
        init_signals();
        
        // Drive inputs on posedge
        @(posedge clk);
        rob_head = 5'h1E;  // Near max (30)
        rs_we = 2'b11;
        rs_entries_in[0] = make_test_inst(5'h01, 5'h00, 1'b1, 5'h00, 1'b1);  // Age (1-30)=3 in 5-bit
        rs_entries_in[1] = make_test_inst(5'h1E, 5'h00, 1'b1, 5'h00, 1'b1);  // Age (30-30)=0 (oldest)
        
        @(posedge clk);
        rs_we = 2'b01;
        rs_entries_in[0] = make_test_inst(5'h1F, 5'h00, 1'b1, 5'h00, 1'b1);  // Age (31-30)=1
        rs_entries_in[1] = '{default:'0};

        @(negedge clk);
        check_assertion("Oldest (tag 0x1E, age 0) issued to FU[0]",
                       fu_packets[0].dest_tag == 5'h1E,
                       $sformatf("Expected tag=0x1E, got 0x%02h", fu_packets[0].dest_tag));
        check_assertion("2nd Oldest (tag 0x01, age 3) issued to FU[1]",
                       fu_packets[1].dest_tag == 5'h01,
                       $sformatf("Expected tag=0x01, got 0x%02h", fu_packets[1].dest_tag));
        
        @(posedge clk);
        rs_we = 2'b00;
        
        @(negedge clk);
        check_assertion("3nd oldest (tag 0x1F, age 1) issued to FU[0]",
                       fu_packets[0].dest_tag == 5'h1F,
                       $sformatf("Expected tag=0x1F, got 0x%02h", fu_packets[0].dest_tag));
        
        display_rs_state();
        
        $display("");

        //-------------------------------------------------------------
        // TEST 5: Back-to-back Dependencies
        //-------------------------------------------------------------
        $display("[TEST 5] Back-to-back Dependent Instructions");
        
        init_signals();
        
        // Drive inputs on posedge
        @(posedge clk);
        rob_head = 5'h00;
        rs_we = 2'b01;
        rs_entries_in[0] = make_test_inst(5'h05, 5'h00, 1'b1, 5'h00, 1'b1);
        rs_entries_in[1] = '{default:'0};
        
        @(posedge clk);
        rs_entries_in[0] = make_test_inst(5'h06, 5'h05, 1'b0, 5'h00, 1'b1);  // Waits for 0x05

        @(negedge clk);
        check_assertion("Inst 0 ready, consumer waiting",
                       dut.entry_ready == 8'b0000_0001,
                       $sformatf("Expected ready=0x01, got 0x%02h", dut.entry_ready));

        check_assertion("Inst 0 issued",
                       fu_packets[0].dest_tag == 5'h05,
                       $sformatf("Expected tag=0x05, got 0x%02h", fu_packets[0].dest_tag));
        
        @(posedge clk);
        rs_we = 2'b11;
        rs_entries_in[0] = make_test_inst(5'h07, 5'h06, 1'b0, 5'h00, 1'b1);  // Waits for 0x06
        rs_entries_in[1] = make_test_inst(5'h08, 5'h08, 1'b1, 5'h08, 1'b1);
        cdb_ports[0] = make_cdb_packet(5'h05, 32'h1234_5678);
        
        @(negedge clk);
        check_assertion("Inst 1 woke up",
                       dut.entry_ready[0] == 1'b1,
                       "Consumer should wake up after producer broadcasts");
        
        check_assertion("Inst 1 issued",
                       fu_packets[0].src_0_a.data == 32'h1234_5678,
                       $sformatf("Expected data=0x12345678, got 0x%08h",
                                fu_packets[0].src_0_a.data));

        @(posedge clk);
        rs_we = 2'b00;
        rs_entries_in = '{default:'0};

        @(negedge clk);
        check_assertion("Inst 3 & 4 stored",
                       dut.entries[0].is_valid && dut.entries[1].is_valid ,
                       "Both Instructions stored in RS");

        check_assertion("Inst 4 issued",
                       fu_packets[0].dest_tag == 5'h08,
                       $sformatf("Expected tag=0x08, got 0x%02h", fu_packets[0].dest_tag));
        
        $display("");

        //-------------------------------------------------------------
        // TEST 6: RS Full
        //-------------------------------------------------------------
        $display("[TEST 6] RS Full Scenario");
        
        init_signals();
        
        // Drive inputs on posedge
        @(posedge clk);
        rob_head = 5'h00;
        fu_rdy = 2'b00;  // Block FUs so RS fills up
        
        // Fill all 8 entries (dispatch 8 instructions, 2 at a time)
        for (int i = 0; i < NUM_ENTRIES/2; i++) begin
            @(posedge clk);
            rs_we = 2'b11;
            rs_entries_in[0] = make_test_inst(5'h00 + i*2,   5'h10, 1'b0, 5'h00, 1'b1);
            rs_entries_in[1] = make_test_inst(5'h00 + i*2+1, 5'h11, 1'b0, 5'h00, 1'b1);
        end
        
        @(posedge clk);
        rs_we = 2'b00;
        
        // Check on negedge
        @(negedge clk);
        
        check_assertion("RS is full",
                       rs_rdy == 2'b00,
                       $sformatf("Expected rs_rdy=00 (full), got %b", rs_rdy));
        
        check_assertion("All 8 entries valid",
                       dut.entries[0].is_valid && dut.entries[1].is_valid &&
                       dut.entries[2].is_valid && dut.entries[3].is_valid &&
                       dut.entries[4].is_valid && dut.entries[5].is_valid &&
                       dut.entries[6].is_valid && dut.entries[7].is_valid,
                       "Not all entries are valid");
        
        // Wake up 2 instructions (drive on posedge)
        @(posedge clk);
        cdb_ports[0] = make_cdb_packet(5'h10, 32'hAAAA_AAAA);
        cdb_ports[1] = make_cdb_packet(5'h11, 32'hBBBB_BBBB);

        @(posedge clk);
        cdb_ports[0] = '{default: '0};
        cdb_ports[1] = '{default: '0};
        fu_rdy = 2'b10;
        // Since ~fu_rdy, should not issue
        @(negedge clk);
        check_assertion("2 instructions snooped but only 1 FU ready",
                       ~fu_packets[0].is_valid && fu_packets[1].is_valid,
                       "Expected 1 instructions to issue");
        check_assertion("RS has 1 free slot now",
                       rs_rdy == 2'b01,
                       $sformatf("Expected rs_rdy==01, got %b", rs_rdy));
                    
        @(posedge clk);
        fu_rdy = 2'b11; // Both FU ready
        // Check on negedge
        @(negedge clk);
        check_assertion("2 instructions issued (RS draining)",
                       fu_packets[0].is_valid && fu_packets[1].is_valid,
                       "Expected 2 instructions to issue");
        
        check_assertion("RS has 2 free slots now",
                       rs_rdy != 2'b00,
                       $sformatf("Expected rs_rdy!=00, got %b", rs_rdy));
        
        $display("");

        //-------------------------------------------------------------
        // TEST 7: Multi-Issue (2 ready instructions same cycle)
        //-------------------------------------------------------------
        $display("[TEST 7] Multi-Issue (2 instructions in 1 cycle)");
        
        init_signals();
        
        // Drive inputs on posedge
        @(posedge clk);
        rob_head = 5'h00;
        rs_we = 2'b11;
        rs_entries_in[0] = make_test_inst(5'h08, 5'h00, 1'b1, 5'h00, 1'b1);
        rs_entries_in[1] = make_test_inst(5'h09, 5'h00, 1'b1, 5'h00, 1'b1);
        
        @(posedge clk);
        rs_we = 2'b00;
        
        // Check on negedge
        @(negedge clk);
        
        check_assertion("Both instructions ready",
                       dut.entry_ready[0] && dut.entry_ready[1],
                       "Both instructions should be ready");
        
        check_assertion("Both issued in same cycle",
                       fu_packets[0].is_valid && fu_packets[1].is_valid,
                       "Both FU packets should be valid");
        
        check_assertion("Correct tags issued",
                       (fu_packets[0].dest_tag == 5'h08 && fu_packets[1].dest_tag == 5'h09) ||
                       (fu_packets[0].dest_tag == 5'h09 && fu_packets[1].dest_tag == 5'h08),
                       $sformatf("Expected tags 0x08 and 0x09, got 0x%02h and 0x%02h",
                                fu_packets[0].dest_tag, fu_packets[1].dest_tag));
        
        @(posedge clk);
        
        @(negedge clk);
        
        check_assertion("RS empty after dual issue",
                       !dut.entries[0].is_valid && !dut.entries[1].is_valid,
                       "Both entries should be cleared");
        
        $display("");

        //-------------------------------------------------------------
        // TEST 8: Flush
        //-------------------------------------------------------------
        $display("[TEST 8] Flush Clears All Entries");
        
        init_signals();
        
        // Drive inputs on posedge
        @(posedge clk);
        rob_head = 5'h00;
        rs_we = 2'b11;
        rs_entries_in[0] = make_test_inst(5'h10, 5'h00, 1'b1, 5'h00, 1'b1);
        rs_entries_in[1] = make_test_inst(5'h11, 5'h00, 1'b1, 5'h00, 1'b1);
        
        @(posedge clk);
        rs_we = 2'b00;
        
        // Check on negedge
        @(negedge clk);
        
        check_assertion("Entries valid before flush",
                       dut.entries[0].is_valid && dut.entries[1].is_valid,
                       "Entries should be valid");
        
        @(posedge clk);
        flush = 1;
        
        @(posedge clk);
        flush = 0;
        
        // Check on negedge
        @(negedge clk);
        
        check_assertion("All entries cleared after flush",
                       !dut.entries[0].is_valid && !dut.entries[1].is_valid &&
                       !dut.entries[2].is_valid && !dut.entries[3].is_valid &&
                       !dut.entries[4].is_valid && !dut.entries[5].is_valid &&
                       !dut.entries[6].is_valid && !dut.entries[7].is_valid,
                       "All entries should be invalid after flush");
        
        $display("");

        //-------------------------------------------------------------
        // TEST 9: Sequential Dispatch (Instructions arrive over time)
        //-------------------------------------------------------------
        $display("[TEST 9] Sequential Dispatch Over Multiple Cycles");
        
        init_signals();
        
        // Cycle 1: Dispatch first instruction
        @(posedge clk);
        rob_head = 5'h00;
        rs_we = 2'b01;
        rs_entries_in[0] = make_test_inst(5'h10, 5'h00, 1'b1, 5'h00, 1'b1);  // Age 16
        rs_entries_in[1] = '{default:'0};
        
        // Cycle 2: Dispatch second instruction
        @(posedge clk);
        rs_entries_in[0] = make_test_inst(5'h0F, 5'h00, 1'b1, 5'h00, 1'b1);  // Age 15 (older!)
        rs_entries_in[1] = '{default:'0};

        @(negedge clk);
        check_assertion("First instruction allocated",
                       dut.entries[0].is_valid,
                       "Entry 0 should be valid");
        
        // Cycle 3: Dispatch third and fourth instruction (2-wide)
        @(posedge clk);
        rs_we = 2'b11;
        rs_entries_in[0] = make_test_inst(5'h11, 5'h00, 1'b1, 5'h00, 1'b1);  // Age 17
        rs_entries_in[1] = make_test_inst(5'h0E, 5'h00, 1'b1, 5'h00, 1'b1);  // Age 14 (oldest)
        
        @(negedge clk);
        check_assertion("Second instruction allocated",
                       dut.entries[0].is_valid,
                       "Entry 0 should be valid");
        
        // Cycle 4: Stop dispatching, check issue order
        @(posedge clk);
        rs_we = 2'b00;
        
        @(negedge clk);
        check_assertion("Third and fourth instructions allocated",
                       dut.entries[0].is_valid && dut.entries[1].is_valid,
                       "Entries 0 and 1 should be valid");

        @(posedge clk);
        @(negedge clk);
        check_assertion("Third and fourth instructions issued & cleared",
                       ~dut.entries[0].is_valid && ~dut.entries[0].is_valid,
                       "Entries 0 and 1 should not be valid");
        
        $display("");

        //-------------------------------------------------------------
        // TEST 10: Partial Dispatch (1 slot available)
        //-------------------------------------------------------------
        $display("[TEST 10] Partial Dispatch (RS has 1 slot free)");
        
        init_signals();
        
        // Fill 7 out of 8 entries
        @(posedge clk);
        rob_head = 5'h00;
        fu_rdy = 2'b00;  // Block FUs
        
        for (int i = 0; i < 3; i++) begin
            @(posedge clk);
            rs_we = 2'b11;
            rs_entries_in[0] = make_test_inst(5'h00 + i*2,   5'h10, 1'b0, 5'h00, 1'b1);
            rs_entries_in[1] = make_test_inst(5'h00 + i*2+1, 5'h10, 1'b0, 5'h00, 1'b1);
        end
        
        @(posedge clk);
        rs_we = 2'b01;
        rs_entries_in[0] = make_test_inst(5'h06, 5'h10, 1'b0, 5'h00, 1'b1);
        
        @(posedge clk);
        rs_we = 2'b00;
        
        @(negedge clk);
        
        check_assertion("RS has 1 slot free",
                       rs_rdy == 2'b01,
                       $sformatf("Expected rs_rdy=01 (1 slot), got %b", rs_rdy));
        
        // Try to dispatch 2 instructions (only 1 should fit)
        @(posedge clk);
        rs_we = 2'b11;
        rs_entries_in[0] = make_test_inst(5'h07, 5'h00, 1'b1, 5'h00, 1'b1);
        rs_entries_in[1] = make_test_inst(5'h08, 5'h00, 1'b1, 5'h00, 1'b1);
        
        @(negedge clk);
        
        check_assertion("Only 1 instruction can be written",
                       rs_rdy[0] == 1'b1 && rs_rdy[1] == 1'b0,
                       $sformatf("Expected rs_rdy=01, got %b", rs_rdy));
        
        @(posedge clk);
        rs_we = 2'b00;
        
        @(negedge clk);
        
        check_assertion("RS now full",
                       rs_rdy == 2'b00,
                       $sformatf("Expected rs_rdy=00 (full), got %b", rs_rdy));
        
        check_assertion("First instruction allocated",
                       dut.entries[7].is_valid && dut.entries[7].dest_tag == 5'h07,
                       "Entry 7 should have tag 0x07");
        
        $display("");
        
        //-------------------------------------------------------------
        // End of Tests
        //-------------------------------------------------------------
        @(posedge clk);
        
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