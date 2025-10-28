/*
    Memory Simple

    Models both Instruction and Data memory using a single 
    byte-addressable register array. Featrues preloaded 
    capability via $readmemh and fixed 1-cycle rad latency.
*/
import uarch_pkg::*;

module mem_simple #(
    parameter IMEM_SIZE_BYTES = 32*1024, // 32 KiB IMEM
    parameter DMEM_SIZE_BYTES = 32*1024, // 32 KiB DMEM
    parameter IMEM_HEX_FILE         = "program.hex",
    parameter DMEM_HEX_FILE         = "",
    // If your IMEM hex is 32-bit words per line, set this to 1
    parameter bit IMEM_HEX_IS_WORDS        = 0
)(
    input  logic                             clk,
    input  logic                             rst,

    // -- IMEM (read) --
    input  logic [CPU_ADDR_BITS-1:0]         icache_addr,      // byte address (PC)
    output logic [FETCH_WIDTH*CPU_DATA_BITS-1:0] icache_dout,  // packed lanes: lane0 low bits
    output logic                             icache_dout_val,  // valid one cycle after icache_re
    input  logic                             icache_re,
    input  logic                             icache_stall,     // ignored

    // -- DMEM (read) --
    input  logic [CPU_ADDR_BITS-1:0]         dcache_addr,      // byte address
    output logic [CPU_DATA_BITS-1:0]         dcache_dout,
    output logic                             dcache_dout_val,
    input  logic                             dcache_re,
    // -- DMEM (write) --
    input  logic [CPU_DATA_BITS-1:0]         dcache_din,
    input  logic [(CPU_DATA_BITS/8)-1:0]     dcache_we,        // byte write enables
    input  logic                             dcache_stall      // ignored
);
    localparam int unsigned INST_BYTES       = 4; // RV32I fixed 32-bit instructions
    localparam int unsigned FETCH_BYTES      = FETCH_WIDTH * INST_BYTES;
    localparam int unsigned DMEM_BYTES       = (CPU_DATA_BITS / 8);

    // ------------------------------
    // Storage
    // ------------------------------
    logic [7:0] imem [IMEM_SIZE_BYTES-1:0];
    logic [7:0] dmem [DMEM_SIZE_BYTES-1:0];

    // ------------------------------
    // Preload (IMEM/DMEM)
    // ------------------------------
    initial begin
        // --- IMEM preload ---
        if (IMEM_HEX_FILE != "") begin
            if (!IMEM_HEX_IS_WORDS) begin
                $display("IMEM: Loading byte-hex '%s'", IMEM_HEX_FILE);
                for (int i = 0; i < IMEM_SIZE_BYTES; i++) imem[i] = 8'h00;
                $readmemh(IMEM_HEX_FILE, imem, 0);
            end else begin
                $display("IMEM: Loading word-hex '%s'", IMEM_HEX_FILE);
                logic [31:0] imem_w [IMEM_SIZE_BYTES/4-1:0];
                for (int i = 0; i < IMEM_SIZE_BYTES; i++) imem[i] = 8'h00;
                $readmemh(IMEM_HEX_FILE, imem_w, 0);
                for (int w = 0; w < IMEM_SIZE_BYTES/4; w++) begin
                    imem[w*4 + 0] = imem_w[w][7:0];
                    imem[w*4 + 1] = imem_w[w][15:8];
                    imem[w*4 + 2] = imem_w[w][23:16];
                    imem[w*4 + 3] = imem_w[w][31:24];
                end
            end
        end else begin
            $display("IMEM: No preload file.");
            for (int i = 0; i < IMEM_SIZE_BYTES; i++) imem[i] = 8'h00;
        end

        // --- DMEM preload or zero ---
        if (DMEM_HEX_FILE != "") begin
            $display("DMEM: Loading byte-hex '%s'", DMEM_HEX_FILE);
            for (int i = 0; i < DMEM_SIZE_BYTES; i++) dmem[i] = 8'h00;
            $readmemh(DMEM_HEX_FILE, dmem, 0);
        end else begin
            $display("DMEM: Zero-initializing.");
            for (int i = 0; i < DMEM_SIZE_BYTES; i++) dmem[i] = 8'h00;
        end
    end

    // ------------------------------
    // IMEM: 1-cycle read latency
    // ------------------------------
    logic [CPU_ADDR_BITS-1:0] icache_addr_d;
    logic                     icache_re_d;

    // Align assert (RV32I requires 4-byte)
    always_ff @(posedge clk) begin
        if (icache_re) begin
            assert (icache_addr[1:0] == 2'b00)
                else $error("IMEM fetch not 4-byte aligned: 0x%0h", icache_addr);
        end
    end

    // Pipe addr & RE
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            icache_addr_d <= '0;
            icache_re_d   <= 1'b0;
        end else begin
            icache_addr_d <= icache_re ? icache_addr : icache_addr_d;
            icache_re_d   <= icache_re;
        end
    end

    // Pack FETCH_WIDTH lanes, each 32b, little-endian bytes, lane0 in low bits
    always_comb begin
        icache_dout = '0;
        for (int w = 0; w < FETCH_WIDTH; w++) begin
            int base = icache_addr_d + (w * INST_BYTES);
            icache_dout[w*32 +: 8]      = (base + 0 < IMEM_SIZE_BYTES) ? imem[base + 0] : 8'h00;
            icache_dout[w*32 + 8 +: 8]  = (base + 1 < IMEM_SIZE_BYTES) ? imem[base + 1] : 8'h00;
            icache_dout[w*32 + 16 +: 8] = (base + 2 < IMEM_SIZE_BYTES) ? imem[base + 2] : 8'h00;
            icache_dout[w*32 + 24 +: 8] = (base + 3 < IMEM_SIZE_BYTES) ? imem[base + 3] : 8'h00;
        end
    end

    assign icache_dout_val = icache_re_d;

    // ------------------------------
    // DMEM: write = 0-cycle, read = 1-cycle
    // ------------------------------
    logic [CPU_ADDR_BITS-1:0] dcache_addr_d;
    logic                     dcache_re_d;

    // Writes (byte enables), synchronous
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // no-op
        end else begin
            for (int i = 0; i < DMEM_BYTES; i++) begin
                if (dcache_we[i]) begin
                    if ((dcache_addr + i) < DMEM_SIZE_BYTES) begin
                        dmem[dcache_addr + i] <= dcache_din[i*8 +: 8];
                    end
                end
            end
        end
    end

    // Read address/RE pipeline for 1-cycle latency
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            dcache_addr_d <= '0;
            dcache_re_d   <= 1'b0;
        end else begin
            dcache_addr_d <= dcache_re ? dcache_addr : dcache_addr_d;
            dcache_re_d   <= dcache_re;
        end
    end

    // Read mux with per-byte bounds checks
    always_comb begin
        dcache_dout = '0;
        for (int i = 0; i < DMEM_BYTES; i++) begin
            dcache_dout[i*8 +: 8] = (dcache_addr_d + i < DMEM_SIZE_BYTES) ? dmem[dcache_addr_d + i] : 8'h00;
        end
    end

    assign dcache_dout_val = dcache_re_d;

endmodule
