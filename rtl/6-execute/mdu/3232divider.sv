//x/y
//how many times can we shift y before it bbecomes greater than x
//there are 32 options

module divider (
    input clk, rst, begin_divide,
    input logic [31:0] x_input, y_input,
    output logic [31:0] out, r,
    output logic division_complete
);

    genvar i;
    logic  shift_compare [31:0];//1 is greater than, 0 is less than 
    logic  [33:0]  x , y;
    
    generate
        for (i = 0; i < 32 ; i++) begin
            assign shift_compare[i] = (x >= (y<<i)) ? 1'd1 : 1'd0;
        end
    endgenerate

    logic [15:0] index , index_true;
    always_comb begin 
        index = 16'd0;
        for (int i = 1; i < 32 ;i++ ) begin
            if(shift_compare[i-1] ^ shift_compare[i] == 1) begin 
                index = i-1;
                break;
            end
            if(i == 16'd31) begin
                if (shift_compare[i] == 1) index = 16'd31;
                else index = 16'd0;
                break;
            end
        end
    end
    logic flag;
    logic [31:0] shift_temp;
    assign shift_temp = 16'd1 <<index;
    logic [31:0] idk, idx2;
    assign idx2 = y<<index;
    assign idk = x - idx2; 
    always_ff @(posedge clk) begin
        if(~begin_divide) begin
            out <= 16'd0;
            r <= 16'd0;
            x <= 33'd0;
            y <= 33'd0;
            division_complete <= 1'b0;
            flag <= 1'b0;
        end

        
        else if(begin_divide & ~flag) begin
            x <= {1'd0 , x_input};
            y <= {1'd0 , y_input};
            flag <= 1'b1;
            out <= 16'd0;
            r   <= 16'd0;
            division_complete <= 1'b0;
        end

        else if (y_input != y[31:0])begin
            flag <= 1'b0; //for consecutive divisions
            division_complete <= 1'b0;    
        end

        else begin
            if(x >= y) begin
                out <= out + shift_temp;
                x   <= idk;
                division_complete <= 1'b0;
            end
            else if (x < y) begin
                out <= out;
                r <= x;
                division_complete <= 1'b1;
            end
        end
    end
    
endmodule