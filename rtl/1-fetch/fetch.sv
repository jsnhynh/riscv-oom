/*
 * Fetch Stage
 *
 * This module implements the first stage of the pipeline. It is responsible
 * for PC generation, handling sequential increments (PC+8) and redirects
 * from the ROB (on flush/mispredict). It issues read requests to the
 * I-Cache and passes the fetched instruction packet to the Instruction Buffer.
 */

import riscv_isa_pkg::*;
import uarch_pkg::*;

module fetch (
    input  logic clk, rst, flush, imem_stall,

    // Ports from ROB
    input  logic [2:0]                  pc_sel,
    input  logic [CPU_ADDR_BITS-1:0]    rob_pc,
    
    // IMEM Ports
    output logic [CPU_ADDR_BITS-1:0]    imem_addr,
    output logic                        imem_re,
    input  logic [FETCH_WIDTH*CPU_ADDR_BITS-1:0]  imem_dout,
    input  logic                        imem_dout_val,

    // Ports to Decoder
    input  logic                        decoder_rdy,
    output logic [CPU_ADDR_BITS-1:0]    inst_pcs    [PIPE_WIDTH-1:0],
    output logic [CPU_INST_BITS-1:0]    insts       [PIPE_WIDTH-1:0],
    output logic                        fetch_val
);

    logic [CPU_ADDR_BITS-1:0] pc, pc_next;
    logic inst_buffer_rdy;

    REGISTER_R_CE #(.N(CPU_ADDR_BITS), .INIT(PC_RESET)) pc_reg (
        .q(pc),
        .d(pc_next),
        .rst(rst),
        .ce(~imem_stall && imem_re),
        .clk(clk)
    ); 

    inst_buffer ib (
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .pc(pc),
        .imem_dout(imem_dout),
        .imem_dout_val(imem_dout_val),
        .inst_buffer_rdy(inst_buffer_rdy),
        
        .decoder_rdy(decoder_rdy),
        .inst_pcs(inst_pcs),
        .insts(insts),
        .fetch_val(fetch_val)
    );

    always_comb begin
        if (rst) begin
            pc_next = PC_RESET;
        end else begin
            case (pc_sel)
                'd1: pc_next = rob_pc; 
                default: pc_next = pc + 8; 
            endcase
        end
    end
    assign imem_addr = pc_next;
    assign imem_re = ~imem_stall && inst_buffer_rdy;

endmodule