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
    input  logic clk, rst, flush,

    // Ports from ROB
    input  logic [2:0]                  pc_sel,
    input  logic [CPU_ADDR_BITS-1:0]    rob_pc,
    
    // IMEM Ports
    input  logic                        imem_req_rdy,
    output logic                        imem_req_val,
    output logic [CPU_ADDR_BITS-1:0]    imem_req_packet,

    output logic                        imem_rec_rdy,
    input  logic                        imem_rec_val,
    input  logic [FETCH_WIDTH*CPU_INST_BITS-1:0]    imem_rec_packet,

    // Ports to Decoder
    input  logic                        decoder_rdy,
    output logic [CPU_ADDR_BITS-1:0]    inst_pcs    [PIPE_WIDTH-1:0],
    output logic [CPU_INST_BITS-1:0]    insts       [PIPE_WIDTH-1:0],
    output logic                        fetch_val
);

    logic [CPU_ADDR_BITS-1:0] pc, pc_next;

    REGISTER_R_CE #(.N(CPU_ADDR_BITS), .INIT(PC_RESET)) pc_reg (
        .q(pc),
        .d(pc_next),
        .rst(rst),
        .ce(imem_req_rdy && imem_req_val),
        .clk(clk)
    ); 

    inst_buffer ib (
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .pc(pc),
        .inst_buffer_rdy(imem_rec_rdy),
        .imem_rec_packet(imem_rec_packet),
        .imem_rec_val(imem_rec_val),
        
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
    assign imem_req_packet = pc_next;
    assign imem_req_val = imem_req_rdy && imem_rec_rdy;

endmodule