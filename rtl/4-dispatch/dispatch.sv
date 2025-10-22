import uarch_pkg::*;

module dispatch (
    input logic clk, rst, flush, cache_stall,

    // Ports from Rename
    input  renamed_inst_t renamed_inst0, renamed_inst1;
    output logic dispatch_rdy,

    // Ready from RS
    input  logic alu_rs_rdy,
    input  logic mdu_rs_rdy,
    input  logic lsq_rdy,
    input  logic [1:0] rob_rdy,

    // Write Ports to RS
    // to alu rs
    output logic [1:0] alu_rs_we,
    output renamed_inst_t alu_rs_entry0, alu_rs_entry1,
    // to mdu rs
    output logic [1:0] mdu_rs_we,
    output renamed_inst_t mdu_rs_entry0, mdu_rs_entry1,
    // to lsq
    output logic [1:0] lsq_rs_we,
    output renamed_inst_t lsq_rs_entry0, lsq_rs_entry1,
);

endmodule