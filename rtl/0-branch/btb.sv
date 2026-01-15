import riscv_isa_pkg::*;
import uarch_pkg::*;
import branch_pkg::*;

module btb #(
    parameter ENTRIES   = BTB_ENTRIES,
    parameter TAG_WIDTH = BTB_TAG_WIDTH
)(
    input  logic clk, rst,

    // READ (async)
    input  logic [CPU_ADDR_BITS-1:0]    pc,
    output btb_read_port_t              read_ports  [FETCH_WIDTH-1:0],

    // WRITE (sync)
    input  btb_write_port_t             write_ports [FETCH_WIDTH-1:0]
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
    // Prediction (Async Read) - Dual Port
    //----------------------------------------------------------
    logic [IDX_WIDTH-1:0] idx [FETCH_WIDTH-1:0];
    logic [TAG_WIDTH-1:0] tag [FETCH_WIDTH-1:0];

    // Slot 0: PC (fetch address)
    assign idx[0] = get_index(pc);
    assign tag[0] = get_tag(pc);

    // Slot 1: PC + 4 (next sequential instruction)
    assign idx[1] = get_index(pc + 4);
    assign tag[1] = get_tag(pc + 4);

    always_comb begin
        for (int p = 0; p < FETCH_WIDTH; p++) begin
            read_ports[p].hit  = btb[idx[p]].val && (btb[idx[p]].tag == tag[p]);
            read_ports[p].targ = btb[idx[p]].targ;
            read_ports[p].btype = btb[idx[p]].btype;
        end
    end

    //----------------------------------------------------------
    // Update (Sync Write) - Dual Port
    //----------------------------------------------------------
    logic [IDX_WIDTH-1:0] update_idx [FETCH_WIDTH-1:0];
    logic [TAG_WIDTH-1:0] update_tag [FETCH_WIDTH-1:0];

    always_comb begin
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            update_idx[i] = get_index(write_ports[i].pc);
            update_tag[i] = get_tag(write_ports[i].pc);
        end
    end
    
    genvar i;
    generate
        for (i = 0; i < ENTRIES; i++) begin : gen_entries
            
            // Determine which slot(s) want to update this entry
            logic update_from_slot0, update_from_slot1;
            logic should_update;
            
            always_comb begin
                update_from_slot0 = write_ports[0].val && write_ports[0].taken && (i == update_idx[0]);
                update_from_slot1 = write_ports[1].val && write_ports[1].taken && (i == update_idx[1]);
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
                        btb[i].targ  <= write_ports[1].targ;
                        btb[i].btype <= write_ports[1].btype;
                    end else begin
                        btb[i].val   <= 1'b1;
                        btb[i].tag   <= update_tag[0];
                        btb[i].targ  <= write_ports[0].targ;
                        btb[i].btype <= write_ports[0].btype;
                    end
                end
            end
        end
    endgenerate

endmodule