/*
    Memory Simple

    Models both Instruction and Data memory using a single 
    byte-addressable register array. Featrues preloaded 
    capability via $readmemh and fixed 1-cycle rad latency.
*/
import uarch_pkg::*;

module mem_simple #(
    parameter IMEM_HEX_FILE     = "program.hex" // Default hex file to load
    parameter DMEM_HEX_FILE     = ""            // Optional hex file for DMEM preload
)(
    input logic clk, rst,

    // IMEM Ports (Read Only)
    input  logic [CPU_ADDR_BITS-1:0]    icache_addr,
    output logic [FETCH_WIDTH*CPU_DATA_BITS-1:0]  icache_dout,  // Parameterized fetch width
    output logic                        icache_dout_val,
    input  logic                        icache_re,
    input  logic                        icache_stall,   // Ignored

    // DMEM Ports (Read)
    input  logic [CPU_ADDR_BITS-1:0]    dcache_addr,
    output logic [CPU_DATA_BITS-1:0]    dcache_dout,
    output logic                        dcache_dout_val,
    input  logic                        dcache_re,
    // DMEM Ports (Write)
    input  logic [CPU_DATA_BITS-1:0]    dcache_din,
    input  logic [3:0]                  dcache_we,      // Byte write enables
    input  logic                        dcache_stall    // Ignored
);
    localparam FETCH_WIDTH_BYTES = FETCH_WIDTH * (CPU_DATA_BITS / 8);

    // -- Internal Memory Array --
    logic [7:0] imem [IMEM_SIZE_BYTES-1:0];
    logic [7:0] dmem [DMEM_SIZE_BYTES-1:0];

    // -- Preloading --
    initial begin
        if (IMEM_HEX_FILE != "") begin
            $display("Simple IMEM Model: Loading %s", IMEM_HEX_FILE);
            $readmemh(IMEM_HEX_FILE, imem, 0); // Load IMEM
        end else begin
            $display("Simple IMEM Model: No preload file specified.");
        end

        if (DMEM_HEX_FILE != "") begin
            $display("Simple DMEM Model: Loading %s", DMEM_HEX_FILE);
            $readmemh(DMEM_HEX_FILE, dmem, 0); // Load DMEM
        end else begin
            $display("Simple DMEM Model: Initializing to zero.");
             for (int i = 0; i < DMEM_SIZE_BYTES; i++) dmem[i] = 8'b0; // Zero init DMEM
        end
    end

    //-------------------------------------------------------------
    // IMEM Read Logic (1 cycle latency)
    //-------------------------------------------------------------
    logic [CPU_ADDR_BITS-1:0]    icache_addr_dly;
    logic                        icache_re_dly;

    always_ff @(posedge clk) begin
        if (rst) begin
            icache_re_dly   <= 1'b0;
            icache_addr_dly <= '0;
        end else begin
            icache_re_dly   <= icache_re;
            icache_addr_dly <= icache_addr;
        end
    end

    always_comb begin
        icache_dout = 'x; // Default
        for (int i = 0; i < FETCH_WIDTH_BYTES; i++) begin
            if ((icache_addr_dly + i) < IMEM_SIZE_BYTES) begin
                icache_dout[i*8 +: 8] = imem[icache_addr_dly + i];
            end else begin
                icache_dout[i*8 +: 8] = 8'h00;
            end
        end
    end
    assign icache_dout_val = icache_re_dly;

    //-------------------------------------------------------------
    // DMEM Read/Write Logic (Write=0 cycle, Read=1 cycle latency)
    //-------------------------------------------------------------
    logic [CPU_ADDR_BITS-1:0]    dcache_addr_dly;
    logic                        dcache_re_dly;

    // --- Write Logic (Synchronous to dcache_array) ---
    always_ff @(posedge clk) begin
        if (!rst) begin
            if (dcache_addr < DMEM_SIZE_BYTES - 3) begin // Use DMEM size
                if (dcache_we[0]) dmem[dcache_addr + 0] <= dcache_din[7:0]; // Write to dcache_array
                if (dcache_we[1]) dmem[dcache_addr + 1] <= dcache_din[15:8];
                if (dcache_we[2]) dmem[dcache_addr + 2] <= dcache_din[23:16];
                if (dcache_we[3]) dmem[dcache_addr + 3] <= dcache_din[31:24];
            end
        end
    end

    // --- Read Logic (1 cycle latency from dcache_array) ---
    always_ff @(posedge clk) begin
        if (rst) begin
            dcache_re_dly   <= 1'b0;
            dcache_addr_dly <= '0;
        end else begin
            dcache_re_dly   <= dcache_re;
            dcache_addr_dly <= dcache_addr;
        end
    end

    always_comb begin
        dcache_dout = 'x; // Default
        for (int i = 0; i < 4; i++) begin
            if ((dcache_addr_dly + i) < DMEM_SIZE_BYTES) begin // Use DMEM size
                dcache_dout[i*8 +: 8] = dcache_array[dcache_addr_dly + i]; // Read from dcache_array
            end else begin
                dcache_dout[i*8 +: 8] = 8'hXX;
            end
        end
    end
    assign dcache_dout_val = dcache_re_dly;

endmodule