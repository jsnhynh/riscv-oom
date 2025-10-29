/*
  mem_simple_rv32i_wordhex_vivado.sv
  ----------------------------------
  RV32I-friendly simple memory model that works cleanly in Vivado.
  * IMEM: read-only, WORD-PER-LINE $readmemh (32-bit per line), 1-cycle read latency
  * DMEM: byte-addressable R/W with byte write-enables, 1-cycle read latency
  * Parameterized sizes; no gigantic arrays derived from CPU_ADDR_BITS
  * Correct FETCH_WIDTH lane packing (lane0=PC, lane1=PC+4, ...)

  Notes:
    - RISC-V is little-endian. Words are stored little-endian in DMEM paths.
    - icache_stall / dcache_stall are present but ignored (simple model).
    - Includes robust $readmemh usage + optional post-load dump to help debug hex files
      that appear to "wrap" or truncate at certain lines.
*/

module mem_simple #(
    // --- Memory sizing ---
    parameter int unsigned IMEM_SIZE_BYTES = 32*1024, // size of instruction memory in bytes
    parameter int unsigned DMEM_SIZE_BYTES = 32*1024, // size of data memory in bytes
    // --- Core interface params ---
    parameter int unsigned CPU_ADDR_BITS   = 32,
    parameter int unsigned CPU_DATA_BITS   = 32,      // RV32I => 32
    parameter int unsigned FETCH_WIDTH     = 2,       // lanes per fetch (2-wide)
    // --- Preload files ---
    parameter string IMEM_HEX_FILE         = "program.hex",    // WORD-PER-LINE 32-bit hex
    // Optional: enable a console dump of the first few IMEM words after load
    parameter bit     IMEM_POSTLOAD_DUMP   = 1
)(
    input  logic                             clk,
    input  logic                             rst,

    // -- IMEM (read) --
    input  logic [CPU_ADDR_BITS-1:0]         icache_addr,      // byte address (PC)
    output logic [FETCH_WIDTH*CPU_DATA_BITS-1:0] icache_dout,  // lane0 low bits
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
    // ------------------------------
    // Local params & storage
    // ------------------------------
    localparam int unsigned INST_BYTES  = 4;                       // RV32I instruction size
    localparam int unsigned IMEM_WORDS  = IMEM_SIZE_BYTES / 4;     // 32-bit words
    localparam int unsigned DMEM_BYTES  = DMEM_SIZE_BYTES;         // bytes
    localparam int unsigned IMEM_IDX_W  = (IMEM_WORDS <= 1) ? 1 : $clog2(IMEM_WORDS);

    // Backing arrays
    logic [31:0] imem [0:IMEM_WORDS-1];    // WORD-PER-LINE for $readmemh
    logic [7:0]  dmem [0:DMEM_BYTES-1];    // byte-addressable data memory

    // ------------------------------
    // Preload (IMEM) — WORD-PER-LINE, 32b per line
    // ------------------------------
    initial begin : imem_preload
        if (IMEM_HEX_FILE == "") begin
            $error("IMEM: No preload file provided (IMEM_HEX_FILE is empty).");
        end else begin
            $display("IMEM: Loading word-hex '%s' (target %0d words)", IMEM_HEX_FILE, IMEM_WORDS);
            // Clear to 0 first so it's obvious what didn't get overwritten
            for (int w = 0; w < IMEM_WORDS; w++) imem[w] = 32'h0000_0000;
            // Use explicit start/end indices to avoid tool quirks
            $readmemh(IMEM_HEX_FILE, imem, 0, IMEM_WORDS-1);
        end
        // Initialize DMEM to zero
        for (int i = 0; i < DMEM_BYTES; i++) dmem[i] = 8'h00;

        if (IMEM_POSTLOAD_DUMP) begin
            int dump_n = (IMEM_WORDS < 32) ? IMEM_WORDS : 32;
            $display("IMEM post-load (first %0d words):", dump_n);
            for (int i = 0; i < dump_n; i++) begin
                $display("  [%0d] = %08h", i, imem[i]);
            end
        end
    end

    // ------------------------------
    // IMEM: 1-cycle read latency, parameterized FETCH_WIDTH
    // ------------------------------
    logic [CPU_ADDR_BITS-1:0] icache_addr_d;
    logic                     icache_re_d;

    // Pipe addr & RE
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            icache_addr_d <= '0;
            icache_re_d   <= 1'b0;
        end else begin
            icache_addr_d <= (icache_re) ? icache_addr : icache_addr_d;
            icache_re_d   <= (icache_re) ? 1'b1 : icache_re_d;
        end
    end

    // Word lookup inside IMEM array (with bounds guard)
    function automatic [31:0] word_at(input [CPU_ADDR_BITS-1:0] byte_addr);
        automatic logic [IMEM_IDX_W-1:0] idx;
        begin
            idx = byte_addr[IMEM_IDX_W+1:2]; // divide by 4, keep within IMEM_WORDS range
            if (idx < IMEM_WORDS) word_at = imem[idx];
            else                  word_at = 32'h00000013; // NOP on out-of-range
        end
    endfunction

    // Pack lanes: lane0=PC, lane1=PC+4, ... (each 32b)
    always_comb begin
        icache_dout = '0;
        for (int w = 0; w < FETCH_WIDTH; w++) begin
            logic [CPU_ADDR_BITS-1:0] addr_w = icache_addr_d + (w*INST_BYTES);
            icache_dout[w*32 +: 32] = (rst)? 'x:word_at(addr_w);
        end
    end

    assign icache_dout_val = icache_re_d && !icache_stall;

    // ------------------------------
    // DMEM: write = 0-cycle, read = 1-cycle
    // ------------------------------
    logic [CPU_ADDR_BITS-1:0] dcache_addr_d;
    logic                     dcache_re_d;

    // Writes (byte enables), synchronous
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Already cleared in initial; keep state on rst deassert for simplicity
        end else begin
            for (int i = 0; i < (CPU_DATA_BITS/8); i++) begin
                if (dcache_we[i]) begin
                    if ((dcache_addr + i) < DMEM_BYTES) begin
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

    // Read mux (little-endian), with bounds checks
    always_comb begin
        dcache_dout = '0;
        for (int i = 0; i < (CPU_DATA_BITS/8); i++) begin
            if ((dcache_addr_d + i) < DMEM_BYTES)
                dcache_dout[i*8 +: 8] = dmem[dcache_addr_d + i];
            else
                dcache_dout[i*8 +: 8] = 8'hXX;
        end
    end

    assign dcache_dout_val = dcache_re_d;

endmodule