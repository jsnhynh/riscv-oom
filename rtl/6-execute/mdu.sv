import riscv_isa_pkg::*;
import uarch_pkg::*;

module mdu (
    input  logic clk, rst, flush,

    output logic                mdu_rdy,
    input  instruction_t        mdu_packet,
    
    output writeback_packet_t   mdu_result,
    input  logic                mdu_cdb_gnt
);
    
instruction_t in_reg;
writeback_packet_t out_reg;
logic comp_done, load_out, mul_a_sign_sel, mul_b_sign_sel, div_sign_sel;
logic [CPU_DATA_BITS - 1 : 0] rs1, rs2, next_out; 


//input register
always_ff @ (posedge clk) begin
    if(rst || flush || comp_done) in_reg <= '0;
    else if(mdu_rdy && mdu_packet.is_valid) in_reg <= mdu_packet;
end

//output register
always_ff @ (posedge clk) begin
    if(rst || flush || comp_done) mdu_result <= '0;
    else if (load_out) begin
        mdu_result.result <= next_out;
        mdu_result.is_valid <= 1'b1;
        mdu_result.dest_tag <= in_reg.dest_tag;
    end
end



assign rs1 = in_reg.src_0_a.data;
assign rs2 = in_reg.src_0_b.data;


always_comb begin 
    case (in_reg.uop_0)
        FNC_MULHSU :begin
            mul_a_sign_sel = 1'b1;
            mul_b_sign_sel = 1'b0;
        end
       FNC_MUL, FNC_MULH: begin
            mul_a_sign_sel = 1'b1;
            mul_b_sign_sel = 1'b1;
       end
        default: begin
            mul_a_sign_sel = 1'b0;
            mul_b_sign_sel = 1'b0;
        end
    endcase

    case (in_reg.uop_0)
        FNC_DIV, FNC_REM: div_sign_sel = 1'b1; 
        default: div_sign_sel = 1'b0;
    endcase
end

logic begin_divide, begin_multiply, division_complete_true, multiplication_complete;
logic [CPU_DATA_BITS - 1 : 0] qoutient, remainder;
logic [2*CPU_DATA_BITS - 1 : 0] product;
Divider_Top div (
    .clk(clk), 
    .rst(rst),
    .rs1(rs1), 
    .rs2(rs2),
    .begin_divide(begin_divide),
    .sign_select(div_sign_sel),
    .division_complete_true(division_complete_true),
    .qoutient(qoutient), 
    .remainder(remainder)
); 


 fs_wallace_2stage_mul64 mul (
    .clk(clk),
    .rst(rst),
    .valid_in(begin_multiply),
    .sign_selectedA(mul_a_sign_sel),
    .sign_selectedB(mul_b_sign_sel),
    .a(rs1),
    .b(rs2),

    .valid_out(multiplication_complete),
    .product(product)
);


typedef enum logic [3:0] {
    IDLE,
    WAIT_MULT,
    WAIT_DIV,
    WAIT_CDB
  } mdu_state;
mdu_state state, next_state;

always_ff @( posedge clk ) begin 
    if(rst || flush) begin
        state <= IDLE;
    end
    else state <= next_state;
end

always_comb begin
    mdu_rdy = 1'b0;
    begin_multiply = 1'b0;
    begin_divide = 1'b0;
    load_out = 1'b0;
    comp_done = 1'b0;
    case (state)
        IDLE : begin
            begin_divide = 1'b0;
            mdu_rdy = 1'b1;
            if(mdu_packet.is_valid) begin
                if(mdu_packet.uop_0 <= 3'b011) next_state = WAIT_MULT;
                else next_state = WAIT_DIV;
            end
            else next_state = IDLE;
        end
        WAIT_MULT : begin
            begin_multiply = 1'b1;
            if(multiplication_complete) begin
                next_state = WAIT_CDB;
                load_out = 1'b1;
                case (in_reg.uop_0)
                    FNC_MULH, FNC_MULHU, FNC_MULHSU: next_out = product[63:32]; 
                    default: next_out = product[31:0];
                endcase
            end
            else next_state = WAIT_MULT;
        end
        WAIT_DIV : begin
            begin_divide = 1'b1;
            if(division_complete_true) begin
                load_out = 1'b1;
                next_state = WAIT_CDB;
                case (in_reg.uop_0)
                    FNC_DIV, FNC_DIVU: next_out = qoutient; 
                    default: next_out = remainder;
                endcase
            end
            else next_state = WAIT_DIV;

        end
        WAIT_CDB : begin
            if(mdu_cdb_gnt) begin
                next_state = IDLE;
                comp_done = 1'b1;
            end
        end
    endcase
end

endmodule