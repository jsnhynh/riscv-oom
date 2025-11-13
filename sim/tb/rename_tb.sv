`timescale 1ns/1ps

import riscv_isa_pkg::*;
import uarch_pkg::*;

module rename_tb;

    //-------------------------------------------------------------
    // Clock and Reset Generation
    //-------------------------------------------------------------
    logic clk;
    logic rst;
    logic flush;

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //-------------------------------------------------------------
    // Stimulus Signals (inputs to DUT)
    //-------------------------------------------------------------
    logic                    dispatch_rdy_i;
    instruction_t            decoded_insts_i    [PIPE_WIDTH-1:0];
    logic [PIPE_WIDTH-1:0]   rob_alloc_gnt_i;
    logic [TAG_WIDTH-1:0]    rob_alloc_tags_i   [PIPE_WIDTH-1:0];
    prf_commit_write_port_t  commit_write_ports_i [PIPE_WIDTH-1:0];

    //-------------------------------------------------------------
    // Monitored Signals (outputs from DUT)
    //-------------------------------------------------------------
    logic                    rename_rdy_o;
    instruction_t            renamed_insts_o    [PIPE_WIDTH-1:0];
    logic [PIPE_WIDTH-1:0]   rob_alloc_req_o;

    //-------------------------------------------------------------
    // DUT Instantiation
    //-------------------------------------------------------------
    rename dut (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        
        // From Decode
        .rename_rdy(rename_rdy_o),
        .decoded_insts(decoded_insts_i),
        
        // To Dispatch
        .dispatch_rdy(dispatch_rdy_i),
        .renamed_insts(renamed_insts_o),
        
        // From ROB
        .rob_alloc_req(rob_alloc_req_o),
        .rob_alloc_gnt(rob_alloc_gnt_i),
        .rob_alloc_tags(rob_alloc_tags_i),
        .commit_write_ports(commit_write_ports_i)
    );

    //-------------------------------------------------------------
    // Helper Tasks
    //-------------------------------------------------------------
    
    // Task: Initialize all stimulus signals
    task automatic init_signals();
        rst = 1;
        flush = 0;
        dispatch_rdy_i = 1;
        rob_alloc_gnt_i = '0;
        
        for (int i = 0; i < PIPE_WIDTH; i++) begin
            decoded_insts_i[i] = '{default:'0};
            rob_alloc_tags_i[i] = '0;
            commit_write_ports_i[i] = '{default:'0};
        end
        
        repeat(2) @(posedge clk);
        rst = 0;
        @(posedge clk);
    endtask

    // Task: Create a simple decoded instruction
    task automatic create_instruction(
        output instruction_t inst,
        input logic [CPU_ADDR_BITS-1:0] pc,
        input logic [4:0] rd, rs1, rs2,
        input logic has_rd,
        input logic [6:0] opcode
    );
        inst = '{default:'0};
        inst.is_valid = 1'b1;
        inst.pc = pc;
        inst.rd = rd;
        inst.has_rd = has_rd;
        inst.opcode = opcode;
        
        // Set source register addresses in tag field
        inst.src_1_a.tag = rs1;
        inst.src_1_a.is_renamed = 1'b0;
        inst.src_1_a.data = '0;
        
        inst.src_1_b.tag = rs2;
        inst.src_1_b.is_renamed = 1'b0;
        inst.src_1_b.data = '0;
        
        // For src_0_a and src_0_b, set different tags to indicate PC/IMM
        inst.src_0_a.tag = 5'h1F; // Different from rs1
        inst.src_0_a.data = pc;
        
        inst.src_0_b.tag = 5'h1E; // Different from rs2
        inst.src_0_b.data = 32'h00000000; // IMM placeholder
    endtask

    // Task: Apply commit write
    task automatic commit_write(
        input int port,
        input logic [4:0] addr,
        input logic [CPU_DATA_BITS-1:0] data,
        input logic [TAG_WIDTH-1:0] tag
    );
        commit_write_ports_i[port].we = 1'b1;
        commit_write_ports_i[port].addr = addr;
        commit_write_ports_i[port].data = data;
        commit_write_ports_i[port].tag = tag;
    endtask

    //-------------------------------------------------------------
    // Test Stimulus
    //-------------------------------------------------------------
    initial begin
        $dumpfile("rename_tb.vcd");
        $dumpvars(0, rename_tb);
        
        $display("========================================");
        $display("  Rename Stage Testbench Started");
        $display("========================================\n");
        
        init_signals();
        
        //-------------------------------------------------------------
        // TEST 1: Single Instruction Rename
        //-------------------------------------------------------------
        $display("[TEST 1] Single Instruction Rename");
        $display("  Sending: ADD x3, x1, x2");
        
        create_instruction(decoded_insts_i[0], 32'h1000, 5'd3, 5'd1, 5'd2, 1'b1, OPC_ARI_RTYPE);
        decoded_insts_i[1] = '{default:'0};
        
        rob_alloc_gnt_i = 2'b01;  // Grant for inst[0]
        rob_alloc_tags_i[0] = 5'd10;
        
        @(posedge clk);
        $display("  rob_alloc_req = %b", rob_alloc_req_o);
        $display("  rename_rdy = %b", rename_rdy_o);
        
        @(posedge clk);
        $display("  renamed_insts[0].is_valid = %b", renamed_insts_o[0].is_valid);
        $display("  renamed_insts[0].dest_tag = %d", renamed_insts_o[0].dest_tag);
        $display("  renamed_insts[0].rd = %d\n", renamed_insts_o[0].rd);
        
        //-------------------------------------------------------------
        // TEST 2: Two Instructions Rename (Both Granted)
        //-------------------------------------------------------------
        $display("[TEST 2] Two Instructions Rename (Both Granted)");
        $display("  Sending: ADD x5, x1, x2 and SUB x6, x3, x4");
        
        create_instruction(decoded_insts_i[0], 32'h1004, 5'd5, 5'd1, 5'd2, 1'b1, OPC_ARI_RTYPE);
        create_instruction(decoded_insts_i[1], 32'h1008, 5'd6, 5'd3, 5'd4, 1'b1, OPC_ARI_RTYPE);
        
        rob_alloc_gnt_i = 2'b11;  // Grant both
        rob_alloc_tags_i[0] = 5'd11;
        rob_alloc_tags_i[1] = 5'd12;
        
        @(posedge clk);
        $display("  rob_alloc_req = %b", rob_alloc_req_o);
        $display("  rename_rdy = %b", rename_rdy_o);
        
        @(posedge clk);
        $display("  renamed_insts[0].is_valid = %b, dest_tag = %d, rd = %d", 
                    renamed_insts_o[0].is_valid, renamed_insts_o[0].dest_tag, renamed_insts_o[0].rd);
        $display("  renamed_insts[1].is_valid = %b, dest_tag = %d, rd = %d\n",
                    renamed_insts_o[1].is_valid, renamed_insts_o[1].dest_tag, renamed_insts_o[1].rd);
        
        //-------------------------------------------------------------
        // TEST 3: RAW Dependency (Intra-group Forwarding)
        //-------------------------------------------------------------
        $display("[TEST 3] RAW Dependency (inst[1] depends on inst[0])");
        $display("  Sending: ADD x5, x1, x2 and ADD x6, x5, x4");
        $display("  inst[1].rs1 (x5) matches inst[0].rd (x5)");
        
        create_instruction(decoded_insts_i[0], 32'h100C, 5'd5, 5'd1, 5'd2, 1'b1, OPC_ARI_RTYPE);
        create_instruction(decoded_insts_i[1], 32'h1010, 5'd6, 5'd5, 5'd4, 1'b1, OPC_ARI_RTYPE);
        
        rob_alloc_gnt_i = 2'b11;
        rob_alloc_tags_i[0] = 5'd13;
        rob_alloc_tags_i[1] = 5'd14;
        
        @(posedge clk);
        @(posedge clk);
        $display("  renamed_insts[1].src_1_a.is_renamed = %b", renamed_insts_o[1].src_1_a.is_renamed);
        $display("  renamed_insts[1].src_1_a.tag = %d (should be %d)\n", 
                    renamed_insts_o[1].src_1_a.tag, rob_alloc_tags_i[0]);
        
        //-------------------------------------------------------------
        // TEST 4: Partial Grant (Only inst[0] granted)
        //-------------------------------------------------------------
        $display("[TEST 4] Partial Grant - Should Stall");
        $display("  Sending: Two instructions, but only inst[0] gets grant");
        
        create_instruction(decoded_insts_i[0], 32'h1014, 5'd7, 5'd1, 5'd2, 1'b1, OPC_ARI_RTYPE);
        create_instruction(decoded_insts_i[1], 32'h1018, 5'd8, 5'd3, 5'd4, 1'b1, OPC_ARI_RTYPE);
        
        rob_alloc_gnt_i = 2'b01;  // Only grant inst[0]
        rob_alloc_tags_i[0] = 5'd15;
        
        @(posedge clk);
        $display("  rob_alloc_req = %b", rob_alloc_req_o);
        $display("  rename_rdy = %b (should be 0 - stalled)", rename_rdy_o);
        
        @(posedge clk);
        $display("  Pipeline should hold previous values (stalled)\n");
        
        //-------------------------------------------------------------
        // TEST 5: Grant both after stall
        //-------------------------------------------------------------
        $display("[TEST 5] Grant Both After Stall");
        rob_alloc_gnt_i = 2'b11;  // Now grant both
        rob_alloc_tags_i[1] = 5'd16;
        
        @(posedge clk);
        $display("  rename_rdy = %b (should be 1)", rename_rdy_o);
        
        @(posedge clk);
        $display("  renamed_insts[0].is_valid = %b, dest_tag = %d", 
                    renamed_insts_o[0].is_valid, renamed_insts_o[0].dest_tag);
        $display("  renamed_insts[1].is_valid = %b, dest_tag = %d\n",
                    renamed_insts_o[1].is_valid, renamed_insts_o[1].dest_tag);
        
        //-------------------------------------------------------------
        // TEST 6: Commit and Read (Verify PRF Update)
        //-------------------------------------------------------------
        $display("[TEST 6] Commit Write and Subsequent Read");
        $display("  Committing x3 = 0xDEADBEEF with tag 10");
        
        commit_write(0, 5'd3, 32'hDEADBEEF, 5'd10);
        decoded_insts_i[0] = '{default:'0};
        decoded_insts_i[1] = '{default:'0};
        rob_alloc_gnt_i = 2'b00;
        
        @(posedge clk);
        commit_write_ports_i[0].we = 1'b0;
        
        // Now try to read x3
        $display("  Reading x3 in next rename cycle");
        create_instruction(decoded_insts_i[0], 32'h101C, 5'd9, 5'd3, 5'd0, 1'b1, OPC_ARI_RTYPE);
        rob_alloc_gnt_i = 2'b01;
        rob_alloc_tags_i[0] = 5'd17;
        
        @(posedge clk);
        @(posedge clk);
        $display("  renamed_insts[0].src_1_a.data = 0x%h (should be 0xDEADBEEF)", 
                    renamed_insts_o[0].src_1_a.data);
        $display("  renamed_insts[0].src_1_a.is_renamed = %b (should be 0)\n",
                    renamed_insts_o[0].src_1_a.is_renamed);
        
        //-------------------------------------------------------------
        // TEST 7: Flush Test
        //-------------------------------------------------------------
        $display("[TEST 7] Flush - Clear All Renamed Flags");
        
        // First, rename some registers
        create_instruction(decoded_insts_i[0], 32'h1020, 5'd10, 5'd1, 5'd2, 1'b1, OPC_ARI_RTYPE);
        rob_alloc_gnt_i = 2'b01;
        rob_alloc_tags_i[0] = 5'd18;
        
        @(posedge clk);
        @(posedge clk);
        
        // Now flush
        $display("  Asserting flush...");
        flush = 1'b1;
        decoded_insts_i[0] = '{default:'0};
        
        @(posedge clk);
        flush = 1'b0;
        
        $display("  After flush, all renamed flags should be cleared");
        $display("  renamed_insts should be invalid\n");
        
        @(posedge clk);
        $display("  renamed_insts[0].is_valid = %b (should be 0)", renamed_insts_o[0].is_valid);
        $display("  renamed_insts[1].is_valid = %b (should be 0)\n", renamed_insts_o[1].is_valid);
        
        //-------------------------------------------------------------
        // TEST 8: Compaction Test
        //-------------------------------------------------------------
        $display("[TEST 8] Compaction - Only inst[1] valid");
        $display("  Sending: inst[0] invalid, inst[1] valid");
        
        decoded_insts_i[0] = '{default:'0};  // Invalid
        create_instruction(decoded_insts_i[1], 32'h1024, 5'd11, 5'd1, 5'd2, 1'b1, OPC_ARI_RTYPE);
        
        rob_alloc_gnt_i = 2'b10;  // Grant inst[1]
        rob_alloc_tags_i[1] = 5'd19;
        
        @(posedge clk);
        @(posedge clk);
        $display("  After compaction:");
        $display("  renamed_insts[0].is_valid = %b (should be 1)", renamed_insts_o[0].is_valid);
        $display("  renamed_insts[0].dest_tag = %d (should be %d)", 
                    renamed_insts_o[0].dest_tag, rob_alloc_tags_i[1]);
        $display("  renamed_insts[1].is_valid = %b (should be 0)\n", renamed_insts_o[1].is_valid);
        
        //-------------------------------------------------------------
        // End of Tests
        //-------------------------------------------------------------
        repeat(5) @(posedge clk);
        
        $display("========================================");
        $display("  All Tests Complete!");
        $display("========================================");
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