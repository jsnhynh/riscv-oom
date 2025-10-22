import uarch_pkg::*;

module rename (
    input logic clk, rst, flush, cache_stall,

    // Ports from Decode
    output logic                    rename_rdy,
    input  decoded_inst_t           decode_inst0,           decode_inst1,

    // Ports to Dispatch
    output renamed_inst_t           renamed_inst0,          renamed_inst1,
    output logic rename_val,
    input  logic dispatch_rdy,

    // Ports to/from ROB
    output logic [1:0]              rob_alloc_req,
    input  logic [1:0]              rob_alloc_gnt,
    input  logic [TAG_WIDTH-1:0]    rob_tag0,               rob_tag1,
    input  commit_write_port_t      commit_0_write_port,    commit_1_write_port
);
    //-------------------------------------------------------------
    // Internal Wires and Connections
    //-------------------------------------------------------------
    prf_read_port_t rs1_0_read_port, rs1_1_read_port;
    prf_read_port_t rs2_0_read_port, rs2_1_read_port;
    prf_rat_write_port_t rat_0_write_port, rat_1_write_port;


    prf prf_inst (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .cache_stall(cache_stall),

        .rs1_0(decode_inst0.rs1),                   .rs1_1(decode_inst1.rs1),
        .rs2_0(decode_inst0.rs2),                   .rs2_1(decode_inst1.rs2),
        .rs1_0_read_port(rs1_0_read_port),          .rs1_1_read_port(rs1_1_read_port),
        .rs2_0_read_port(rs2_0_read_port),          .rs2_1_read_port(rs2_1_read_port),

        .rat_0_write_port(rat_0_write_port),        .rat_1_write_port(rat_1_write_port),
        
        .commit_0_write_port(commit_0_write_port),  .commit_1_write_port(commit_1_write_port)
    );

    //-------------------------------------------------------------
    // Renaming Function
    //-------------------------------------------------------------
    function automatic renamed_inst_t rename_inst (
        input decoded_inst_t d_inst,
        input prf_read_port_t rs1_port,
        input prf_read_port_t rs2_port,
        input logic [TAG_WIDTH-1:0] new_tag,
        input logic                 can_rename_flag
    );
        renamed_inst_t r_inst;
        r_inst = `(default:`0);
        r_inst.is_valid = can_rename_flag;

        // Pass-through fields from decode
        r_inst.pc         = d_inst.pc;
        r_inst.imm        = d_inst.imm;
        r_inst.has_rd     = d_inst.has_rd;
        r_inst.is_jump    = d_inst.is_jump;
        r_inst.is_load    = d_inst.is_load;
        r_inst.is_store   = d_inst.is_store;
        r_inst.is_branch  = d_inst.is_branch;
        r_inst.is_muldiv  = d_inst.is_muldiv;
        r_inst.alu_a_sel  = d_inst.alu_a_sel;
        r_inst.alu_b_sel  = d_inst.alu_b_sel;
        r_inst.uop        = d_inst.uop;
        r_inst.uop_br     = d_inst.uop_br;

        // New Fields added by rename
        r_inst.dest_tag  = new_tag;
        r_inst.rs1_renamed = rs1_port.renamed;
        r_inst.rs1_tag   = rs1_port.tag;
        r_inst.rs1_data  = rs1_port.data;
        r_inst.rs2_renamed = rs2_port.renamed;
        r_inst.rs2_tag   = rs2_port.tag;
        r_inst.rs2_data  = rs2_port.data;

        return r_inst;
    endfunction

    //-------------------------------------------------------------
    // Conbinational Renaming Logic
    //-------------------------------------------------------------
    renamed_inst_t renamed_inst0_next, renamed_inst1_next;
    logic can_rename0, can_rename1;

    // Request ROB entries based on validity of incoming instructions
    assign rob_alloc_req[0] = decode_inst0.is_valid;
    assign rob_alloc_req[1] = decode_inst1.is_valid;

    // An instruction can be successfully renamed if it's valid and the ROB grants its request
    assign can_rename0 = decode_inst0.is_valid && rob_alloc_gnt[0];
    assign can_rename1 = decode_inst1.is_valid && rob_alloc_gnt[1];

    always_comb begin
        renamed_inst_t renamed_inst0_tmp,  renamed_inst1_tmp;

        // Step 1: Perform initial renaming for both instructions
        renamed_inst0_tmp = rename_inst(decode_inst0, rs1_0_read_port, rs2_0_read_port, rob_tag0, can_rename0)
        renamed_inst1_tmp = rename_inst(decode_inst1, rs1_1_read_port, rs2_1_read_port, rob_tag1, can_rename1)

        // Apply intra-group forwards logic for inst 1
        //  inst0's rd == inst1's rs1?
        if (can_rename0 && decode_inst0.has_rd && (decode_inst1.rs1 == decode_inst0.rd) && (decode_inst0.rd != 0)) begin
            renamed_inst1_tmp.rs1_renamed   = 1'b1;
            renamed_inst1_tmp.rs1_tag       = rob_tag0;
        end

        //  inst0's rd == inst1's rs2?
        if (can_rename0 && decode_inst0.has_rd && (decode_inst1.rs2 == decode_inst0.rd) && (decode_inst0.rd != 0)) begin
            renamed_inst1_tmp.rs2_renamed   = 1'b1;
            renamed_inst1_tmp.rs2_tag       = rob_tag0;
        end

        renamed_inst0_next = renamed_inst0_tmp;
        renamed_inst1_next = renamed_inst1_tmp;
    end

    // -- Generate Write Ports for PRF --
    assign rat_0_write_port.addr = decode_inst0.rd;
    assign rat_0_write_port.tag  = rob_tag0;
    assign rat_0_write_port.we   = can_rename0 && decode_inst0.has_rd;

    assign rat_1_write_port.addr = decode_inst1.rd;
    assign rat_1_write_port.tag  = rob_tag1;
    assign rat_1_write_port.we   = can_rename1 && decode_inst1.has_rd;

    //-------------------------------------------------------------
    // Handshake and Pipeline Control
    //-------------------------------------------------------------
    assign rename_rdy = dispatch_rdy;
    assign rename_val = can_rename0;

    //-------------------------------------------------------------
    // Pipeline Register Logic
    //-------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst || flush) begin
                renamed_inst0 <= `{default:`0};
                renamed_inst1 <= `{default:`0};
        end else if (rename_rdy) begin
            if (decode_val) begin
                renamed_inst0 <= renamed_inst0_next;
                renamed_inst1 <= renamed_inst1_next;
            end
        end 

    end



endmodule