/*
    Dispatch Stage

    This module is purely combinational that routes renamed instructions 
    from the Rename stage's output register to the correct backend issue 
    queue (ALU_RS, MDU_RS, LSQ)

    It handles resource hazards by prioritizing instruction 0 over 
    instruction 1 and stalling the Rename stage if resources are not 
    available.
*/

import uarch_pkg::*;

module dispatch (
    // Ports from Rename
    input  renamed_inst_t renamed_inst0, renamed_inst1;
    output logic dispatch_rdy,

    // Ready from RS
    input  logic [1:0] alu_rs_rdy, // 00: 0 rdy, 01: 1 rdy, 10/11: 2+ rdy
    input  logic [1:0] mdu_rs_rdy,
    input  logic [1:0] lsq_rdy,
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

    //-------------------------------------------------------------
    // Internal Logic
    //-------------------------------------------------------------
    logic is_alu0, is_mdu0, is_lsq0;
    logic is_alu1, is_mdu1, is_lsq1;
    logic can_dispatch0, can_dispatch1;

    // -- Step 1: Determine the target queue for each instruction --
    assign is_alu0 = renamed_inst0.is_valid && !is_mdu0 && !is_lsq0;
    assign is_mdu0 = renamed_inst0.is_valid && renamed_inst0.is_muldiv;
    assign is_lsq0 = renamed_inst0.is_valid && renamed_inst0.is_load || renamed_inst0.is_store;

    assign is_alu1 = renamed_inst1.is_valid && !is_mdu1 && !is_lsq1;
    assign is_mdu1 = renamed_inst1.is_valid && renamed_inst1.is_muldiv;
    assign is_lsq1 = renamed_inst1.is_valid && renamed_inst1.is_load || renamed_inst1.is_store;

    // -- Step 2: Determine if inst 0 can be dispatched -- 
    assign can_dispatch0 =  (is_alu0 && alu_rs_rdy[0]) || 
                            (is_mdu0 && mdu_rs_rdy[0]) || 
                            (is_lsq0 && lsq_rdy[0]);


    // CASES
    // Both ALU
    always_comb begin
        casez ({})
            : 
            default: 
        endcase
    end

    

    // -- Step 3: Determine if inst 1 can be dispatched --

    // -- Step 4: Generate Handshake and Write Enable Signals --

    // -- Step 5: Assign Data to Output Ports --

endmodule