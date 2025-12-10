module wallace_8bit (
    // input logic clk, rst, begin_multiplication,
    input logic [7:0] a, b,

    output logic [15:0] result 

);


// 2d array matrix for wallace
logic [7:0] matrix [7:0];                // using unpacked array 


// partial product formation 
generate 
genvar i, j;
    for (i = 0; i < 8; i++)
    begin
        for (j = 0; j < 8; j++)
        begin
            assign matrix[i][j] = a[i] & b[j];

        end
    end
endgenerate


// MSB ----- LSB

// last bit assigned to LSB of result 
assign result[0] = matrix[0][0];

// result[1] 
logic HA1_c, result_1; 
half_adder HA1 (.a(matrix[1][0]), .b(matrix[0][1]), .S(result_1), .Cout(HA1_c)); 

assign result[1] = result_1;

// result[2] 
logic HA2_c;
logic FA2_sum, FA2_c, result_2; 

full_adder FA2 (.Cin(HA1_c), .a(matrix[1][1]), .b(matrix[0][2]), .S(FA2_sum), .Cout(FA2_c)); 
half_adder HA2 (.a(matrix[2][0]), .b(FA2_sum), .S(result_2), .Cout(HA2_c)); 
assign result[2] = result_2;

// result[3] 
logic FA3_1sum, FA3_1c, FA3_2sum, FA3_2c, HA3_c, result_3;

full_adder FA3_1 (.Cin(HA2_c), .a(matrix[1][2]), .b(matrix[0][3]), .S(FA3_1sum), .Cout(FA3_1c)); 
full_adder FA3_2 (.Cin(FA2_c), .a(matrix[2][1]), .b(FA3_1sum), .S(FA3_2sum), .Cout(FA3_2c)); 
half_adder HA3 (.a(matrix[3][0]), .b(FA3_2sum), .S(result_3), .Cout(HA3_c)); 
assign result[3] = result_3;

// result[4] 
logic FA4_1s, FA4_1c, FA4_2s, FA4_2c, FA4_3s, FA4_3c, HA4_c, result_4;

full_adder FA4_1 (.Cin(HA3_c), .a(matrix[1][3]), .b(matrix[0][4]), .S(FA4_1s), .Cout(FA4_1c)); 
full_adder FA4_2 (.Cin(FA3_1c), .a(matrix[2][2]), .b(FA4_1s), .S(FA4_2s), .Cout(FA4_2c)); 
full_adder FA4_3 (.Cin(FA3_2c), .a(matrix[3][1]), .b(FA4_2s), .S(FA4_3s), .Cout(FA4_3c)); 
half_adder HA4 (.a(matrix[4][0]), .b(FA4_3s), .S(result_4), .Cout(HA4_c)); 
assign result[4] = result_4;

// result[5] 
logic FA5_1s, FA5_1c, FA5_2s, FA5_2c, FA5_3s, FA5_3c, FA5_4s, FA5_4c, HA5_c, result_5;

full_adder FA5_1 (.Cin(HA4_c), .a(matrix[1][4]), .b(matrix[0][5]), .S(FA5_1s), .Cout(FA5_1c)); 
full_adder FA5_2 (.Cin(FA4_1c), .a(matrix[2][3]), .b(FA5_1s), .S(FA5_2s), .Cout(FA5_2c)); 
full_adder FA5_3 (.Cin(FA4_2c), .a(matrix[3][2]), .b(FA5_2s), .S(FA5_3s), .Cout(FA5_3c)); 
full_adder FA5_4 (.Cin(FA4_3c), .a(matrix[4][1]), .b(FA5_3s), .S(FA5_4s), .Cout(FA5_4c)); 
half_adder HA5 (.a(matrix[5][0]), .b(FA5_4s), .S(result_5), .Cout(HA5_c)); 
assign result[5] = result_5;

// result[6] <- CONTINUE THIS SHIT 
logic FA6_1s, FA6_1c, FA6_2s, FA6_2c, FA6_3s, FA6_3c, FA6_4s, FA6_4c, FA6_5s, FA6_5c, HA6_c, result_6;

