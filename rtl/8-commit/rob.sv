/*
 * Commit Reorder Buffer (ROB)
 *
 * This module is the central controller for the out-of-order backend. It
 * is a circular buffer that tracks all in-flight instructions.
 *
 * Its primary responsibilities are:
 * 1. Allocation: Grants tags to the Rename stage.
 * 2. Writeback: Snoops the CDBs and updates entries with results.
 * 3. Commit: Commits up to two instructions in-order, writing to the PRF.
 * 4. Recovery: Detects mispredictions/exceptions at commit and flushes the pipeline.
 */

import riscv_isa_pkg::*;
import uarch_pkg::*;

module rob #(parameter N = ROB_ENTRIES)(
    // Module I/O
    input  logic clk, rst,

    // Control Signals
    output logic flush,
    output logic [CPU_ADDR_BITS-1:0] rob_pc,

    // Ports to Rename (Allocation)
    input  logic [PIPE_WIDTH-1:0]   rob_alloc_req,
    output logic [PIPE_WIDTH-1:0]   rob_alloc_gnt, // Grant for 0, 1, or 2 entries
    output logic [$clog2(N)-1:0]    rob_alloc_tags      [PIPE_WIDTH-1:0],
    
    // Ports to Rename (Commit)
    output prf_commit_write_port_t  commit_write_ports  [PIPE_WIDTH-1:0],

    // Ports from Dispatch
    output logic [PIPE_WIDTH-1:0]   rob_rdy,
    input  logic [PIPE_WIDTH-1:0]   rob_we,
    input  rob_entry_t              rob_entries         [PIPE_WIDTH-1:0],

    // Ports from CDB
    input  writeback_packet_t       cdb_ports           [PIPE_WIDTH-1:0],

    // Ports to LSQ
    output logic [$clog2(N)-1:0]    commit_store_ids    [PIPE_WIDTH-1:0],
    output logic [PIPE_WIDTH-1:0]   commit_store_vals,

    // ROB Pointers
    output logic [$clog2(N)-1:0]    rob_head, rob_tail 
);
    //-------------------------------------------------------------
    // Internal Storage and Pointers
    //-------------------------------------------------------------
    rob_entry_t rob_mem         [N-1:0];
    rob_entry_t rob_mem_next    [N-1:0];
    logic [$clog2(N)-1:0] rob_head_next, rob_tail_next;
    assign rob_head_next = rob_head + 1;
    assign rob_tail_next = rob_tail + 1;

    logic [$clog2(N)-1:0] reserved_tags [PIPE_WIDTH-1:0];
    logic [$clog2(N):0] avail_slots;
    logic [1:0] reserved_cnt;   // # insts reserved this cycle
    logic [1:0] alloc_cnt;      // # insts allocated this cycle
    logic [1:0] commit_cnt;     // # insts commited this cycle

    //-------------------------------------------------------------
    // Pointer Logic
    //-------------------------------------------------------------
    logic [1:0] req_cnt;
    assign req_cnt = rob_alloc_req[0] + rob_alloc_req[1];
    assign rob_alloc_gnt[0] = rob_alloc_req[0] && (avail_slots >= req_cnt);
    assign rob_alloc_gnt[1] = rob_alloc_req[1] && (avail_slots >= req_cnt);

    assign reserved_cnt     = rob_alloc_gnt[0] + rob_alloc_gnt[1];

    assign rob_rdy[0] = alloc_cnt >= 1;
    assign rob_rdy[1] = alloc_cnt >= 2;
    assign rob_alloc_tags[0] = (rob_alloc_gnt[0])? rob_tail : '0;
    assign rob_alloc_tags[1] = (rob_alloc_gnt[1])? rob_tail_next : '0;

    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            rob_head    <= 'd0;
            rob_tail    <= 'd0;
            avail_slots <= N;
            reserved_tags <= '{default:'0};
            alloc_cnt   <= '0;
        end else begin
            rob_head    <= rob_head + commit_cnt;
            rob_tail    <= rob_tail + reserved_cnt;
            avail_slots <= avail_slots - reserved_cnt + commit_cnt;
            reserved_tags <= rob_alloc_tags;
            alloc_cnt   <= reserved_cnt;
        end
    end

    //-------------------------------------------------------------
    // Writeback Logic (Update entries from CDB)
    //-------------------------------------------------------------
    function automatic rob_entry_t cdb_snoop (
        input rob_entry_t           curr_entry,
        input writeback_packet_t    wb_packet,
        input logic [$clog2(N)-1:0] entry_tag
    );
        rob_entry_t updated_entry = curr_entry;
        if (wb_packet.is_valid && (wb_packet.dest_tag == entry_tag) && curr_entry.is_valid) begin
            updated_entry.is_ready      = 1'b1;
            updated_entry.result        = wb_packet.result;
            updated_entry.exception     = wb_packet.exception;
        end
        return updated_entry;
    endfunction

    //-------------------------------------------------------------
    // ROB Entry Update Logic (Combinational)
    //-------------------------------------------------------------
    always_comb begin
        // Start with existing values (pass-through by default)
        rob_mem_next = rob_mem;
        
        for (int i = 0; i < N; i++) begin
            automatic logic [$clog2(N)-1:0] tag = i;
            
            // Priority 1: Dispatch writes (using reserved tags from previous cycle)
            if (rob_we[0] && rob_rdy[0] && (tag == reserved_tags[0])) begin
                rob_mem_next[i] = rob_entries[0];
                // Stores are immediately ready (LSQ handles address computation)
                rob_mem_next[i].is_ready = (rob_entries[0].opcode == OPC_STORE);
            end
            if (rob_we[1] && rob_rdy[1] && (tag == reserved_tags[1])) begin
                rob_mem_next[i] = rob_entries[1];
                rob_mem_next[i].is_ready = (rob_entries[1].opcode == OPC_STORE);
            end

            // Priority 2: CDB snoops (chain from rob_mem_next to allow same-cycle bypass)
            for (int j = 0; j < PIPE_WIDTH; j++) begin
                rob_mem_next[i] = cdb_snoop(rob_mem_next[i], cdb_ports[j], tag);
            end

            // Priority 3: Invalidate entries that are committing this cycle
            if (((rob_head == tag) && (commit_cnt >= 1)) ||
                ((rob_head_next == tag) && (commit_cnt >= 2))) begin
                rob_mem_next[i] = '{default:'x};
            end
        end
    end
    
    // Register the next state
    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            for (int i = 0; i < N; i++) begin
                rob_mem[i] <= '{default:'x};
            end
        end else begin
            rob_mem <= rob_mem_next;
        end
    end

    //-------------------------------------------------------------
    // Commit Logic
    //-------------------------------------------------------------
    typedef struct packed {
        logic                       do_flush;
        logic                       do_commmit;
        logic [CPU_ADDR_BITS-1:0]   redirect_pc;
        prf_commit_write_port_t     prf_commit;
        logic [$clog2(N)-1:0]       commit_store_id;
        logic                       commit_store_val;
    } commit_info_t;

    function automatic commit_info_t proc_commit(input logic [$clog2(N)-1:0] ptr);
        commit_info_t info = '{default:'0};
        rob_entry_t entry = rob_mem[ptr];
        
        logic handshake = entry.is_ready && entry.is_valid;
        logic is_exception = entry.exception;
        logic is_mispredict = (entry.opcode == OPC_BRANCH) && entry.result[0];
        logic is_jump = (entry.opcode == OPC_JAL) || (entry.opcode == OPC_JALR);

        info.do_flush = handshake && (is_exception || is_mispredict || is_jump);
        info.do_commmit = handshake && !is_exception && !is_mispredict; // Jumps need commit to link

        if (info.do_commmit) begin 
            // Commit Info
            info.prf_commit.addr    = entry.rd;
            info.prf_commit.data    = (is_jump)? entry.pc+4 : entry.result;
            info.prf_commit.tag     = ptr;
            info.prf_commit.we      = entry.has_rd && (entry.opcode != OPC_STORE);

            // LSQ Commit Info
            info.commit_store_id    = ptr;
            info.commit_store_val   = entry.opcode == OPC_STORE;
        end

        if (handshake && is_exception) begin
            info.redirect_pc = 'x; // TODO: Exception Handler PC
        end else begin
            info.redirect_pc = {entry.result[31:1], 1'b0};
        end

        return info;
    endfunction

    commit_info_t commit_info [PIPE_WIDTH-1:0];

    always_comb begin
        commit_info[0] = proc_commit(rob_head);
        // Only process second candidate if first doesnt flush
        commit_info[1] = commit_info[0].do_flush? '{default:'0} : proc_commit(rob_head_next);
    end

    always_comb begin
        rob_pc  = '0;
        flush   = 1'b0;
        commit_write_ports  = '{default:'0};
        commit_store_ids    = '{default:'0};
        commit_store_vals   = '{default:'0};
        commit_cnt          = '0;

        if (commit_info[0].do_flush) begin
            rob_pc  = commit_info[0].redirect_pc;
            flush   = 1'b1;
        end else if (commit_info[1].do_flush) begin
            rob_pc  = commit_info[1].redirect_pc;
            flush   = 1'b1;
        end

        if (commit_info[0].do_commmit) begin
            commit_cnt = 2'd1;
            commit_write_ports[0]   = commit_info[0].prf_commit;
            commit_store_ids[0]     = commit_info[0].commit_store_id;
            commit_store_vals[0]    = commit_info[0].commit_store_val;
        end
        if (commit_info[1].do_commmit && commit_info[0].do_commmit) begin
            commit_cnt = 2'd2;
            commit_write_ports[1]   = commit_info[1].prf_commit;
            commit_store_ids[1]     = commit_info[1].commit_store_id;
            commit_store_vals[1]    = commit_info[1].commit_store_val;
        end
    end

endmodule