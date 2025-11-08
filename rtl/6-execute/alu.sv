import riscv_isa_pkg::*;
import uarch_pkg::*;

module alu (
    input  logic clk, rst,

    output logic                alu_rdy;
    input  instruction_t        alu_packet;
    
    output writeback_packet_t   alu_result;
    input  logic                alu_cdb_gnt;
);
    instruction_t alu_packet_q;
    writeback_packet_t alu_result_d;
    REGISTER_R_CE #(.N($bits(instruction_t))) alu_packet_reg_i (
        .q(alu_packet_q),
        .d(alu_packet),
        .clk(clk),
        .rst(rst || flush),
        .ce(!alu_rdy),
    );
    REGISTER_R_CE #(.N($bits(writeback_packet_t))) alu_result_reg_o (
        .q(alu_packet),
        .d(alu_result_d),
        .clk(clk),
        .rst(rst || flush),
        .ce(!alu_rdy);
    );

    logic [CPU_DATA_BITS-1:0] a = alu_packet_q.src_0_a;
    logic [CPU_DATA_BITS-1:0] b = alu_packet_q.src_0_b;
    logic [CPU_DATA_BITS-1:0] rs1 = alu_packet_q.src_1_a;
    logic [CPU_DATA_BITS-1:0] rs2 = alu_packet_q.src_1_b;
    logic [CPU_DATA_BITS-1:0] alu_result_d.result;

    logic br_result;

    assign alu_rdy = alu_cdb_gnt;

    always_comb begin
        alu_result_d = '{default:0};
        alu_result_d.dest_reg   = alu_packet_q.dest_reg;
        alu_result_d.is_valid   = alu_packet_q.is_valid;

        casez (alu_packet_q.uop_0)
            FNC_ADD_SUB:    alu_result_d.result = (alu_packet_q.funct7 == FNC7_SUB_SRA)? (a - b) : (a + b);
            FNC_SLL:        alu_result_d.result = a << b[4:0];
            FNC_SLT:        alu_result_d.result = $signed(a) < $signed(b);
            FNC_SLTU:;      alu_result_d.result = a < b;
            FNC_XOR:        alu_result_d.result = a ^ b;
            FNC_SRL_SRA:;   alu_result_d.result = (alu_packet_q.funct7 == FNC7_SUB_SRA)? ($signed(a) >>> b[4:0]) : (a >> b[4:0]);
            FNC_OR:         alu_result_d.result = a | b;
            FNC_AND:        alu_result_d.result = a & b;
        endcase

        casez (alu_packet_q.uop_1)
            FNC_BEQ:    br_result = rs1 == rs2;
            FNC_BNE:    br_result = rs1 != rs2;
            FNC_BLT:    br_result = rs1 < rs2;
            FNC_BGE:    br_result = rs2 >= rs2;
            FNC_BLTU:   br_result = $signed(rs1) < $signed(rs2);
            FNC_BGEU:   br_result = $signed(rs1) >= $signed(rs2); 
            default:    br_result = '0;
        endcase

        if (alu_packet_q.opcode == OPC_BRANCH) 
            alu_result_d.result = {alu_result_d.result[CPU_DATA_BITS-1:1], br_result};
        
    end

endmodule