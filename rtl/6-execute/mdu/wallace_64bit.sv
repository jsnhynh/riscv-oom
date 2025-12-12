module fs_wallace_256v1 (
    input  logic        sign_selectedA,
    input  logic        sign_selectedB,
    input  logic [31:0] a,
    input  logic [31:0] b,

    output logic        msb_product,
    output logic [255:0] concat
);

    // sign / unsigned handling
    logic        msb_a, msb_b;
    logic [31:0] modified_a, modified_b;

    assign msb_a = a[31];
    assign msb_b = b[31];

    // take absolute value if sign is selected and msb is 1
    assign modified_a = (sign_selectedA & msb_a) ? (~a + 32'd1) : a;
    assign modified_b = (sign_selectedB & msb_b) ? (~b + 32'd1) : b;

    // sign of final product
    assign msb_product = (sign_selectedA & msb_a) ^ (sign_selectedB & msb_b);

    // split into 8-bit chunks
    logic [7:0] ag1, ag2, ag3, ag4;
    logic [7:0] bg1, bg2, bg3, bg4;

    assign ag1 = modified_a[7:0];
    assign ag2 = modified_a[15:8];
    assign ag3 = modified_a[23:16];
    assign ag4 = modified_a[31:24];

    assign bg1 = modified_b[7:0];
    assign bg2 = modified_b[15:8];
    assign bg3 = modified_b[23:16];
    assign bg4 = modified_b[31:24];

    // 16 partial 8x8 products (a_i * b_j)
    logic [15:0] product_8bit1,  product_8bit2,  product_8bit3,  product_8bit4;
    logic [15:0] product_8bit5,  product_8bit6,  product_8bit7,  product_8bit8;
    logic [15:0] product_8bit9,  product_8bit10, product_8bit11, product_8bit12;
    logic [15:0] product_8bit13, product_8bit14, product_8bit15, product_8bit16;

    wallace_8bit crisscross1  (.a(ag1), .b(bg1), .result(product_8bit1));
    wallace_8bit crisscross2  (.a(ag1), .b(bg2), .result(product_8bit2));
    wallace_8bit crisscross3  (.a(ag1), .b(bg3), .result(product_8bit3));
    wallace_8bit crisscross4  (.a(ag1), .b(bg4), .result(product_8bit4));
    wallace_8bit crisscross5  (.a(ag2), .b(bg1), .result(product_8bit5));
    wallace_8bit crisscross6  (.a(ag2), .b(bg2), .result(product_8bit6));
    wallace_8bit crisscross7  (.a(ag2), .b(bg3), .result(product_8bit7));
    wallace_8bit crisscross8  (.a(ag2), .b(bg4), .result(product_8bit8));
    wallace_8bit crisscross9  (.a(ag3), .b(bg1), .result(product_8bit9));
    wallace_8bit crisscross10 (.a(ag3), .b(bg2), .result(product_8bit10));
    wallace_8bit crisscross11 (.a(ag3), .b(bg3), .result(product_8bit11));
    wallace_8bit crisscross12 (.a(ag3), .b(bg4), .result(product_8bit12));
    wallace_8bit crisscross13 (.a(ag4), .b(bg1), .result(product_8bit13));
    wallace_8bit crisscross14 (.a(ag4), .b(bg2), .result(product_8bit14));
    wallace_8bit crisscross15 (.a(ag4), .b(bg3), .result(product_8bit15));
    wallace_8bit crisscross16 (.a(ag4), .b(bg4), .result(product_8bit16));

    // pack partial products; order must match stage 2
    assign concat = {
        product_8bit16, product_8bit15, product_8bit14, product_8bit13,
        product_8bit12, product_8bit11, product_8bit10, product_8bit9,
        product_8bit8,  product_8bit7,  product_8bit6,  product_8bit5,
        product_8bit4,  product_8bit3,  product_8bit2,  product_8bit1
    };

endmodule



module fs_wallace_256v2 (
    input  logic        msb_product_in,
    input  logic [255:0] concat_in,
    output logic [63:0] product   // full 64-bit signed product
);

    // unpack partial products (must match concat packing)
    logic [15:0] p1,  p2,  p3,  p4;
    logic [15:0] p5,  p6,  p7,  p8;
    logic [15:0] p9,  p10, p11, p12;
    logic [15:0] p13, p14, p15, p16;

    assign p1  = concat_in[ 15:  0];
    assign p2  = concat_in[ 31: 16];
    assign p3  = concat_in[ 47: 32];
    assign p4  = concat_in[ 63: 48];
    assign p5  = concat_in[ 79: 64];
    assign p6  = concat_in[ 95: 80];
    assign p7  = concat_in[111: 96];
    assign p8  = concat_in[127:112];
    assign p9  = concat_in[143:128];
    assign p10 = concat_in[159:144];
    assign p11 = concat_in[175:160];
    assign p12 = concat_in[191:176];
    assign p13 = concat_in[207:192];
    assign p14 = concat_in[223:208];
    assign p15 = concat_in[239:224];
    assign p16 = concat_in[255:240];

    // zero-extend & shift each 16-bit product into its 64-bit position
    // a = a0 + a1<<8 + a2<<16 + a3<<24
    // b = b0 + b1<<8 + b2<<16 + b3<<24
    // p(i,j) is shifted by 8*(i+j)
    logic [63:0] zext1,  zext2,  zext3,  zext4;
    logic [63:0] zext5,  zext6,  zext7,  zext8;
    logic [63:0] zext9,  zext10, zext11, zext12;
    logic [63:0] zext13, zext14, zext15, zext16;

    assign zext1  = {{48{1'b0}}, p1}  << 0;   // a0*b0
    assign zext2  = {{48{1'b0}}, p2}  << 8;   // a0*b1
    assign zext3  = {{48{1'b0}}, p3}  << 16;  // a0*b2
    assign zext4  = {{48{1'b0}}, p4}  << 24;  // a0*b3

    assign zext5  = {{48{1'b0}}, p5}  << 8;   // a1*b0
    assign zext6  = {{48{1'b0}}, p6}  << 16;  // a1*b1
    assign zext7  = {{48{1'b0}}, p7}  << 24;  // a1*b2
    assign zext8  = {{48{1'b0}}, p8}  << 32;  // a1*b3

    assign zext9  = {{48{1'b0}}, p9}  << 16;  // a2*b0
    assign zext10 = {{48{1'b0}}, p10} << 24;  // a2*b1
    assign zext11 = {{48{1'b0}}, p11} << 32;  // a2*b2
    assign zext12 = {{48{1'b0}}, p12} << 40;  // a2*b3

    assign zext13 = {{48{1'b0}}, p13} << 24;  // a3*b0
    assign zext14 = {{48{1'b0}}, p14} << 32;  // a3*b1
    assign zext15 = {{48{1'b0}}, p15} << 40;  // a3*b2
    assign zext16 = {{48{1'b0}}, p16} << 48;  // a3*b3

    // 64-bit adder tree
    logic cout_1,  cout_2,  cout_3,  cout_4;
    logic cout_5,  cout_6,  cout_7,  cout_8;
    logic cout_9,  cout_10, cout_11, cout_12;
    logic cout_13, cout_14, cout_15;

    logic [63:0] inter1, inter2, inter3, inter4;
    logic [63:0] inter5, inter6, inter7, inter8;
    logic [63:0] ro8_1,  ro8_2,  ro8_3,  ro8_4;
    logic [63:0] ro8_5,  ro8_6;
    logic [63:0] final_result;
    logic [63:0] signed_result;

    adder_64bit FA64_1  (.a(zext1),  .b(zext2),  .S(inter1), .Cout(cout_1));
    adder_64bit FA64_2  (.a(zext3),  .b(zext4),  .S(inter2), .Cout(cout_2));
    adder_64bit FA64_3  (.a(zext5),  .b(zext6),  .S(inter3), .Cout(cout_3));
    adder_64bit FA64_4  (.a(zext7),  .b(zext8),  .S(inter4), .Cout(cout_4));
    adder_64bit FA64_5  (.a(zext9),  .b(zext10), .S(inter5), .Cout(cout_5));
    adder_64bit FA64_6  (.a(zext11), .b(zext12), .S(inter6), .Cout(cout_6));
    adder_64bit FA64_7  (.a(zext13), .b(zext14), .S(inter7), .Cout(cout_7));
    adder_64bit FA64_8  (.a(zext15), .b(zext16), .S(inter8), .Cout(cout_8));

    adder_64bit FA64_9  (.a(inter1), .b(inter2), .S(ro8_1), .Cout(cout_9));
    adder_64bit FA64_10 (.a(inter3), .b(inter4), .S(ro8_2), .Cout(cout_10));
    adder_64bit FA64_11 (.a(inter5), .b(inter6), .S(ro8_3), .Cout(cout_11));
    adder_64bit FA64_12 (.a(inter7), .b(inter8), .S(ro8_4), .Cout(cout_12));

    adder_64bit FA64_13 (.a(ro8_1), .b(ro8_2), .S(ro8_5), .Cout(cout_13));
    adder_64bit FA64_14 (.a(ro8_3), .b(ro8_4), .S(ro8_6), .Cout(cout_14));
    adder_64bit FA64_15 (.a(ro8_5), .b(ro8_6), .S(final_result), .Cout(cout_15));

    // sign correction (two's complement) for signed result
    always_comb begin
        if (msb_product_in) begin
            signed_result = ~final_result + 64'd1;
        end else begin
            signed_result = final_result;
        end
    end

    assign product = signed_result;

endmodule

