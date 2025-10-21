import uarch_pkg::*;

module rename (
    input logic clk, rst, flush, cache_stall,

    // Ports from Decode
    output logic rename_rdy,
    input  decoded_inst_t decode_inst0, decode_inst1,
    input  logic decode_val,

    // ROB Ports
    input  rat_write_port_t     rat_0_write_port,       rat_1_write_port,
    input  commit_write_port_t  commit_0_write_port,    commit_1_write_port,
    input  logic rob_rdy,

    // Ports to Dispatch

);

endmodule