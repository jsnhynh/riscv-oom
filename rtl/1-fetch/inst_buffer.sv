/*
 * Instruction Buffer (FIFO Queue)
 *
 * This module acts as a decoupling buffer between the Fetch and Decode stages.
 * It is implemented as a circular FIFO to help hide I-Cache read latency
 * and to smooth the instruction stream, preventing pipeline stalls from
 * propagating upstream to the PC generation logic.
 */

import riscv_isa_pkg::*;
import uarch_pkg::*;

module inst_buffer (
  // Module I/O
  input logic clk, rst, flush,

  // Port from ICache
  input  logic [CPU_ADDR_BITS-1:0]      pc,
  input  logic [FETCH_WIDTH*CPU_INST_BITS-1:0]  icache_dout,
  input  logic                          icache_dout_val,
  output logic                          inst_buffer_rdy,

  // Port to Decoder
  input  logic decoder_rdy,
  output logic [CPU_ADDR_BITS-1:0]      inst_pcs        [PIPE_WIDTH-1:0],
  output logic [CPU_INST_BITS-1:0]      insts           [PIPE_WIDTH-1:0],
  output logic                          fetch_val
);
  logic [$clog2(INST_BUFFER_DEPTH)-1:0] read_ptr, write_ptr;
  logic is_full, is_empty;

  logic [CPU_ADDR_BITS-1:0]             pc_regs         [INST_BUFFER_DEPTH-1:0];
  logic [FETCH_WIDTH*CPU_INST_BITS-1:0] inst_packet_reg [INST_BUFFER_DEPTH-1:0];

  logic do_write, do_read;
  assign do_write = icache_dout_val && inst_buffer_rdy && ~flush;
  assign do_read  = decoder_rdy && ~is_empty && ~flush;

  always_ff @(posedge clk or posedge rst or posedge flush) begin
    if (rst || flush) begin
      read_ptr  <= '0;
      write_ptr <= '0;
      pc_regs <= '{default:'0};
      inst_packet_reg <= '{default:'0};
    end else begin
      if (do_write) begin // Write
        inst_packet_reg[write_ptr]  <= icache_dout;
        pc_regs[write_ptr]          <= pc;
        write_ptr                   <= write_ptr + 1;
      end 

      if (do_read) begin
        read_ptr <= read_ptr + 1;
      end
    end
  end

  assign is_full  = (write_ptr + 1) == read_ptr;
  assign is_empty = (read_ptr == write_ptr);

  assign inst_buffer_rdy  = ~is_full;
  assign fetch_val         = ~is_empty && ~rst && ~flush && decoder_rdy;

  // Read
  logic [2*CPU_INST_BITS-1:0] read_packet;
  assign read_packet = inst_packet_reg[read_ptr];
  assign insts[0]    = (fetch_val)? read_packet[CPU_INST_BITS-1:0] : '0;
  assign insts[1]    = (fetch_val)? read_packet[FETCH_WIDTH*CPU_INST_BITS-1:CPU_INST_BITS] : '0;
  assign inst_pcs[0] = (fetch_val)? pc_regs[read_ptr] : '0;
  assign inst_pcs[1] = (fetch_val)? pc_regs[read_ptr] + 4 : '0;
endmodule