full_adder FA6_1 (.Cin(HA5_c), .a(matrix[1][5]), .b(matrix[0][6]), .S(FA6_1s), .Cout(FA6_1c)); 
full_adder FA6_2 (.Cin(FA5_1c), .a(matrix[2][4]), .b(FA6_1s), .S(FA6_2s), .Cout(FA6_2c)); 
full_adder FA6_3 (.Cin(FA5_2c), .a(matrix[3][3]), .b(FA6_2s), .S(FA6_3s), .Cout(FA6_3c)); 
full_adder FA6_4 (.Cin(FA5_3c), .a(matrix[4][2]), .b(FA6_3s), .S(FA6_4s), .Cout(FA6_4c)); 
full_adder FA6_5 (.Cin(FA5_4c), .a(matrix[5][1]), .b(FA6_4s), .S(FA6_5s), .Cout(FA6_5c)); 
half_adder HA6 (.a(matrix[6][0]), .b(FA6_5s), .S(result_6), .Cout(HA6_c)); 
assign result[6] = result_6;

// result[7]
logic FA7_1s, FA7_1c, FA7_2s, FA7_2c, FA7_3s, FA7_3c, FA7_4s, FA7_4c, FA7_5s, FA7_5c, FA7_6s, FA7_6c;
logic HA7_c, result_7;

full_adder FA7_1 (.Cin(HA6_c), .a(matrix[1][6]), .b(matrix[0][7]), .S(FA7_1s), .Cout(FA7_1c)); 
full_adder FA7_2 (.Cin(FA6_1c), .a(matrix[2][5]), .b(FA7_1s), .S(FA7_2s), .Cout(FA7_2c)); 
full_adder FA7_3 (.Cin(FA6_2c), .a(matrix[3][4]), .b(FA7_2s), .S(FA7_3s), .Cout(FA7_3c)); 
full_adder FA7_4 (.Cin(FA6_3c), .a(matrix[4][3]), .b(FA7_3s), .S(FA7_4s), .Cout(FA7_4c)); 
full_adder FA7_5 (.Cin(FA6_4c), .a(matrix[5][2]), .b(FA7_4s), .S(FA7_5s), .Cout(FA7_5c)); 
full_adder FA7_6 (.Cin(FA6_5c), .a(matrix[6][1]), .b(FA7_5s), .S(FA7_6s), .Cout(FA7_6c)); 
half_adder HA7 (.a(matrix[7][0]), .b(FA7_6s), .S(result_7), .Cout(HA7_c)); 
assign result[7] = result_7;

//result[8]
logic FA8_1s, FA8_1c, FA8_2s, FA8_2c, FA8_3s, FA8_3c, FA8_4s, FA8_4c, FA8_5s, FA8_5c, FA8_6s, FA8_6c;
logic HA8_c, result_8;

full_adder FA8_1 (.Cin(HA7_c), .a(matrix[1][7]), .b(matrix[2][6]), .S(FA8_1s), .Cout(FA8_1c)); 
full_adder FA8_2 (.Cin(FA7_1c), .a(matrix[3][5]), .b(FA8_1s), .S(FA8_2s), .Cout(FA8_2c)); 
full_adder FA8_3 (.Cin(FA7_2c), .a(matrix[4][4]), .b(FA8_2s), .S(FA8_3s), .Cout(FA8_3c)); 
full_adder FA8_4 (.Cin(FA7_3c), .a(matrix[5][3]), .b(FA8_3s), .S(FA8_4s), .Cout(FA8_4c)); 
full_adder FA8_5 (.Cin(FA7_4c), .a(matrix[6][2]), .b(FA8_4s), .S(FA8_5s), .Cout(FA8_5c)); 
full_adder FA8_6 (.Cin(FA7_5c), .a(matrix[7][1]), .b(FA8_5s), .S(FA8_6s), .Cout(FA8_6c)); 
half_adder HA8 (.a(FA7_6c), .b(FA8_6s), .S(result_8), .Cout(HA8_c)); 
assign result[8] = result_8;


//result[9]
logic FA9_1s, FA9_1c, FA9_2s, FA9_2c, FA9_3s, FA9_3c, FA9_4s, FA9_4c, FA9_5s, FA9_5c, FA9_6c;
logic result_9;

