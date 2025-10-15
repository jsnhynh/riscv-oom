module inst_buffer #(
  parameter DEPTH = 4,
)(
  // Module I/O
  input logic clk, rst, flush, cache_stall,

  // Port from ICache
  input  logic [`CPU_ADDR_BITS-1:0]   pc,
  input  logic [2*`CPU_INST_BITS-1:0] icache_dout,
  input  logic                        icache_dout_val,
  output logic                        inst_buffer_rdy,

  // Port to Decoder
  input  logic decoder_rdy,
  output logic [`CPU_ADDR_BITS-1:0] pc, pc_4,
  output logic [`CPU_INST_BITS-1:0] inst0, inst1,
  output logic                      inst_val
);
  logic [$clog2(DEPTH)-1:0] read_ptr, write_ptr;
  logic is_full, is_empty;

  logic [`CPU_ADDR_BITS-1:0]    pc_regs         [DEPTH-1:0];
  logic [2*`CPU_INST_BITS-1:0]  inst_packet_reg [DEPTH-1:0];

  logic do_write = icache_dout_val && ~is_full;
  logic do_read  = decoder_rdy && ~is_empty;

  always_ff @(posedge clk) begin
    if (rst || flush) begin
      read_ptr  <= 'd0;
      write_ptr <= 'd0;
    end else if (~cache_stall)begin
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
  assign inst_val         = ~is_empty;

  // Read
  logic [2*`CPU_INST_BITS-1:0] read_packet = inst_packet_reg[read_ptr];
  assign inst0  = read_packet[`CPU_INST_BITS-1:0];
  assign inst1  = read_packet[2*`CPU_INST_BITS-1:`CPU_INST_BITS];
  assign pc     = pc_regs[read_ptr];
  assign pc_4   = pc_regs[read_ptr] + 4;
endmodule
