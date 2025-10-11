module core(
  input clk, rst,

  // IMEM Ports
  output [`CPU_ADDR_BITS-1:0] icacche_addr,
  input [`CPU_DATA_BITS*2-1:0] icache_dout,
  output icache_re,

  // DMEM Ports
  output [`CPU_ADDR_BITS-1:0] dcache_addr,
  input [`CPU_DATA_BITS:0] dcache_dout,
  output dcache_re,
  output [`CPU_DATA_BITS:0] dcache_din,
  output [3:0]  dcache_we,

  input cache_stall
);



endmodule