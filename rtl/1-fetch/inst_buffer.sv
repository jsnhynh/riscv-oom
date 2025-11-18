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

  // Port from imem
  input  logic [CPU_ADDR_BITS-1:0]      pc,
  input  logic [FETCH_WIDTH*CPU_INST_BITS-1:0]  imem_rec_packet,
  input  logic                          imem_rec_val,
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

  // Holding registers for when decoder stalls
  logic [CPU_ADDR_BITS-1:0]             inst_pcs_hold;
  logic [FETCH_WIDTH*CPU_INST_BITS-1:0] insts_hold;
  logic                                 holding_valid;

  logic do_write, do_read;
  assign do_write = imem_rec_val && inst_buffer_rdy && ~flush;
  assign do_read  = decoder_rdy && ~is_empty && ~flush;

  always_ff @(posedge clk or posedge rst or posedge flush) begin
    if (rst || flush) begin
      read_ptr  <= '0;
      write_ptr <= '0;
      pc_regs <= '{default:'0};
      inst_packet_reg <= '{default:'0};
    end else begin
      if (do_write) begin // Write
        inst_packet_reg[write_ptr]  <= imem_rec_packet;
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

  // Combinational read from buffer
  logic [2*CPU_INST_BITS-1:0] read_packet;
  logic [CPU_ADDR_BITS-1:0]   read_pc;
  assign read_packet = inst_packet_reg[read_ptr];
  assign read_pc     = pc_regs[read_ptr];

  // Holding register for decoder stalls
  // Capture output when we have valid data but decoder is not ready
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      insts_hold      <= '0;
      inst_pcs_hold   <= '0;
      holding_valid   <= 1'b0;
    end else if (flush) begin
      holding_valid   <= 1'b0;
    end else if (!decoder_rdy && !is_empty && !holding_valid) begin
      // Decoder stalled and we have data but haven't captured it yet
      insts_hold      <= read_packet;
      inst_pcs_hold   <= read_pc;
      holding_valid   <= 1'b1;
    end else if (decoder_rdy && holding_valid) begin
      // Decoder ready again, release the hold
      holding_valid   <= 1'b0;
    end
  end
  
  // Output mux: use holding registers if valid, otherwise direct from buffer
  always_comb begin
    if (holding_valid) begin
      // Use held values during stall
      insts[0]    = insts_hold[CPU_INST_BITS-1:0];
      insts[1]    = insts_hold[FETCH_WIDTH*CPU_INST_BITS-1:CPU_INST_BITS];
      inst_pcs[0] = inst_pcs_hold;
      inst_pcs[1] = inst_pcs_hold+4;
      fetch_val   = 1'b1;
    end else if (!is_empty && !flush) begin
      // Normal operation: combinational read from buffer
      insts[0]    = read_packet[CPU_INST_BITS-1:0];
      insts[1]    = read_packet[FETCH_WIDTH*CPU_INST_BITS-1:CPU_INST_BITS];
      inst_pcs[0] = read_pc;
      inst_pcs[1] = read_pc + 4;
      fetch_val   = 1'b1;
    end else begin
      // Empty or flushed
      insts       = '{default:'0};
      inst_pcs    = '{default:'0};
      fetch_val   = 1'b0;
    end
  end

endmodule