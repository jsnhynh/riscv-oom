/*
 * Simple Memory Model with Separate I/D Spaces
 *
 * This is a simulation-only module that models distinct Instruction and Data
 * memory spaces. Each space is a byte-addressable array with 1-cycle
 * read latency and 0-cycle (synchronous) write latency for DMEM.
 *
 * It supports preloading from a hex file via $readmemh for both IMEM and DMEM.
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
    input  logic                        clk,
    input  logic                        rst,

    // -- IMEM (read) --
    input  logic                        imem_req_rdy,   // Made input for forced stimulus
    input  logic                        imem_req_val,
    input  logic [CPU_ADDR_BITS-1:0]    imem_req_packet,

    input  logic                        imem_rec_rdy,
    output logic                        imem_rec_val,
    output logic [FETCH_WIDTH*CPU_INST_BITS-1:0]    imem_rec_packet,

    // -- DMEM --
    output logic                        dmem_req_rdy,
    input  instruction_t                dmem_req_packet,

    input  logic                        dmem_rec_rdy,
    output writeback_packet_t           dmem_rec_packet
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
    logic [CPU_ADDR_BITS-1:0] imem_req_addr_d;
    logic                     imem_req_val_d;

    // Pipe addr & RE
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            imem_req_addr_d <= '0;
            imem_req_val_d  <= 1'b0;
        end else if (imem_req_val && imem_rec_rdy) begin
            imem_req_addr_d <= imem_req_packet;
            imem_req_val_d  <= imem_req_val;
        end else begin
            imem_req_addr_d <= imem_req_addr_d;
            imem_req_val_d  <= imem_req_val_d;
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
        imem_rec_packet = '0;
        for (int w = 0; w < FETCH_WIDTH; w++) begin
            logic [CPU_ADDR_BITS-1:0] addr_w = imem_req_addr_d + (w*INST_BYTES);
            imem_rec_packet[w*32 +: 32] = (rst)? 'x:word_at(addr_w);
        end
    end

    assign imem_rec_val = imem_req_val_d && imem_req_rdy;

    // ------------------------------
    // DMEM: write = 0-cycle, read = 1-cycle
    // ------------------------------
    instruction_t   dmem_req_packet_d;
    logic           dmem_req_load_d;

    assign dmem_req_rdy = dmem_rec_rdy && dmem_rec_packet.is_valid;

    // Writes (byte enables), synchronous
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Already cleared in initial; keep state on rst deassert for simplicity
        end if (dmem_req_packet.is_valid && (dmem_req_packet.opcode == OPC_STORE)) begin
            logic [3:0] we;
            case (dmem_req_packet.uop_0)
                FNC_B: we = 4'b0001 << dmem_req_packet.src_0_a.data [1:0];
                FNC_H: we = 4'b0011 << dmem_req_packet.src_0_a.data [1:0];
                FNC_W: we = 4'b1111;
                default: we = 4'b0000;
            endcase

            if (dmem_req_packet.src_0_a.data < DMEM_BYTES - 3) begin
                if (we[0]) dmem[dmem_req_packet.src_0_a.data + 0] <= dmem_req_packet.src_1_b[7:0];
                if (we[1]) dmem[dmem_req_packet.src_0_a.data + 1] <= dmem_req_packet.src_1_b[15:8];
                if (we[2]) dmem[dmem_req_packet.src_0_a.data + 2] <= dmem_req_packet.src_1_b[23:16];
                if (we[3]) dmem[dmem_req_packet.src_0_a.data + 3] <= dmem_req_packet.src_1_b[31:24];
            end
        end
    end

    // Read address/RE pipeline for 1-cycle latency
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            dmem_req_packet_d       <= '{default:'0};
            dmem_req_load_d         <= 1'b0;
        end else begin
            if (dmem_req_packet.is_valid && (dmem_req_packet.opcode == OPC_LOAD)) begin
                dmem_req_packet_d   <= dmem_req_packet;
                dmem_req_load_d     <= 1'b1;
            end else begin
                dmem_req_packet_d   <= '{default:'0};
                dmem_req_load_d     <= 1'b0;
            end
        end
    end

    // Read Result Generation
    logic [CPU_DATA_BITS-1:0] word_data;
    always_comb begin
        dmem_rec_packet = '{default:'0};
        dmem_rec_packet.is_valid = dmem_req_load_d;
        dmem_rec_packet.dest_tag = dmem_req_packet_d.dest_tag;

        for (int i = 0; i < 4; i++) begin
            if ((dmem_req_packet_d.src_0_a + i) < DMEM_BYTES) begin
                word_data[i*8 +: 8] = dmem[dmem_req_packet_d.src_0_a + i];
            end else begin
                word_data[i*8 +: 8] = 8'hXX;
            end
        end

        case(dmem_req_packet_d.uop_0)
            FNC_B:  dmem_rec_packet.result = {{24{word_data[7]}},   word_data[7:0]};
            FNC_H:  dmem_rec_packet.result = {{16{word_data[15]}},  word_data[15:0]};
            FNC_W:  dmem_rec_packet.result = word_data;
            FNC_BU: dmem_rec_packet.result = {{24{1'b0}}, word_data[7:0]};
            FNC_HU: dmem_rec_packet.result = {{16{1'b0}}, word_data[15:0]};
            default: dmem_rec_packet.result = 'x; // Invalid load
        endcase
    end

endmodule