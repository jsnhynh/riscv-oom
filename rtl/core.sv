module core(
  input clk, rst,

  // IMEM Ports
  output [`CPU_ADDR_BITS-1:0] icache_addr,
  input [2*`CPU_DATA_BITS-1:0] icache_dout,
  input icache_dout_val,
  output icache_re,

  // DMEM Ports
  output [`CPU_ADDR_BITS-1:0] dcache_addr,
  input [`CPU_DATA_BITS:0] dcache_dout,
  input dcache_dout_val,
  output dcache_re,
  output [`CPU_DATA_BITS:0] dcache_din,
  output [3:0]  dcache_we,

  input cache_stall
);

  fetch fetch_stage (
    .clk(clk),
    .rst(rst),
    .flush(flush),
    .cache_stall(cache_stall),

    .pc_sel(pc_sel),
    .rob_pc(rob_pc),

    .icache_addr(icache_addr),
    .icache_dout(icache_dout),
    .icache_dout_val(icache_dout_val),
    .icache_re(icache_re),

    .decoder_rdy(decoder_rdy),
    .inst0_pc(inst0_pc),
    .inst1_pc(inst1_pc),
    .inst0(inst0),
    .inst1(inst1),
    .inst_val(inst_val)
  );

  decode decode_stage ();

  prf rename_stage (
    .clk(clk),
    .rst(rst),
    .flush(flush),
    .cache_stall(cache_stall),

    .rs1_0(rs1_0),
    .rs2_0(rs2_0),
    .rs1_0_read_port(rs1_0_read_port),
    .rs2_0_read_port(rs2_0_read_port),

    .rs1_1(rs1_1),
    .rs2_1(rs2_1),
    .rs1_1_read_port(rs1_1_read_port),
    .rs2_1_read_port(rs2_1_read_port),

    .rat_0_write_port(rat_0_write_port),
    .rat_1_write_port(rat_1_write_port),

    .commit_0_write_port(commit_0_write_port),
    .commit_1_write_port(commit_1_write_port)
  );


endmodule