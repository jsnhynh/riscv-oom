module Divider_Top (
    input clk, rst,
    input logic [31:0] rs1, rs2,
    input logic begin_divide,
    input logic sign_select,
    output logic division_complete_true,
    output logic [31:0] qoutient , remainder
);  
    

    //edge cases, divide by 0
    //signed division, divide -2^31 - 1 / -1
    //division by 0
    //dividedend is number being divided
    //ddividend is rs1, divisor is rs2
    logic [31:0] q, r;
    logic [31:0] rs1_true, rs2_true;
    logic division_complete;
    logic [31:0] q_neg, r_neg;
    assign q_neg = ~q + 32'd1;
    assign r_neg = ~r + 32'd1;

    //to do signed division with unsigneed values,
    //we must first convert both values to unsigned
    //record the signs oof both the divider and dividend
    //rs1 / rs2
    //if both are positive, then q and r are both positive
    //if rs1 is negative, rs2 positive, q is negative, r is positive
    //if rs1 is negative, rs2 negative, q is positive, r is negative
    //if rs1 is positive, rs2 negative, q is negative, r is negative  or divider unsigned_32bit(    
    always_comb begin
        if(rs2 == 32'd0) begin//divide by 0 case
            qoutient = 32'hffffffff;
            remainder  = rs1;
            division_complete_true  = 1'b1;
            rs1_true = rs1;
            rs2_true = rs2; 
        end
        else if((sign_select) & (rs1 == 32'h80000000) & (rs2 ==  32'hffffffff))  begin//signed overflow case
            qoutient =  32'h80000000;
            remainder = 32'd0;
            division_complete_true = 1'b1;
            rs1_true = rs1;
            rs2_true = rs2; 
        end
        else begin
            division_complete_true = division_complete;  
            if(sign_select == 1'b0) begin
                rs1_true = rs1;
                rs2_true = rs2; 
                qoutient = q;
                remainder = r;   
            end
           else begin
    rs1_true = rs1[31] ? (~rs1 + 32'd1) : rs1;
    rs2_true = rs2[31] ? (~rs2 + 32'd1) : rs2;

    case ({rs1[31], rs2[31]})
        2'b00: begin
            // + / +  => q +, r +
            qoutient = q;
            remainder = r;
        end
        2'b10: begin
            // - / +  => q -, r -  (remainder follows rs1)
            qoutient = q_neg;
            remainder = r_neg;
        end
        2'b11: begin
            // - / -  => q +, r -
            qoutient = q;
            remainder = r_neg;
        end
        2'b01: begin
            // + / -  => q -, r +  (remainder follows rs1)
            qoutient = q_neg;
            remainder = r;
        end
    endcase
end

        end
    end
    
    divider unsigned_32bit (
        .clk(clk), 
        .rst(), 
        .begin_divide(begin_divide),
        .x_input(rs1_true), 
        .y_input(rs2_true),
        .out(q), 
        .r(r),
        .division_complete(division_complete)
    );


    //output conditions


endmodule

