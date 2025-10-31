/*
    2-Wide, OoO RV32IM CPU

    This module is the top level module that 
    encapsulates the processing logic and the 
    memory.

    By default, a simple memory model is 
    configured comprised of registers.
*/
import uarch_pkg::*;

module cpu #(parameter SIMPLE_MEM_MODE = 1) (input clk, rst);

    core core0 (
        .clk(clk),
        .rst(rst),
        // IMEM Ports
        .icache_addr(icache_addr),
        .icache_re(icache_re),
        .icache_dout(icache_dout),
        .icache_dout_val(icache_dout_val),
        .icache_stall(icache_stall),
        // DMEM Ports
        .dcache_addr(dcache_addr),
        .dcache_re(dcache_re),
        .dcache_dout(dcache_dout),
        .dcache_dout_val(dcache_dout_val),
        .dcache_stall(dcache_stall),
        // DMEM Write Ports
        .dcache_din(dcache_din),
        .dcache_we(dcache_we)
    );

    generate
        if (SIMPLE_MEM_MODE) begin
            mem_simple mem (
                .clk(clk),
                .rst(rst),
                // IMEM Ports
                .icache_addr(icache_addr),
                .icache_re(icache_re),
                .icache_dout(icache_dout),
                .icache_dout_val(icache_dout_val),
                .icache_stall(icache_stall),
                // DMEM Ports
                .dcache_addr(dcache_addr),
                .dcache_re(dcache_re),
                .dcache_dout(dcache_dout),
                .dcache_dout_val(dcache_dout_val),
                .dcache_stall(dcache_stall),
                // DMEM Write Ports
                .dcache_din(dcache_din),
                .dcache_we(dcache_we)
            );
        end else begin
            // TODO: Cache System Goes Here
        end
    endgenerate

endmodule