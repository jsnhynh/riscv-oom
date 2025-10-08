`ifndef CONST
`define CONST

//-----------------------------------------------------------------
// General Architectural Parameters
//-----------------------------------------------------------------
`define CPU_ADDR_BITS   32
`define CPU_INST_BITS   32
`define CPU_DATA_BITS   32

// PC address on reset
`define PC_RESET        32'h00002000


//-----------------------------------------------------------------
// RISC-V ISA Encodings
//-----------------------------------------------------------------

// -- Opcodes (Instruction bits 6:0) --
`define OPC_LUI         7'b0110111
`define OPC_AUIPC       7'b0010111
`define OPC_JAL         7'b1101111
`define OPC_JALR        7'b1100111
`define OPC_BRANCH      7'b1100011
`define OPC_LOAD        7'b0000011
`define OPC_STORE       7'b0100011
`define OPC_ARI_ITYPE   7'b0010011 // Arithmetic I-Type (e.g., ADDI)
`define OPC_ARI_RTYPE   7'b0110011 // Arithmetic R-Type (e.g., ADD)
`define OPC_CSR         7'b1110011
`define OPC_NOOP        7'b0000000 // A non-standard NOP for pipeline kills

// -- Funct3 for BRANCH Instructions (Instruction bits 14:12) --
`define FNC_BEQ         3'b000
`define FNC_BNE         3'b001
`define FNC_BLT         3'b100
`define FNC_BGE         3'b101
`define FNC_BLTU        3'b110
`define FNC_BGEU        3'b111

// -- Funct3 for LOAD/STORE Instructions (Instruction bits 14:12) --
`define FNC_B           3'b000 // LB, SB
`define FNC_H           3'b001 // LH, SH
`define FNC_W           3'b010 // LW, SW
`define FNC_BU          3'b100 // LBU
`define FNC_HU          3'b101 // LHU

// -- Funct3 for Arithmetic R-Type and I-Type (Instruction bits 14:12) --
`define FNC_ADD_SUB     3'b000
`define FNC_SLL         3'b001
`define FNC_SLT         3'b010
`define FNC_SLTU        3'b011
`define FNC_XOR         3'b100
`define FNC_SRL_SRA     3'b101
`define FNC_OR          3'b110
`define FNC_AND         3'b111

// -- Funct3 for 'M' Extension (MUL/DIV) -- (NEW)
`define FNC_MUL         3'b000 // mul
`define FNC_MULH        3'b001 // mulh
`define FNC_MULHSU      3'b010 // mulhsu
`define FNC_MULHU       3'b011 // mulhu
`define FNC_DIV         3'b100 // div
`define FNC_DIVU        3'b101 // divu
`define FNC_REM         3'b110 // rem
`define FNC_REMU        3'b111 // remu

// -- Funct7 Bit (Instruction bit 30) for distinguishing ops with same Funct3 --
`define FNC7_ADD_SRL    1'b0
`define FNC7_SUB_SRA    1'b1
`define FNC7_MULDIV     7'b0000001

// Standard NOP instruction encoding (addi x0, x0, 0)
`define INSTR_NOP       32'h00000013

//-----------------------------------------------------------------
// CSR Register Addresses
//-----------------------------------------------------------------
`define CSR_STATUS      12'h50A
`define CSR_HARTID      12'h50B
`define CSR_TOHOST      12'h51E

`endif