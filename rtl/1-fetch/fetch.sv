module fetch (
    input logic clk, rst, flush, cache_stall,

    input [2:0] pc_sel,
    input [`CPU_ADDR_BITS] rob_pc,
    
    // IMEM Ports
    output [`CPU_ADDR_BITS-1:0] icache_addr,
    input [2*`CPU_ADDR_BITS-1:0] icache_dout,
    input icache_dout_val,
    output icache_re,

    // Decoder Ports
    input  logic decoder_rdy,
    output logic [`CPU_ADDR_BITS-1:0] pc, pc_4,
    output logic [`CPU_INST_BITS-1:0] inst0, inst1,
    output logic                      inst_val
);

    logic [`CPU_ADDR_BITS-1:0] pc, pc_next;

    REGISTER_R_CE #(.N(`CPU_ADDR_BITS)) pc_reg (
        .q(pc),
        .d(pc_next),
        .rst(rst),
        .ce(~cache_stall),
        .clk(clk)
    ); 

    inst_buffer ib (
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .pc(pc),
        .icache_dout(icache_dout),
        .icache_dout_val(icache_dout_val),
        .inst_buffer_rdy(inst_buffer_rdy),
        
        .decoder_rdy(decoder_rdy),
        .pc(pc),
        .pc_4(pc_4),
        .inst0(inst0),
        .inst1(inst1),
        .inst_val(inst_val)
    );

    always_comb begin
        case (pc_sel)
            'd1: pc_next = rob_id; 
            default: pc_next = pc + 4; 
        endcase
    end

endmodule