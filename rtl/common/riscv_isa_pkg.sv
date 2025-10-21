/*
    This package defines the standard, unchanging architectural 
    constants for the RV32IM instruction set, including opcodes 
    and fuction fields.
*/

package riscv_isa_pkg;
    //-------------------------------------------------------------
    // Global Architectural Parameters
    //-------------------------------------------------------------
    localparam CPU_ADDR_BITS = 32;
    localparam CPU_INST_BITS = 32;
    localparam CPU_DATA_BITS = 32;
    localparam ARCH_REGS     = 32;
    localparam PC_RESET      = 32'h00002000;

    //-------------------------------------------------------------
    // RISC-V ISA Encodings
    //-------------------------------------------------------------

    // -- Opcodes (Instruction bits 6:0) --
    localparam logic [6:0] OPC_LUI         = 7'b0110111;
    localparam logic [6:0] OPC_AUIPC       = 7'b0010111;
    localparam logic [6:0] OPC_JAL         = 7'b1101111;
    localparam logic [6:0] OPC_JALR        = 7'b1100111;
    localparam logic [6:0] OPC_BRANCH      = 7'b1100011;
    localparam logic [6:0] OPC_LOAD        = 7'b0000011;
    localparam logic [6:0] OPC_STORE       = 7'b0100011;
    localparam logic [6:0] OPC_ARI_ITYPE   = 7'b0010011; // Arithmetic I-Type
    localparam logic [6:0] OPC_ARI_RTYPE   = 7'b0110011; // Arithmetic R-Type
    localparam logic [6:0] OPC_CSR         = 7'b1110011;

    // -- Funct3 for BRANCH Instructions --
    localparam logic [2:0] FNC_BEQ         = 3'b000;
    localparam logic [2:0] FNC_BNE         = 3'b001;
    localparam logic [2:0] FNC_BLT         = 3'b100;
    localparam logic [2:0] FNC_BGE         = 3'b101;
    localparam logic [2:0] FNC_BLTU        = 3'b110;
    localparam logic [2:0] FNC_BGEU        = 3'b111;

    // -- Funct3 for LOAD/STORE Instructions --
    localparam logic [2:0] FNC_B           = 3'b000; // LB, SB
    localparam logic [2:0] FNC_H           = 3'b001; // LH, SH
    localparam logic [2:0] FNC_W           = 3'b010; // LW, SW
    localparam logic [2:0] FNC_BU          = 3'b100; // LBU
    localparam logic [2:0] FNC_HU          = 3'b101; // LHU

    // -- Funct3 for Arithmetic R-Type and I-Type --
    localparam logic [2:0] FNC_ADD_SUB     = 3'b000;
    localparam logic [2:0] FNC_SLL         = 3'b001;
    localparam logic [2:0] FNC_SLT         = 3'b010;
    localparam logic [2:0] FNC_SLTU        = 3'b011;
    localparam logic [2:0] FNC_XOR         = 3'b100;
    localparam logic [2:0] FNC_SRL_SRA     = 3'b101;
    localparam logic [2:0] FNC_OR          = 3'b110;
    localparam logic [2:0] FNC_AND         = 3'b111;

    // -- Funct3 for 'M' Extension (MUL/DIV) --
    localparam logic [2:0] FNC_MUL         = 3'b000;
    localparam logic [2:0] FNC_MULH        = 3'b001;
    localparam logic [2:0] FNC_MULHSU      = 3'b010;
    localparam logic [2:0] FNC_MULHU       = 3'b011;
    localparam logic [2:0] FNC_DIV         = 3'b100;
    localparam logic [2:0] FNC_DIVU        = 3'b101;
    localparam logic [2:0] FNC_REM         = 3'b110;
    localparam logic [2:0] FNC_REMU        = 3'b111;

    // -- Funct7 Field --
    localparam logic [6:0] FNC7_MULDIV     = 7'b0000001;
    localparam logic [6:0] FNC7_SUB_SRA    = 7'b0100000;

    // -- Standard NOP encoding --
    localparam logic [31:0] INSTR_NOP      = 32'h00000013; // addi x0, x0, 0

    // -- CSR Register Addresses --
    localparam logic [11:0] CSR_STATUS = 12'h50A;
    localparam logic [11:0] CSR_HARTID = 12'h50B;
    localparam logic [11:0] CSR_TOHOST = 12'h51E;

endpackage
