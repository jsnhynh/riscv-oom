import uarch_pkg::*;

module rob (
    // Module I/O
    input  logic clk, rst, flush, cache_stall,
    output logic rob_rdy,

    // Ports from Decoder
    input  decoded_inst_t       decode_inst0,           decode_inst1,
    input  logic                decode_val,

    // Ports to Rename
    output rat_write_port_t     rat_0_write_port,       rat_1_write_port,
    output commit_write_port_t  commit_0_write_port,    commit_1_write_port,

    // Ports to Dispatch (Diagram is for both ways, can reduce to older instruction as tag should already be in RAT, this is for then inst1 is dependent on inst0 which's rob_id isnt in RAT yet.)
    output logic [TAG_WIDTH-1:0]        rs1_id,     rs2_id;
    output logic                        rs1_id_val, rs2_id_val;

    // Ports from CDB
    input writeback_packet_t            cdb_port0, cdb_port1,

    // Ports to LSQ
    output logic [TAG_WIDTH-1:0]        store_id, 
    output logic                        store_val,

    // ROB Pointers for calculating instruction age
    output logic [`clog2(ENTRIES)-1:0]  rob_head, rob_tail
);

endmodule