package branch_pkg;
    import riscv_isa_pkg::*;
    import uarch_pkg::*;

    //-------------------------------------------------------------
    // Global Branch Parameters
    //-------------------------------------------------------------
    // These are the "knobs" to configure the size and performance of your branch prediction.
    localparam BTB_ENTRIES      = 128;
    localparam BTB_TAG_WIDTH    = 12;

    localparam RAS_ENTRIES      = 16;

    localparam GHR_WIDTH        = 32;
    localparam BASE_ENTRIES     = 256;

    localparam TAGE_ENTRIES     = 128;
    localparam TAGE_TABLES      = 4;
    localparam TAGE_TAG_WIDTH   = 8;
    localparam CTR_WIDTH        = 3;


    // Branch types
    localparam BRANCH_COND = 2'b00;
    localparam BRANCH_JUMP = 2'b01;
    localparam BRANCH_CALL = 2'b10;
    localparam BRANCH_RET  = 2'b11;

    //----------------------------------------------------------
    //  The following structs is used to pass around the BPU
    //----------------------------------------------------------

    /* 
        Branch Target Buffer Structs
    */
    typedef struct packed {
        logic                       hit;
        logic [CPU_ADDR_BITS-1:0]   targ;
        logic [1:0]                 btype;
    } btb_read_port_t;

    typedef struct packed {
        logic                       val;
        logic [CPU_ADDR_BITS-1:0]   pc;
        logic [CPU_ADDR_BITS-1:0]   targ;
        logic [1:0]                 btype;
        logic                       taken;
    } btb_write_port_t;

    /*
        Fetch Target Queue Structs
    */
    typedef struct packed {
        logic                           val;
        logic [CPU_ADDR_BITS-1:0]       pc;             // For hash and recovery
        
        logic [$clog2(TAGE_TABLES):0]   provider;       // Which table (0-3, 4=Base)
        logic                           pred_taken;     // Provider's prediction
        logic                           pred_alt;       // Altpred's prediction
        logic [1:0]                     btype;          // Branch type
        logic [CPU_ADDR_BITS-1:0]       target;         // Branch Target

        logic [GHR_WIDTH-1:0]           ghr_cp;         // For hash & recovery
        logic [$clog2(RAS_ENTRIES):0]   ras_cp;         // For RAS recovery
    } ftq_entry_t;

    /*
        TAGE Structs
    */
    typedef struct packed {
        logic                           val;
        logic [$clog2(TAGE_TABLES):0]   provider;       // Which tage table
        logic                           pred_taken;     // Provider's prediction
        logic                           pred_alt;       // For usefulness
        logic                           ghr;            // Current GHR to checkpoint
    } tage_pred_port_t;

    typedef struct packed {
        logic                           val;
        logic [CPU_ADDR_BITS-1:0]       pc;
        logic                           actual_taken;   // From ROB
        logic [$clog2(TAGE_TABLES):0]   provider;       // From FTQ
        logic                           pred_taken;     // From FTQ
        logic                           pred_alt;       // From FTQ
        logic [GHR_WIDTH-1:0]           ghr_cp;         // From FTQ
    } tage_update_port_t;

endpackage