import riscv_isa_pkg::*;
import uarch_pkg::*;

module btb #(
    parameter ENTRIES   = BTB_ENTRIES,
    parameter TAG_WIDTH = 12
)(
    input  logic clk, rst,

    // READ (async)
    input  logic [CPU_ADDR_BITS-1:0]    pc,
    output logic [FETCH_WIDTH-1:0]      pred_hit,
    output logic [CPU_ADDR_BITS-1:0]    pred_targs    [FETCH_WIDTH-1:0],
    output logic [1:0]                  pred_types    [FETCH_WIDTH-1:0],

    // WRITE (sync)
    input  logic [FETCH_WIDTH-1:0]      update_val,
    input  logic [CPU_ADDR_BITS-1:0]    update_pc     [FETCH_WIDTH-1:0],
    input  logic [CPU_ADDR_BITS-1:0]    update_targ   [FETCH_WIDTH-1:0],
    input  logic [1:0]                  update_type   [FETCH_WIDTH-1:0],
    input  logic                        update_taken  [FETCH_WIDTH-1:0]
);

    localparam IDX_WIDTH = $clog2(ENTRIES);

    typedef struct packed {
        logic                       val;
        logic [TAG_WIDTH-1:0]       tag;
        logic [CPU_ADDR_BITS-1:0]   targ;
        logic [1:0]                 btype;
    } btb_entry_t;

    btb_entry_t btb [ENTRIES-1:0];

    //----------------------------------------------------------
    // Index and Tag Extraction
    //----------------------------------------------------------
    function automatic logic [IDX_WIDTH-1:0] get_index(input logic [CPU_ADDR_BITS-1:0] addr);
        return addr[IDX_WIDTH+2:2];
    endfunction

    function automatic logic [TAG_WIDTH-1:0] get_tag(input logic [CPU_ADDR_BITS-1:0] addr);
        return addr[TAG_WIDTH+IDX_WIDTH+2:IDX_WIDTH+2];
    endfunction

    //----------------------------------------------------------
    // Prediction (Async Read)
    //----------------------------------------------------------
    logic [IDX_WIDTH-1:0] idx0, idx1;
    logic [TAG_WIDTH-1:0] tag0, tag1;

    // Slot 0: PC (fetch address)
    assign idx0 = get_index(pc);
    assign tag0 = get_tag(pc);

    // Slot 1: PC + 4 (next sequential instruction)
    assign idx1 = get_index(pc + 4);
    assign tag1 = get_tag(pc + 4);

    always_comb begin
        // Slot 0
        pred_hit[0]   = btb[idx0].val && (btb[idx0].tag == tag0);
        pred_targs[0] = btb[idx0].targ;
        pred_types[0] = btb[idx0].btype;

        // Slot 1
        pred_hit[1]   = btb[idx1].val && (btb[idx1].tag == tag1);
        pred_targs[1] = btb[idx1].targ;
        pred_types[1] = btb[idx1].btype;
    end

    //----------------------------------------------------------
    // Update (Sync Write)
    //----------------------------------------------------------
    logic [IDX_WIDTH-1:0] update_idx  [FETCH_WIDTH-1:0];
    logic [TAG_WIDTH-1:0] update_tag  [FETCH_WIDTH-1:0];

    always_comb begin
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            update_idx[i] = get_index(update_pc[i]);
            update_tag[i] = get_tag(update_pc[i]);
        end
    end
    
    genvar i;
    generate
        for (i = 0; i < ENTRIES; i++) begin : gen_entries
            
            // Determine which slot(s) want to update this entry
            logic update_from_slot0, update_from_slot1;
            logic should_update;
            
            always_comb begin
                update_from_slot0 = update_val[0] && update_taken[0] && (i == update_idx[0]);
                update_from_slot1 = update_val[1] && update_taken[1] && (i == update_idx[1]);
                should_update = update_from_slot0 || update_from_slot1;
            end
            
            always_ff @(posedge clk) begin
                if (rst) begin
                    btb[i].val   <= 1'b0;
                    btb[i].tag   <= '0;
                    btb[i].targ  <= '0;
                    btb[i].btype <= '0;
                end else if (should_update) begin
                    // If both slots write to same entry, slot 1 wins (newer instruction)
                    if (update_from_slot1) begin
                        btb[i].val   <= 1'b1;
                        btb[i].tag   <= update_tag[1];
                        btb[i].targ  <= update_targ[1];
                        btb[i].btype <= update_type[1];
                    end else begin
                        btb[i].val   <= 1'b1;
                        btb[i].tag   <= update_tag[0];
                        btb[i].targ  <= update_targ[0];
                        btb[i].btype <= update_type[0];
                    end
                end
            end
        end
    endgenerate

endmodule
