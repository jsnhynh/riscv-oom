import uarch_pkg::*;

module decode (
    input logic clk, rst, flush, cache_stall,

    // Ports from Fetch
    output logic                        decode_rdy,
    input  logic [CPU_ADDR_BITS-1-0]    inst0_pc,   inst1_pc,
    input  logic [CPU_INST_BITS-1:0]    inst0,      inst1,
    input  logic                        inst_val,

    // Ports to Rename
    input  logic            rename_rdy,
    output decoded_inst_t   decode_inst0,   decode_inst1,
    output logic            decode_val
);

    //-------------------------------------------------------------
    // Immediate Generation Function
    //-------------------------------------------------------------
    function automatic logic [CPU_DATA_BITS-1:0] gen_imm(input logic [CPU_INST_BITS-1:0] inst);
        casez (inst[6:0])
            OPC_ARI_ITYPE:      return {{20{inst[31]}}, inst[31:20]};                               // I-type
            OPC_STORE:          return {{20{inst[31]}}, inst[31:25], inst[11:7]};                   // S-type
            OPC_BRANCH:         return {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};    // B-type
            OPC_LUI, OPC_AUIPC: return {inst[31:12], 12'b0};                                        // U-type (LUI/AUIPC)
            OPC_JAL, OPC_JALR:  return {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};  // J-type (JAL/JALR)
            default:            return '0;
        endcase
    endfunction

    function automatic decoded_inst_t decode_inst (
        input logic [CPU_ADDR_BITS-1:0] pc,
        input logic [CPU_INST_BITS-1:0] inst,
        input logic                     val,
    );
        decoded_inst_t d_inst;
        logic [6:0] opcode  = inst[6:0];
        logic [2:0] funct3  = inst[14:12];
        logic [6:0] funct7  = inst[31:25];

        // Default values
        d_inst = '{default:'0};
        d_inst.pc       = pc;
        d_inst.rd       = inst[11:7];
        d_inst.rs1      = inst[19:15];
        d_inst.rs2      = inst[24:20];
        d_inst.imm      = gen_imm(inst);

        casez (opcode)  // Instructions are valid if sent from buffer and compliant opcode
            OPC_LUI, OPC_AUIPC, OPC_JAL, OPC_JALR, OPC_BRANCH, OPC_LOAD, OPC_STORE, OPC_ARI_ITYPE, OPC_ARI_RTYPE, OPC_CSR:
                                d_inst.is_valid = val;
            default:            d_inst.is_valid = '0;
        endcase
        
        casez (opcode)
            OPC_LUI, OPC_AUIPC, OPC_JAL, OPC_JALR, OPC_LOAD, OPC_ARI_ITYPE, OPC_ARI_RTYPE:
                                d_inst.has_rd = 1'b1;
            default:            d_inst.has_rd = 1'b0;
        endcase

        casez (opcode)
            OPC_BRANCH:         d_inst.is_branch    = 1'b1;
            OPC_JAL, OPC_JALR:  d_inst.is_jump      = 1'b1;
            OPC_LOAD:           d_inst.is_load      = 1'b1;
            OPC_STORE:          d_inst.is_store     = 1'b1;
            OPC_ARI_RTYPE:      d_inst.is_muldiv = (funct7 == FNC7_MULDIV);
            default: ;
        endcase

        casez (opcode)
            OPC_AUIPC, OPC_JAL, OPC_BRANCH: d_inst.alu_a_sel = 1'b1; // Use PC as first operand
            default:                        d_inst.alu_a_sel = 1'b0; // Use rs1
        endcase

        casez (opcode)
            OPC_ARI_RTYPE:      d_inst.alu_b_sel = 1'b0; // Use rs2
            default:            d_inst.alu_b_sel = 1'b1; // Use immediate
        endcase

        logic is_sub_sra    = (funct7 == FNC7_SUB_SRA);
        casez (opcode)
            OPC_ARI_RTYPE, OPC_ARI_ITYPE:   d_inst.uop = {is_sub_sra, funct3};
            OPC_LOAD, OPC_STORE:            d_inst.uop = {'0, funct3};
            default:                        d_inst.uop = {'0, FNC_ADD_SUB};
        endcase

        casez (opcode)
            OPC_BRANCH:         d_inst.uop_br = funct3;
            default:            d_inst.uop_br = '0;
        endcase
        
        return d_inst;
    endfunction

    //-------------------------------------------------------------
    // Handshake and Pipeline Control
    //-------------------------------------------------------------
    assign decode_rdy = rename_rdy && !cache_stall;
    assign decode_val = inst_val && decode_rdy;


    //-------------------------------------------------------------
    // Control Signal Generation
    //-------------------------------------------------------------
    decoded_inst_t decode_inst0_next, decode_inst1_next;

    // Call the decoder function for each instruction path
    assign decode_inst0_next = decode_inst(inst0, inst0_pc, inst_val);
    assign decode_inst1_next = decode_inst(inst1, inst1_pc, inst_val);
    
    //-------------------------------------------------------------
    // Pipeline Register Logic
    //-------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            decode_inst0 <= '{default:'0};
            decode_inst1 <= '{default:'0};
        end else if (decode_rdy) begin // Only update if the stage is not stalled
            if (inst_val) begin
                decode_inst0 <= decode_inst0_next;
                decode_inst1 <= decode_inst1_next;
            end else begin
                // Insert a bubble if input is not valid but we are not stalled
                decode_inst0 <= '{default:'0};
                decode_inst1 <= '{default:'0};
            end
        end
    end

endmodule