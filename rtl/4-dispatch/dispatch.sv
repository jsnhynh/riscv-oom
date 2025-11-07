/*
 * Dispatch Stage
 *
 * This module is a purely combinational "switchyard" that routes renamed
 * instructions from the Rename stage to the correct backend issue queue
 * (ALU_RS, MDU_RS, or LSQ_RS).
 *
 * It has two parallel jobs:
 * 1. Arbitration: Checks for available slots in the issue queues.
 * 2. ROB Write: Writes the initial metadata (pc, rd, etc.) for each
 *               instruction into the Reorder Buffer.
 * It provides the final backpressure signal to the Rename stage.
 */

import riscv_isa_pkg::*;
import uarch_pkg::*;

module dispatch (
    // Ports from Rename
    output logic                    dispatch_rdy,
    input  instruction_t            renamed_insts   [PIPE_WIDTH-1:0],

    // Ports to RS
    input  logic [PIPE_WIDTH-1:0]   alu_rs_rdy,
    input  logic [PIPE_WIDTH-1:0]   mdu_rs_rdy,
    input  logic [PIPE_WIDTH-1:0]   lsq_rs_rdy,

    output logic [PIPE_WIDTH-1:0]   alu_rs_we,
    output logic [PIPE_WIDTH-1:0]   mdu_rs_we,
    output logic [PIPE_WIDTH-1:0]   lsq_rs_we,

    output instruction_t            alu_rs_entries  [PIPE_WIDTH-1:0],
    output instruction_t            mdu_rs_entries  [PIPE_WIDTH-1:0],
    output instruction_t            lsq_rs_entries  [PIPE_WIDTH-1:0],

    // Ports to ROB
    input  logic [PIPE_WIDTH-1:0]   rob_rdy, // 00: 0 rdy, 01: 1 rdy, 10/11: 2+ rdy
    output logic [PIPE_WIDTH-1:0]   rob_we,
    output rob_entry_t              rob_entries     [PIPE_WIDTH-1:0]
);

    //-------------------------------------------------------------
    // Internal Logic
    //-------------------------------------------------------------
    logic [PIPE_WIDTH-1:0] is_alu;
    logic [PIPE_WIDTH-1:0] is_lsq;
    logic [PIPE_WIDTH-1:0] is_mdu;
    logic [PIPE_WIDTH-1:0] can_dispatch ;

    // -- Step 1: Determine the target queue for each instruction --
    assign is_alu[0] = renamed_insts[0].is_valid && !is_mdu[0] && !is_lsq[0];
    assign is_lsq[0] = renamed_insts[0].is_valid && ((renamed_insts[0].opcode == OPC_LOAD) || (renamed_insts[0].opcode == OPC_STORE));
    assign is_mdu[0] = renamed_insts[0].is_valid && ((renamed_insts[0].opcode == OPC_ARI_RTYPE) && (renamed_insts[0].funct7 == FNC7_MULDIV));

    assign is_alu[1] = renamed_insts[1].is_valid && !is_mdu[1] && !is_lsq[1];
    assign is_lsq[1] = renamed_insts[1].is_valid && ((renamed_insts[1].opcode == OPC_LOAD) || (renamed_insts[1].opcode == OPC_STORE));
    assign is_mdu[1] = renamed_insts[1].is_valid && ((renamed_insts[1].opcode == OPC_ARI_RTYPE) && (renamed_insts[1].funct7 == FNC7_MULDIV));

    // -- Step 2: Determine if inst 0 can be dispatched -- 
    assign can_dispatch[0] =  rob_rdy[0] && (
                                (is_alu[0] && alu_rs_rdy[0]) || 
                                (is_mdu[0] && mdu_rs_rdy[0]) || 
                                (is_lsq[0] && lsq_rs_rdy[0]));

    // -- Step 3: Determine if inst 1 can be dispatched --
    logic rob_avail_for_inst1 = (can_dispatch[0])? rob_rdy[1] : rob_rdy[0];
    logic rs_avail_for_inst1;
    always_comb begin
        rs_avail_for_inst1 = 1'b0;
        if (is_alu[1]) begin
            rs_avail_for_inst1 = (is_alu[0] && can_dispatch[0])? alu_rs_rdy[1] : alu_rs_rdy[0];
        end else if (is_lsq[1]) begin
            rs_avail_for_inst1 = (is_lsq[0] && can_dispatch[0])? lsq_rs_rdy[1] : lsq_rs_rdy[0];
        end else if (is_mdu[1]) begin
            rs_avail_for_inst1 = (is_mdu[0] && can_dispatch[0])? mdu_rs_rdy[1] : mdu_rs_rdy[0];
        end
    end
    assign can_dispatch[1] = rob_avail_for_inst1 && rs_avail_for_inst1;

    // -- Step 4: Generate Handshake and Write Enable Signals --
    // Ready to accept from rename if I can dispatch exactly both
    assign dispatch_rdy = (!renamed_insts[0].is_valid || can_dispatch[0]) && (!renamed_insts[1].is_valid || can_dispatch[1]);

    assign alu_rs_we    = {dispatch_rdy && can_dispatch[1] && is_alu[1], dispatch_rdy && can_dispatch[0] && is_alu[0]};
    assign lsq_we       = {dispatch_rdy && can_dispatch[1] && is_lsq[1], dispatch_rdy && can_dispatch[0] && is_lsq[0]};
    assign mdu_rs_we    = {dispatch_rdy && can_dispatch[1] && is_mdu[1], dispatch_rdy && can_dispatch[0] && is_mdu[0]};
    assign rob_we       = {dispatch_rdy && can_dispatch[1], dispatch_rdy && can_dispatch[0]};

    // -- Step 5: Assign Data to Output Ports --
    assign alu_rs_entries[0] = renamed_insts[0];
    assign alu_rs_entries[1] = renamed_insts[1];
    assign lsq_rs_entries[0] = renamed_insts[0];
    assign lsq_rs_entries[1] = renamed_insts[1];
    assign mdu_rs_entries[0] = renamed_insts[0];
    assign mdu_rs_entries[1] = renamed_insts[1];

    // ROB Entry Generation Function
    function automatic rob_entry_t gen_rob_entry (input instruction_t r_inst);
        rob_entry_t entry;
        entry = '{default:'0};
        entry.is_valid  = r_inst.is_valid;
        entry.is_ready  = 1'b0;
        entry.pc        = r_inst.pc;
        entry.rd        = r_inst.rd;
        entry.has_rd    = r_inst.has_rd;
        // Result is undetermined
        entry.has_exception = 1'b0;
        entry.opcode    = r_inst.opcode;
        return entry;
    endfunction

    assign rob_entries[0] = gen_rob_entry(renamed_insts[0]);
    assign rob_entries[1] = gen_rob_entry(renamed_insts[1]);
endmodule