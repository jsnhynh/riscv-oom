/*
 * Rename Stage
 *
 * This module is the heart of the out-of-order frontend. It performs:
 * 1. PRF Read: Reads the status of source operands (rs1, rs2) for N instructions.
 * 2. ROB Allocation: Requests and is granted new tags from the ROB.
 * 3. PRF (RAT) Write: Writes the new speculative mappings (rd -> rob_tag) to the PRF.
 * 4. Dependency Forwarding: Resolves intra-group dependencies (e.g., inst1 depends on inst0).
 * 5. Compaction: Ensures a single valid instruction is always in slot 0.
 * It outputs N instruction_t packets to the Dispatch stage.
 */
import riscv_isa_pkg::*;
import uarch_pkg::*;

module rename (
    input logic clk, rst, flush,

    // Ports from Decode
    output logic                    rename_rdy,
    input  instruction_t            decoded_insts       [PIPE_WIDTH-1:0],

    // Ports to Dispatch
    input  logic                    dispatch_rdy,
    output instruction_t            renamed_insts       [PIPE_WIDTH-1:0],

    // Ports from ROB
    output logic [PIPE_WIDTH-1:0]   rob_alloc_req,
    input  logic [PIPE_WIDTH-1:0]   rob_alloc_gnt, // Grant for 0, 1, or 2 entries
    input  logic [TAG_WIDTH-1:0]    rob_alloc_tags      [PIPE_WIDTH-1:0],
    input  prf_commit_write_port_t  commit_write_ports  [PIPE_WIDTH-1:0]
);
    //-------------------------------------------------------------
    // Internal Wires and Connections
    //-------------------------------------------------------------
    source_t                rs1_read_ports  [PIPE_WIDTH-1:0];
    source_t                rs2_read_ports  [PIPE_WIDTH-1:0];
    prf_rat_write_port_t    rat_write_ports [PIPE_WIDTH-1:0];

    prf prf_inst (
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .rs1({decoded_insts[1].src_1_a.tag, decoded_insts[0].src_1_a.tag}),
        .rs2({decoded_insts[1].src_1_b.tag, decoded_insts[0].src_1_b.tag}),
        .rs1_read_ports(rs1_read_ports),
        .rs2_read_ports(rs2_read_ports),

        .rat_write_ports(rat_write_ports),
        
        .commit_write_ports(commit_write_ports)
    );

    //-------------------------------------------------------------
    // Renaming Function
    //-------------------------------------------------------------
    function automatic instruction_t rename_inst (
        input instruction_t d_inst,
        input source_t rs1_port,
        input source_t rs2_port,
        input logic [TAG_WIDTH-1:0] new_tag,
        input logic                 alloc_gnt
    );
        instruction_t r_inst;
        r_inst = '{default:'0};
        r_inst.is_valid = alloc_gnt && d_inst.is_valid;

        // Pass-through fields from decode
        r_inst.pc           = d_inst.pc;
        r_inst.rd           = d_inst.rd;
        r_inst.has_rd       = d_inst.has_rd;
        r_inst.br_taken     = d_inst.br_taken;
        r_inst.opcode       = d_inst.opcode;
        r_inst.funct7       = d_inst.funct7;
        r_inst.uop_0        = d_inst.uop_0;
        r_inst.uop_1        = d_inst.uop_1;

        // New Fields added by rename
        r_inst.dest_tag     = new_tag;

        if (d_inst.src_0_a.tag == d_inst.src_1_a.tag) begin
            r_inst.src_0_a.data         = rs1_port.data;
            r_inst.src_0_a.tag          = rs1_port.tag;
            r_inst.src_0_a.is_renamed   = rs1_port.is_renamed;
        end else r_inst.src_0_a.data    = d_inst.src_0_a.data; // Pass PC

        if (d_inst.src_0_b.tag == d_inst.src_1_b.tag) begin
            r_inst.src_0_b.data         = rs2_port.data;
            r_inst.src_0_b.tag          = rs2_port.tag;
            r_inst.src_0_b.is_renamed   = rs2_port.is_renamed;
        end else r_inst.src_0_b.data    = d_inst.src_0_b.data; // Pass IMM

        r_inst.src_1_a.data         = rs1_port.data;
        r_inst.src_1_a.tag          = rs1_port.tag;
        r_inst.src_1_a.is_renamed   = rs1_port.is_renamed;

        r_inst.src_1_b.data         = rs2_port.data;
        r_inst.src_1_b.tag          = rs2_port.tag;
        r_inst.src_1_b.is_renamed   = rs2_port.is_renamed;

        return r_inst;
    endfunction

    //-------------------------------------------------------------
    // Conbinational Renaming Logic
    //-------------------------------------------------------------
    instruction_t renamed_insts_next [PIPE_WIDTH-1:0];
    logic all_gnts_ok;

    // Request ROB entries based on validity of incoming instructions
    assign rob_alloc_req[0] = decoded_insts[0].is_valid;
    assign rob_alloc_req[1] = decoded_insts[1].is_valid;

    assign all_gnts_ok = (!decoded_insts[0].is_valid || rob_alloc_gnt[0]) && (!decoded_insts[1].is_valid || rob_alloc_gnt[1]);
    
    instruction_t renamed_insts_tmp [PIPE_WIDTH-1:0];
    always_comb begin
        // Step 1: Perform initial renaming for both instructions
        renamed_insts_tmp[0] = rename_inst(decoded_insts[0], rs1_read_ports[0], rs2_read_ports[0], rob_alloc_tags[0], decoded_insts[0].is_valid && all_gnts_ok);
        renamed_insts_tmp[1] = rename_inst(decoded_insts[1], rs1_read_ports[1], rs2_read_ports[1], rob_alloc_tags[1], decoded_insts[1].is_valid && all_gnts_ok);

        // Step 2: Apply intra-group forwards logic for inst 1
        if (decoded_insts[0].is_valid && rob_alloc_gnt[0] && decoded_insts[0].has_rd && (decoded_insts[1].src_1_a.tag[$clog2(ARCH_REGS)-1:0] == decoded_insts[0].rd) && (decoded_insts[0].rd != 0)) begin //  inst0's rd == inst1's rs1?
            renamed_insts_tmp[1].src_1_a.is_renamed = 1'b1;
            renamed_insts_tmp[1].src_1_a.tag       = rob_alloc_tags[0];
        end

        if (decoded_insts[0].is_valid && rob_alloc_gnt[0] && decoded_insts[0].has_rd && (decoded_insts[1].src_1_b.tag[$clog2(ARCH_REGS)-1:0] == decoded_insts[0].rd) && (decoded_insts[0].rd != 0)) begin //  inst0's rd == inst1's rs2?
            renamed_insts_tmp[1].src_1_b.is_renamed = 1'b1;
            renamed_insts_tmp[1].src_1_b.tag        = rob_alloc_tags[0];
        end

        // Step 3: Pass Through Sources
        if (decoded_insts[0].src_0_a.tag == decoded_insts[0].src_1_a.tag) begin
            renamed_insts_tmp[0].src_0_a.data       = renamed_insts_tmp[0].src_1_a.data;
            renamed_insts_tmp[0].src_0_a.tag        = renamed_insts_tmp[0].src_1_a.tag;
            renamed_insts_tmp[0].src_0_a.is_renamed = renamed_insts_tmp[0].src_1_a.is_renamed;
        end
        if (decoded_insts[0].src_0_b.tag == decoded_insts[0].src_1_b.tag) begin
            renamed_insts_tmp[0].src_0_b.data       = renamed_insts_tmp[0].src_1_b.data;
            renamed_insts_tmp[0].src_0_b.tag        = renamed_insts_tmp[0].src_1_b.tag;
            renamed_insts_tmp[0].src_0_b.is_renamed = renamed_insts_tmp[0].src_1_b.is_renamed;
        end

        if (decoded_insts[1].src_0_a.tag == decoded_insts[1].src_1_a.tag) begin
            renamed_insts_tmp[1].src_0_a.data       = renamed_insts_tmp[1].src_1_a.data;
            renamed_insts_tmp[1].src_0_a.tag        = renamed_insts_tmp[1].src_1_a.tag;
            renamed_insts_tmp[1].src_0_a.is_renamed = renamed_insts_tmp[1].src_1_a.is_renamed;
        end
        if (decoded_insts[1].src_0_b.tag == decoded_insts[1].src_1_b.tag) begin
            renamed_insts_tmp[1].src_0_b.data       = renamed_insts_tmp[1].src_1_b.data;
            renamed_insts_tmp[1].src_0_b.tag        = renamed_insts_tmp[1].src_1_b.tag;
            renamed_insts_tmp[1].src_0_b.is_renamed = renamed_insts_tmp[1].src_1_b.is_renamed;
        end

        // Step 4: Compaction Logic
        if (!renamed_insts_tmp[0].is_valid && renamed_insts_tmp[1].is_valid) begin
            renamed_insts_next[0] = renamed_insts_tmp[1];
            renamed_insts_next[1] = '{default:'0};
        end else begin
            renamed_insts_next[0] = renamed_insts_tmp[0];
            renamed_insts_next[1] = renamed_insts_tmp[1];
        end

    end

    // -- Generate Write Ports for PRF --
    assign rat_write_ports[0].addr = decoded_insts[0].rd;
    assign rat_write_ports[0].tag  = rob_alloc_tags[0];
    assign rat_write_ports[0].we   = decoded_insts[0].is_valid && rob_alloc_gnt[0] && decoded_insts[0].has_rd;

    assign rat_write_ports[1].addr = decoded_insts[1].rd;
    assign rat_write_ports[1].tag  = rob_alloc_tags[1];
    assign rat_write_ports[1].we   = decoded_insts[1].is_valid && rob_alloc_gnt[1] && decoded_insts[1].has_rd;

    //-------------------------------------------------------------
    // Handshake and Pipeline Control
    //-------------------------------------------------------------
    assign rename_rdy = dispatch_rdy && all_gnts_ok;

    //-------------------------------------------------------------
    // Pipeline Register Logic
    //-------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            renamed_insts[0] <= '{default:'0};
            renamed_insts[1] <= '{default:'0};
        end else if (rename_rdy) begin
            renamed_insts[0] <= renamed_insts_next[0];
            renamed_insts[1] <= renamed_insts_next[1];
        end
    end

endmodule