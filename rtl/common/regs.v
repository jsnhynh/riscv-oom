`timescale 1ns/1ps

// Register of D-Type Flip-flops
module REGISTER(q, d, clk);
  parameter N = 1;
  output reg [N-1:0] q;
  input [N-1:0]      d;
  input         clk;
  always @(posedge clk)
    q <= d;
endmodule // REGISTER

// Register with clock enable
module REGISTER_CE(q, d, ce, clk);
  parameter N = 1;
  output reg [N-1:0] q;
  input [N-1:0]      d;
  input          ce, clk;
  always @(posedge clk)
    if (ce) q <= d;
endmodule // REGISTER_CE

// Register with reset value
module REGISTER_R(q, d, rst, clk);
  parameter N = 1;
  parameter INIT = {N{1'b0}};
  output reg [N-1:0] q;
  input [N-1:0]      d;
  input          rst, clk;
  always @(posedge clk)
    if (rst) q <= INIT;
    else q <= d;
endmodule // REGISTER_R

// Register with reset and clock enable
//  Reset works independently of clock enable
module REGISTER_R_CE(q, d, rst, ce, clk);
  parameter N = 1;
  parameter INIT = {N{1'b0}};
  output reg [N-1:0] q;
  input [N-1:0]      d;
  input          rst, ce, clk;
  always @(posedge clk)
    if (rst) q <= INIT;
    else if (ce) q <= d;
endmodule // REGISTER_R_CE

/*
  Asynchronous 2 reads ports
  Synchronous  1 write port
*/
module regfile #( parameter DEPTH = 32, parameter WIDTH = 32 ) (
  input clk,
  input rst, 
  input we,
  // Read port 1
  input [$clog2(DEPTH)-1:0] raddr1,
  output [WIDTH-1:0] rs1,
  // Read port 2
  input [$clog2(DEPTH)-1:0] raddr2,
  output [WIDTH-1:0] rs2,
  // Write port 1
  input [$clog2(DEPTH)-1:0] waddr,
  input [WIDTH-1:0] rd
);

  genvar i;
  reg [WIDTH-1:0] reg_d [DEPTH-1:0]; // din
  wire [WIDTH-1:0] reg_q [DEPTH-1:0]; // dout

  // Register file
  generate
    for (i = 0; i < DEPTH; i = i + 1) begin
      REGISTER #(.N(WIDTH)) reg_x (.clk(clk), .d(reg_d[i]), .q(reg_q[i]));

      // Write
      always @(*) begin 
        if (rst == 1'b1) begin
          reg_d[i] = {WIDTH{1'b0}};
        end else begin
          if ((we == 1'b1) && (i == waddr) && (waddr != 0)) begin
            reg_d[waddr] = rd;
          end else begin
            reg_d[i] = reg_q[i];
          end
        end
      end
    end
  endgenerate

  // Read
  assign rs1 = reg_q[raddr1];
  assign rs2 = reg_q[raddr2];

endmodule