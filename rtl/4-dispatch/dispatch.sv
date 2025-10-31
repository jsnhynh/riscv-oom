/*
    Dispatch Stage

    This module is purely combinational that routes renamed instructions 
    from the Rename stage's output register to the correct backend issue 
    queue (ALU_RS, MDU_RS, LSQ)

    Its also generates the initial entry for the Reorder Buffer at the 
    same time, beginning the tracking of the instruction for retirement.

    Assumes backend queues have dual write ports
    Assumes compaction logic from Rename
    Handles resource hazards and stalls Rename if resources are 
    unavailable.
*/
import riscv_isa_pkg::*;
import uarch_pkg::*;

module dispatch (
    // Ports from Rename
    output logic dispatch_rdy,
    input  renamed_inst_t renamed_inst0, renamed_inst1,

    // Ports to RS
    input  logic [1:0]      alu_rs_rdy,
    input  logic [1:0]      mdu_rs_rdy,
    input  logic [1:0]      lsq_rs_rdy,

    output logic [1:0]      alu_rs_we,
    output logic [1:0]      mdu_rs_we,
    output logic [1:0]      lsq_rs_we,

    output renamed_inst_t   alu_rs_entry0, alu_rs_entry1,
    output renamed_inst_t   mdu_rs_entry0, mdu_rs_entry1,
    output renamed_inst_t   lsq_rs_entry0, lsq_rs_entry1,

    // Ports to ROB
    input  logic [1:0]      rob_rdy, // 00: 0 rdy, 01: 1 rdy, 10/11: 2+ rdy
    output logic [1:0]      rob_we,
    output rob_entry_t      rob_entry0, rob_entry1
);

    //-------------------------------------------------------------
    // Internal Logic
    //-------------------------------------------------------------
    logic is_alu0, is_mdu0, is_lsq0;
    logic is_alu1, is_mdu1, is_lsq1;
    logic can_dispatch0, can_dispatch1;

    // -- Step 1: Determine the target queue for each instruction --
    assign is_alu0 = renamed_inst0.is_valid && !is_mdu0 && !is_lsq0;
    assign is_lsq0 = renamed_inst0.is_valid && renamed_inst0.is_load || renamed_inst0.is_store;
    assign is_mdu0 = renamed_inst0.is_valid && renamed_inst0.is_muldiv;

    assign is_alu1 = renamed_inst1.is_valid && !is_mdu1 && !is_lsq1;
    assign is_lsq1 = renamed_inst1.is_valid && renamed_inst1.is_load || renamed_inst1.is_store;
    assign is_mdu1 = renamed_inst1.is_valid && renamed_inst1.is_muldiv;

    // -- Step 2: Determine if inst 0 can be dispatched -- 
    assign can_dispatch0 =  rob_rdy[0] && (
                            (is_alu0 && alu_rs_rdy[0]) || 
                            (is_mdu0 && mdu_rs_rdy[0]) || 
                            (is_lsq0 && lsq_rs_rdy[0]));

    // -- Step 3: Determine if inst 1 can be dispatched --
    logic rob_avail_for_inst1 = (can_dispatch0)? rob_rdy[1] : rob_rdy[0];
    logic rs_avail_for_inst1;
    always_comb begin
        rs_avail_for_inst1 = 1'b0;
        if (is_alu1) begin
            rs_avail_for_inst1 = (is_alu0 && can_dispatch0)? alu_rs_rdy[1] : alu_rs_rdy[0];
        end else if (is_lsq1) begin
            rs_avail_for_inst1 = (is_lsq0 && can_dispatch0)? lsq_rs_rdy[1] : lsq_rs_rdy[0];
        end else if (is_mdu1) begin
            rs_avail_for_inst1 = (is_mdu0 && can_dispatch0)? mdu_rs_rdy[1] : mdu_rs_rdy[0];
        end
    end
    assign can_dispatch1 = rob_avail_for_inst1 && rs_avail_for_inst1;

    // -- Step 4: Generate Handshake and Write Enable Signals --
    // Ready to accept from rename if can dispatch first valid instruction or if no valid inst is coming
    assign dispatch_rdy = (!renamed_inst0.is_valid || can_dispatch0) && (!renamed_inst1.is_valid || can_dispatch1);

    assign alu_rs_we    = {can_dispatch1 && is_alu1, can_dispatch0 && is_alu0};
    assign lsq_we       = {can_dispatch1 && is_lsq1, can_dispatch0 && is_lsq0};
    assign mdu_rs_we    = {can_dispatch1 && is_mdu1, can_dispatch0 && is_mdu0};
    assign rob_we       = {can_dispatch1, can_dispatch0};

    // -- Step 5: Assign Data to Output Ports --
    assign alu_rs_entry0 = renamed_inst0;
    assign alu_rs_entry1 = renamed_inst1;
    assign lsq_entry0    = renamed_inst0;
    assign lsq_entry1    = renamed_inst1;
    assign mdu_rs_entry0 = renamed_inst0;
    assign mdu_rs_entry1 = renamed_inst1;

    // ROB Entry Generation Function
    function automatic rob_entry_t gen_rob_entry (input renamed_inst_t r_inst);
        rob_entry_t entry;
        entry = '{default:'0};
        entry.is_valid  = r_inst.is_valid;
        entry.is_ready  = 1'b0;
        entry.pc        = inst.pc;
        entry.rd        = inst.rd;
        entry.has_rd    = inst.has_rd;
        // Result is undetermined
        entry.has_exception = 1'b0;
        entry.is_branch     = inst.is_branch;
        entry.is_jump       = inst.is_jump;
        entry.is_store      = inst.is_store;
        return entry;
    endfunction

    assign rob_entry0 = gen_rob_entry(renamed_inst0);
    assign rob_entry1 = gen_rob_entry(renamed_inst1);
endmodule