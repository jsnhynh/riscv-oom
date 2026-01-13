import riscv_isa_pkg::*;
import uarch_pkg::*;

module btb #(
    parameter ENTRIES   = 64,  // Total Entries
    parameter TAG_WIDTH = 12
)(
    input  logic clk, rst,

    // READ (async)
    input  logic [CPU_ADDR_BITS-1:0]    pc,
    output logic [FETCH_WIDTH-1:0]      pred_hit,
    output logic [CPU_ADDR_BITS-1:0]    pred_targs [FETCH_WIDTH-1:0],
    output logic [1:0]                  pred_types [FETCH_WIDTH-1:0],

    // WRITE (sync)
    input  logic                        update_val,
    input  logic [CPU_ADDR_BITS-1:0]    update_pc,
    input  logic [CPU_ADDR_BITS-1:0]    update_targ,
    input  logic [1:0]                  update_type,
    input  logic                        update_taken
);

    localparam BANK_ENTRIES = ENTRIES / FETCH_WIDTH;    // Entries per Bank
    localparam IDX_WIDTH    = $clog2(BANK_ENTRIES);

    // Entry definition
    typedef struct packed {
        logic                       val;
        logic [TAG_WIDTH-1:0]       tag;
        logic [CPU_ADDR_BITS-1:0]   targ;
        logic [1:0]                 btype;
    } btb_entry_t;

    // Two banks in one array
    btb_entry_t banks [FETCH_WIDTH-1:0][BANK_ENTRIES-1:0];

    //----------------------------------------------------------
    // Index and Tag Extraction
    //----------------------------------------------------------
    function automatic logic [IDX_WIDTH-1:0] get_index(input logic [CPU_ADDR_BITS-1:0] addr);
        return addr[IDX_WIDTH+2:3];
    endfunction

    function automatic logic [TAG_WIDTH-1:0] get_tag(input logic [CPU_ADDR_BITS-1:0] addr);
        return addr[TAG_WIDTH+IDX_WIDTH+2:IDX_WIDTH+3];
    endfunction

    //----------------------------------------------------------
    // Prediction (Async Read)
    //----------------------------------------------------------
    logic [IDX_WIDTH-1:0] pred_idx;
    logic [TAG_WIDTH-1:0] pred_tag;

    assign pred_idx = get_index(pc);
    assign pred_tag = get_tag(pc);

    always_comb begin
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            pred_hit[i]   = banks[i][pred_idx].val && (banks[i][pred_idx].tag == pred_tag);
            pred_targs[i] = banks[i][pred_idx].targ;
            pred_types[i] = banks[i][pred_idx].btype;
        end
    end

    //----------------------------------------------------------
    // Update (Sync Write)
    //----------------------------------------------------------
    logic [IDX_WIDTH-1:0] update_idx;
    logic [TAG_WIDTH-1:0] update_tag;
    logic                 update_bank_sel;

    assign update_idx      = get_index(update_pc);
    assign update_tag      = get_tag(update_pc);
    assign update_bank_sel = update_pc[2];

    //----------------------------------------------------------
    // Reset Logic - Use generate to avoid nested loops
    //----------------------------------------------------------
    genvar bank_idx, entry_idx;
    generate
        for (bank_idx = 0; bank_idx < FETCH_WIDTH; bank_idx++) begin : gen_banks
            for (entry_idx = 0; entry_idx < BANK_ENTRIES; entry_idx++) begin : gen_entries
                always_ff @(posedge clk) begin
                    if (rst) begin
                        banks[bank_idx][entry_idx].val   <= 1'b0;
                        banks[bank_idx][entry_idx].tag   <= '0;
                        banks[bank_idx][entry_idx].targ  <= '0;
                        banks[bank_idx][entry_idx].btype <= '0;
                    end else if (update_val && update_taken && (bank_idx == update_bank_sel) && (entry_idx == update_idx)) begin
                        banks[bank_idx][entry_idx].val   <= 1'b1;
                        banks[bank_idx][entry_idx].tag   <= update_tag;
                        banks[bank_idx][entry_idx].targ  <= update_targ;
                        banks[bank_idx][entry_idx].btype <= update_type;
                    end
                end
            end
        end
    endgenerate

endmodule