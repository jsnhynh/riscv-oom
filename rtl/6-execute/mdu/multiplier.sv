module fs_wallace_2stage_mul64 (
    input  logic        clk,
    input  logic        rst,
    input logic         flush,

    input  logic        valid_in,
    input  logic        sign_selectedA,
    input  logic        sign_selectedB,
    input  logic [31:0] a,
    input  logic [31:0] b,

    output logic        valid_out,
    output logic [63:0] product
);

    // -------------------------------
    // Stage 1: combinational
    // -------------------------------
    logic        msb_product_s1;
    logic [255:0] concat_s1;


    fs_wallace_256v1 u_stage1 (
        .sign_selectedA (sign_selectedA),
        .sign_selectedB (sign_selectedB),
        .a              (a),
        .b              (b),
        .msb_product    (msb_product_s1),
        .concat         (concat_s1)
    );

    // -------------------------------
    // Pipeline registers (stage1 -> stage2)
    // -------------------------------
    logic        msb_product_reg;
    logic [255:0] concat_reg;

    logic        valid_s1;   // valid for stage2 inputs
    logic        valid_s2;   // valid for output register

    always_ff @(posedge clk ) begin
        if (rst || flush) begin
            msb_product_reg <= 1'b0;
            concat_reg      <= '0;
            valid_s1        <= 1'b0;
            valid_s2        <= 1'b0;
        end else begin
            // valid pipeline
            valid_s1 <= valid_in;
            valid_s2 <= valid_s1;

            // capture stage1 output when input is valid
            if (valid_in) begin
                msb_product_reg <= msb_product_s1;
                concat_reg      <= concat_s1;
            end
        end
    end

    // -------------------------------
    // Stage 2: combinational (64-bit product)
    // -------------------------------
    logic [63:0] product_comb;

    fs_wallace_256v2 u_stage2 (
        .msb_product_in (msb_product_reg),
        .concat_in      (concat_reg),
        .product        (product_comb)   // 64-bit from stage2
    );

    // -------------------------------
    // Output register
    // -------------------------------
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            product   <= '0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_s2;
            if (valid_s1) begin
                product <= product_comb;
            end
        end
    end

endmodule
