/*
    This package defines all the structed types and parameters
    used to pass information between the stages of the dual-issue, 
    out-of-order RISC-V core.

    By centralizing these definitions, we create a single source of
    truth for all module interfaces.
*/

package uarch_pkg;
    import riscv_isa_pkg::*;

    //-------------------------------------------------------------
    // Global Microarchitectural Parameters
    //-------------------------------------------------------------
    // These are the "knobs" to configure the size and performance of your core.
    localparam CLK_PERIOD       = 10;       // 10ns = 100MHz clock
    localparam FETCH_WIDTH      = 2;        // Number of instructions per fetch  

    localparam ROB_ENTRIES      = 32;
    localparam ALU_RS_ENTRIES   = 8;
    localparam MDU_RS_ENTRIES   = 4;
    localparam LSQ_ENTRIES      = 8;
    localparam INST_BUFFER_DEPTH = 4;

    localparam TAG_WIDTH        = $clog2(ROB_ENTRIES);

    //-------------------------------------------------------------
    // Decode Stage -> Rename Stage Interface
    //-------------------------------------------------------------
    // This packet contains all parsed info and control signals available after decode.
    typedef struct packed {
        logic [CPU_ADDR_BITS-1:0]   pc;
        logic [4:0]                 rd, rs1, rs2;
        logic [CPU_DATA_BITS-1:0]   imm;
        // Control Signals
        logic                       is_valid;
        logic                       has_rd;
        logic                       is_branch,  is_jump;
        logic                       is_load,    is_store;
        logic                       is_muldiv;
        logic                       alu_a_sel,  alu_b_sel;
        logic [3:0]                 uop;
        logic [2:0]                 uop_br;
    } decoded_inst_t;

    //-------------------------------------------------------------
    // Rename Stage -> Dispatch Stage Interface
    //-------------------------------------------------------------
    // This packet adds the renaming tags and operand values and serves as RS entry
    typedef struct packed {
        logic [CPU_ADDR_BITS-1:0]   pc;
        logic [TAG_WIDTH-1:0]       dest_tag; // The rob_id for this instruction
        logic [CPU_DATA_BITS-1:0]   imm;
        // Control Signals
        logic                       is_valid;
        logic                       is_branch,  is_jump;
        logic                       is_load,    is_store;
        logic                       is_muldiv;
        logic                       alu_a_sel,  alu_b_sel;
        logic [3:0]                 uop;
        logic [2:0]                 uop_br;
        
        logic [TAG_WIDTH-1:0]       rs1_tag,        rs2_tag;
        logic [CPU_DATA_BITS-1:0]   rs1_data,       rs2_data;
        logic                       rs1_renamed,    rs2_renamed;
    } renamed_inst_t;

    //-------------------------------------------------------------
    // Issue Stage -> Execute Stage Interface
    //-------------------------------------------------------------
    // A unified but shrunken packet containing the superset of signals for all FUs.
    typedef struct packed {
        // Common Fields
        logic [TAG_WIDTH-1:0]       dest_tag;
        logic [CPU_DATA_BITS-1:0]   operand_a,  operand_b;
        logic                       is_valid;

        // FU Control
        logic [3:0]                 uop;

        // Branch Comparator Control
        logic                       is_branch;
        logic [2:0]                 uop_br;
        logic [CPU_DATA_BITS-1:0]   rs1_data,   rs2_data;

        // Memory Unit (LSQ) Control
        logic                       is_load,    is_store;
        logic [CPU_DATA_BITS-1:0]   store_data;
    } execute_packet_t;

    //-------------------------------------------------------------
    // Execute Stage -> Writeback Stage Interface (The CDB)
    //-------------------------------------------------------------
    // The narrowest packet, containing only the result to be broadcast.
    typedef struct packed {
        logic [TAG_WIDTH-1:0]       dest_tag; // The rob_id
        logic [CPU_DATA_BITS-1:0]   result;
        logic                       is_valid;
        logic                       is_exception;
    } writeback_packet_t;

    //-------------------------------------------------------------
    // Reorder Buffer (ROB) Entry Definition
    //-------------------------------------------------------------
    // This struct defines the contents of a single entry in the ROB.
    typedef struct packed {
        // State Flags
        logic                       is_valid;
        logic                       is_ready;   // Has the instruction completed execution?

        // Instruction Information
        logic [CPU_ADDR_BITS-1:0]   pc;
        logic [4:0]                 rd;         // The architectural destination register (rd)
        logic                       has_rd;     // Does this instruction write to a destination?

        // Result Storage
        logic [CPU_DATA_BITS-1:0]   result;     // For branches, jump_pc is stored in upper 31 bits and LSB is taken/not-taken 
        logic                       has_exception;

        // Control Flow Information
        logic                       is_branch, is_jump;
        logic                       is_store;
    } rob_entry_t;

    //-------------------------------------------------------------
    // Physical Register File (PRF) Port Definitions
    //-------------------------------------------------------------
    typedef struct packed {
        logic [CPU_DATA_BITS-1:0]   data;
        logic [TAG_WIDTH-1:0]       tag;
        logic                       renamed;
    } prf_read_port_t;

    typedef struct packed {
        logic [$clog2(ARCH_REGS)-1:0]   addr;
        logic [TAG_WIDTH-1:0]           tag;
        logic                           we;
    } prf_rat_write_port_t;

    typedef struct packed {
        logic [$clog2(ARCH_REGS)-1:0]   addr;
        logic [CPU_DATA_BITS-1:0]       data;
        logic [TAG_WIDTH-1:0]           tag;
        logic                           we;
    } prf_commit_write_port_t;


    /*
        The following structs is used to pass decoded instructions down the pipeline to the FU
    */
    typedef struct packed {
        logic [CPU_DATA_BITS-1:0]   data,
        logic [TAG_WIDTH-1:0]       tag,        // is_renamed? renamed_tag / reg_addr
        logic                       is_renamed
    } source_t;

    typedef struct packed {
        logic [CPU_ADDR_BITS-1:0] pc,
        logic [TAG_WIDTH-1:0] dest_tag,

        /* 2 Sources + Operation */
        source_t    src_0_a,    // a_sel? PC  : RS1
        source_t    src_0_b,    // b_sel? IMM : RS2
        logic [3:0] uop_0,      // {Func7[i], Func3}, where i is bit index we check per inst (SUB/SRC: bit[25], MUL: bit[31])

        /* 2 Sources + Operation, used for parallel operations/additional data ie:BRANCHES/STORE*/
        source_t    src_1_a,    // Always RS1 (For Branches)
        source_t    src_1_b,    // Always RS2 (For Branches/Store_Data)
        logic [3:0] uop_1,      // {0, Func3} // Used for Branch Operation, use ADD for uop_0

        // Control Signals
        logic is_valid,
        logic br_taken,         // Set to 1 if jump, can be later used for Branch Prediction
        logic [2:0] opcode
        /* Upper 3 Bits of Opcode can be adeqetly used to determine function type
            011, 001, 111: ALU
            000: MEM_LOAD
            010: MEM_STORE
            110: BRANCH / JUMP
        */
    } instruction_t

endpackage