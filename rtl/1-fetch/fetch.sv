import uarch_pkg::*;

module fetch (
    input  logic clk, rst, flush, icache_stall,

    input logic [2:0]                   pc_sel,
    input logic [CPU_ADDR_BITS-1:0]     rob_pc,
    
    // IMEM Ports
    output logic [CPU_ADDR_BITS-1:0]    icache_addr,
    input  logic [2*CPU_ADDR_BITS-1:0]  icache_dout,
    input  logic                        icache_dout_val,
    output logic                        icache_re,

    // Decoder Ports
    input  logic                        decoder_rdy,
    output logic [CPU_ADDR_BITS-1:0]    pc,     pc_4,
    output logic [CPU_INST_BITS-1:0]    inst0,  inst1,
    output logic                        inst_val
);

    logic [CPU_ADDR_BITS-1:0] pc, pc_next;
    logic inst_buffer_rdy;

    REGISTER_R_CE #(.N(CPU_ADDR_BITS)) pc_reg (
        .q(pc),
        .d(pc_next),
        .rst(rst),
        .ce(~icache_stall && icache_re),
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
            'd1: pc_next = rob_pc; 
            default: pc_next = pc + 8; 
        endcase
    end
    assign icache_addr = pc;
    assign icache_re = ~icache_stall && inst_buffer_rdy;

endmodule