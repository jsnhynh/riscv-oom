`timescale 1ns/1ps

import uarch_pkg::*;

module fetch_tb;;
    localparam TEST_FILE = "fetch_test.hex";
    localparam MEM_SIZE        = 1024;

    // Testbench Signals
    logic clk;
    logic rst;
    logic flush_i;
    logic icache_stall_i;

    logic [2:0]                 pc_sel_i;
    logic [CPU_ADDR_BITS-1:0]   rob_pc_i;

    // Interface between DUT and Memory Model
    logic [CPU_ADDR_BITS-1:0]   icache_addr;
    logic                       icache_re;
    logic [FETCH_WIDTH*CPU_INST_BITS-1:0] icache_dout; // Use FETCH_WIDTH from pkg
    logic                       icache_dout_val;

    // Decoder Ports
    logic                       decoder_rdy_i;
    logic [CPU_ADDR_BITS-1:0]   pc_o;
    logic [CPU_ADDR_BITS-1:0]   pc_4_o;
    logic [CPU_INST_BITS-1:0]   inst0_o;
    logic [CPU_INST_BITS-1:0]   inst1_o;
    logic                       inst_val_o;

    fetch dut (
        .clk(clk),
        .rst(rst),
        .flush(flush_i),

        .pc_sel(pc_sel_i),
        .rob_pc(rob_pc_i),

        .icache_addr(icache_addr),
        .icache_re(icache_re),
        .icache_dout(icache_dout),
        .icache_dout_val(icache_dout_val),
        .icache_stall(icache_stall_i),

        .decoder_rdy(decoder_rdy_i),
        .pc(pc_o),
        .pc_4(pc_4_o),
        .inst0(inst0_o),
        .inst1(inst1_o),
        .inst_val(inst_val_o)
    );

    mem_simple #(
        .IMEM_HEX_FILE(TEST_FILE), 
        .IMEM_SIZE_BYTES(MEM_SIZE),
        .DMEM_SIZE_BYTES(1)
    ) mem (
        .clk(clk),
        .rst(rst),
        // IMEM Ports
        .icache_addr(icache_addr),
        .icache_re(icache_re),
        .icache_dout(icache_dout),
        .icache_dout_val(icache_dout_val),
        .icache_stall(icache_stall_i),

        // DMEM Ports (Unconnected)
        .dcache_addr('0),
        .dcache_re('0),
        .dcache_dout(),
        .dcache_dout_val(),
        .dcache_stall()
        .dcache_din('0),
        .dcache_we('0)
    );

    // Clock Generation
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        $display("Starting Fetch Stage Testbench...");
        // Initialize signals
        clk = 0;
        rst = 1;
        flush_i = 0;
        icache_stall_i = 0;
        pc_sel_i = '0;
        pc_sel_i[0] = flush_i;
        rob_pc_i = '0;
        decoder_rdy = 1;

        // Create the hex file with repeating patterns
        begin
            automatic int fd = $fopen(TEST_FILE, "w");
            automatic logic [CPU_INST_BITS-1:0] pattern = 32'h11111111;
            for (int i = 0; i < MEM_SIZE / 4; i=i+1) begin // Iterate through words
                // Write two instructions (one 64-bit line) per address increment of 8
                if ((PC_RESET + i*4) < (PC_RESET + MEM_SIZE)) begin // Basic bounds check
                   $fdisplay(fd, "%h", pattern); // Word at Addr + i*4
                end
                 pattern = pattern + 32'h11111111; // Next pattern
            end
            // Specific instruction for redirect target
            if (32'hA000 < (PC_RESET + MEM_SIZE))
                $fdisplay(fd, "@a000\n%h", 32'hAAAAAAAA);
            if (32'hA004 < (PC_RESET + MEM_SIZE))
                $fdisplay(fd, "@a004\n%h", 32'hBBBBBBBB);
            $fclose(fd);
        end

        // Reset Sequence
        #1; @(posedge clk); rst = 0;
        $display("[%0t] Reset Released. PC should be at reset vector %h.", $time, PC_RESET);
        @(posedge clk);

        // -- Test 1: Sequential Fetch --
        $display("[%0t] Test 1: Sequential Fetching...", $time);
        assert (icache_addr == PC_RESET) else $fatal(1, "[%0t] PC did not reset correctly. Addr=%h", $time, icache_addr);
        repeat (5) @(posedge clk); // Let a few fetches happen

        // -- Test 2: Decoder Stall --
        $display("[%0t] Test 2: Decoder Stall...", $time);
        decoder_rdy_i = 0; // Stall the decoder
        repeat (3) @(posedge clk); // Hold stall
        decoder_rdy_i = 1; // Release stall
        repeat (2) @(posedge clk);    // Allow recovery

        // -- Test 3: I-Cache Stall --
        $display("[%0t] Test 3: Cache Stall...", $time);
        icache_stall_i = 1; // Stall the fetch stage
        repeat (3) @(posedge clk); // Hold stall
        icache_stall_i = 0; // Release stall
        repeat (3) @(posedge clk);     // Allow recovery

        // --- Test 4: Branch/Jump Redirect ---
        $display("[%0t] Test 4: Redirect...", $time);
        pc_sel_i = 3'b001; // Select ROB PC
        rob_pc_i = 32'h0000_A000;
        flush_i  = 1;       // Assert flush to force redirect
        @(posedge clk);
        flush_i = 0;        // De-assert flush for next cycle fetch
        pc_sel_i = '0;
        @(posedge clk);     // PC updates, new fetch issued to A000
        assert (icache_addr == 32'h0000_A000) else $fatal(1, "[%0t] Redirect failed. Addr=%h", $time, icache_addr);
        @(posedge clk);     // Memory responds for A000.
        @(posedge clk);     // Buffer outputs AAAA, BBBB.
        @(posedge clk);     // Fetch A008.

        #100; // Run for a bit longer
        $display("[%0t] Testbench Finished.", $time);
        $finish;
    end

    initial begin
        @(negedge rst);
        #1;
        $monitor("[%0t] PC:%h Inst0:%h | PC4:%h Inst1:%h | Decoder Val:%b",
            $time, pc_o, inst0_o, pc_4_o, inst1_o, inst_val_o);
    end

endmodule