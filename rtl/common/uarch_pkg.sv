/*
 * Microarchitectural Types Package
 *
 * This package defines the internal, implementation-specific parameters and
 * data structures (structs) for this specific out-of-order processor.
 * It includes the definitions for pipeline-stage interfaces (e.g.,
 * decoded_inst_t, renamed_inst_t), ROB/RS/LSQ sizing parameters,
 * and PRF port types.
 */

package uarch_pkg;
    import riscv_isa_pkg::*;

    //-------------------------------------------------------------
    // Global Microarchitectural Parameters
    //-------------------------------------------------------------
    // These are the "knobs" to configure the size and performance of your core.
    localparam CLK_PERIOD       = 10;       // 10ns = 100MHz clock
    localparam FETCH_WIDTH      = 2;        // Number of instructions per fetch
    localparam PIPE_WIDTH       = 2;        // Number of instructions processed

    localparam ROB_ENTRIES      = 32;
    localparam ALU_RS_ENTRIES   = 8;
    localparam MDU_RS_ENTRIES   = 4;
    localparam LSQ_ENTRIES      = 8;
    localparam INST_BUF_DEPTH   = 4;

    localparam TAG_WIDTH        = $clog2(ROB_ENTRIES);

    localparam NUM_RS           = 4;        // Number of RS's
    /*  RS ID MAPPING
        0: ALU_RS
        1: LSQ_LD
        2: LSQ_ST
        3: MDU_RS
    */
    localparam NUM_FU           = 5;        // Number of FU's
    /* FU ID MAPPING
        0: ALU_0
        1: ALU_1
        2: MEM
        3: AGU
        4: MDU 
    */

    /*
        The following structs is used to pass decoded instructions down the pipeline to the FU
    */
    typedef struct packed {
        logic [CPU_DATA_BITS-1:0]   data;       // Reference if is_renamed == 1, else snoop CDB with tag
        logic [TAG_WIDTH-1:0]       tag;        // is_renamed? renamed_tag / reg_addr
        logic                       is_renamed;
    } source_t;

    typedef struct packed {
        logic [CPU_ADDR_BITS-1:0] pc;
        logic [4:0] rd;
        logic [TAG_WIDTH-1:0] dest_tag;

        /* 2 Sources + Operation */
        source_t    src_0_a;    // a_sel? PC  : RS1
        source_t    src_0_b;    // b_sel? IMM : RS2
        logic [2:0] uop_0;      // Func3, replace with ADD for address generation

        /* 2 Sources + Operation, used for parallel operations/additional data ie:BRANCHES/STORE*/
        source_t    src_1_a;    // Always RS1 (For Branches)
        source_t    src_1_b;    // Always RS2 (For Branches/Store_Data)
        logic [2:0] uop_1;      // Func3, Used for Branch Operation, use ADD for uop_0

        // Control Signals
        logic is_valid;
        logic has_rd;
        logic br_taken;         // Set to 1 if jump, can be later used for Branch Prediction
        logic agu_comp;
        logic [6:0] opcode;
        logic [6:0] funct7;
    } instruction_t;

    //-------------------------------------------------------------
    // Execute Stage -> Writeback Stage Interface (The CDB)
    //-------------------------------------------------------------
    // The narrowest packet, containing only the result to be broadcast.
    typedef struct packed {
        logic [TAG_WIDTH-1:0]       dest_tag; // The rob_id
        logic [CPU_DATA_BITS-1:0]   result;
        logic                       is_valid;
        logic                       exception;
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
        logic                       exception;

        // Control Flow Information
        logic [6:0]                 opcode;
    } rob_entry_t;

    //-------------------------------------------------------------
    // Physical Register File (PRF) Port Definitions
    //-------------------------------------------------------------
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

endpackage