full_adder FA9_1 (.Cin(HA8_c), .a(matrix[2][7]), .b(matrix[3][6]), .S(FA9_1s), .Cout(FA9_1c)); 
full_adder FA9_2 (.Cin(FA8_1c), .a(matrix[4][5]), .b(FA9_1s), .S(FA9_2s), .Cout(FA9_2c)); 
full_adder FA9_3 (.Cin(FA8_2c), .a(matrix[5][4]), .b(FA9_2s), .S(FA9_3s), .Cout(FA9_3c)); 
full_adder FA9_4 (.Cin(FA8_3c), .a(matrix[6][3]), .b(FA9_3s), .S(FA9_4s), .Cout(FA9_4c)); 
full_adder FA9_5 (.Cin(FA8_4c), .a(matrix[7][2]), .b(FA9_4s), .S(FA9_5s), .Cout(FA9_5c)); 
full_adder FA9_6 (.Cin(FA8_6c), .a(FA8_5c), .b(FA9_5s), .S(result_9), .Cout(FA9_6c)); 
assign result[9] = result_9;

//result[10]
logic FA10_1s, FA10_1c, FA10_2s, FA10_2c, FA10_3s, FA10_3c, FA10_4s, FA10_4c, FA10_5c;
logic result_10;

full_adder FA10_1 (.Cin(FA9_6c), .a(matrix[3][7]), .b(matrix[4][6]), .S(FA10_1s), .Cout(FA10_1c)); 
full_adder FA10_2 (.Cin(FA9_1c), .a(matrix[5][5]), .b(FA10_1s), .S(FA10_2s), .Cout(FA10_2c)); 
full_adder FA10_3 (.Cin(FA9_2c), .a(matrix[6][4]), .b(FA10_2s), .S(FA10_3s), .Cout(FA10_3c)); 
full_adder FA10_4 (.Cin(FA9_3c), .a(matrix[7][3]), .b(FA10_3s), .S(FA10_4s), .Cout(FA10_4c)); 
full_adder FA10_5 (.Cin(FA10_4s), .a(FA9_4c), .b(FA9_5c), .S(result_10), .Cout(FA10_5c)); 
assign result[10] = result_10;

//result[11]
logic FA11_1s, FA11_1c, FA11_2s, FA11_2c, FA11_3s, FA11_3c, FA11_4c;
logic result_11;

full_adder FA11_1 (.Cin(FA10_5c), .a(matrix[4][7]), .b(matrix[5][6]), .S(FA11_1s), .Cout(FA11_1c)); 
full_adder FA11_2 (.Cin(FA10_1c), .a(matrix[6][5]), .b(FA11_1s), .S(FA11_2s), .Cout(FA11_2c)); 
full_adder FA11_3 (.Cin(FA10_2c), .a(matrix[7][4]), .b(FA11_2s), .S(FA11_3s), .Cout(FA11_3c)); 
full_adder FA11_4 (.Cin(FA10_3c), .a(FA10_4c), .b(FA11_3s), .S(result_11), .Cout(FA11_4c)); 
assign result[11] = result_11;


//result[12]
logic FA12_1s, FA12_1c, FA12_2s, FA12_2c, FA12_3c;
logic result_12;

full_adder FA12_1 (.Cin(FA11_4c), .a(matrix[5][7]), .b(matrix[6][6]), .S(FA12_1s), .Cout(FA12_1c)); 
full_adder FA12_2 (.Cin(FA11_1c), .a(matrix[7][5]), .b(FA12_1s), .S(FA12_2s), .Cout(FA12_2c)); 
full_adder FA12_3 (.Cin(FA11_2c), .a(FA11_3c), .b(FA12_2s), .S(result_12), .Cout(FA12_3c)); 
assign result[12] = result_12;


//result[13]
logic FA13_1s, FA13_1c, FA13_2c;
logic result_13;

full_adder FA13_1 (.Cin(FA12_3c), .a(matrix[6][7]), .b(matrix[7][6]), .S(FA13_1s), .Cout(FA13_1c)); 
full_adder FA13_2 (.Cin(FA12_1c), .a(FA12_2c), .b(FA13_1s), .S(result_13), .Cout(FA13_2c)); 
assign result[13] = result_13;


//result[14]
logic FA14_1c;
logic result_14;

full_adder FA14_1 (.Cin(FA13_2c), .a(matrix[7][7]), .b(FA13_1c), .S(result_14), .Cout(FA14_1c)); 
assign result[14] = result_14;


//resault[15]
assign result[15] = FA14_1c;


endmodule 