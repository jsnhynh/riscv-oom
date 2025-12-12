module half_adder (
    input logic a,b,

    output logic S, Cout
);

assign S = a ^ b; 
assign Cout = a & b;

endmodule 



module full_adder (
    input logic Cin, a, b, 
    output logic S, Cout 
);

assign S = Cin ^ a ^ b;
assign Cout = (Cin & a)|(Cin & b)|(a & b);

endmodule 


// for 64 bit multiplier 

module adder_64bit (
    
    input logic [63: 0] a, b,
    output logic [63: 0] S,
    output logic Cout

);

// variable assignment 
logic [63:0] Cin; 

half_adder first_adder(.a(a[0]), .b(b[0]), .S(S[0]), .Cout(Cin[1]));

// two variables 
genvar i;

generate
    for (i = 1; i < 63; i++)
    begin
        full_adder FA(.Cin(Cin[i]),
                      .a(a[i]), 
                      .b(b[i]), 
                      .S(S[i]), 
                      .Cout(Cin[i+1])
                      );

    end

endgenerate

// last adder 
full_adder last_FA(.Cin(Cin[62]), .a(a[63]), .b(b[63]), .S(S[63]), .Cout(Cout));


endmodule 



