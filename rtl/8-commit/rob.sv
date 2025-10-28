import uarch_pkg::*;

module rob (
    // Module I/O
    input  logic clk, rst,
    input  logic [1:0] rob_rdy,

    // Control Signals
    output logic flush,
    output logic [CPU_ADDR_BITS-1:0] rob_pc,

    // Ports to Rename (Allocation)
    input  logic [1:0]              rob_alloc_req,
    output logic [1:0]              rob_alloc_gnt, // Grant for 0, 1, or 2 entries
    output logic [TAG_WIDTH-1:0]    rob_tag0,               rob_tag1,
    
    // Ports to Rename (Commit)
    output prf_commit_write_port_t  commit_0_write_port,    commit_1_write_port

    // Ports from Dispatch
    input rob_entry_t               rob_entry0, rob_entry1,
    input logic [1:0]               rob_we,

    // Ports from CDB
    input  writeback_packet_t       cdb_port0, cdb_port1,

    // Ports to LSQ
    output logic [TAG_WIDTH-1:0]    commit_store_id0,   commit_store_id1,
    output logic                    commit_store_val0,  commit_store_val1,

    // ROB Pointers
    output logic [TAG_WIDTH-1:0]    rob_head, rob_tail 
);
    //-------------------------------------------------------------
    // Internal Storage and Pointers
    //-------------------------------------------------------------
    localparam PTR_WIDTH = TAG_WIDTH;

    rob_entry_t rob_entries [ROB_ENTRIES];
    rob_entry_t rob_entries_next [ROB_ENTRIES];
    logic [PTR_WIDTH:0] head, tail;
    logic [PTR_WIDTH:0] head_next, tail_next;
    logic [$clog2(ROB_ENTRIES):0] avail_slots;
    logic [1:0] commit_cnt;     // # insts commited this cycle
    logic [1:0] alloc_cnt;      // # insts allocated this cycle

    //-------------------------------------------------------------
    // Pointer, Free Count, and Allocation Logic
    //-------------------------------------------------------------
    assign rob_alloc_gnt[0] = rob_alloc_req[0] && (avail_slots >= 1);
    assign rob_alloc_gnt[1] = rob_alloc_req[1] && ((rob_alloc_req[0])? (avail_slots >= 2) : avail_slots >= 1);
    assign alloc_cnt = rob_we;
    always_ff @(posedge clk) begin // Pointer register logic
        if (rst || flush) { head <= '0; tail <= '0; }
        else { head <= head_next; tail <= tail_next; }
    end
    always_comb begin // avail_slots calculation
        if (head == tail) {
            avail_slots = (head[PTR_WIDTH] == tail[PTR_WIDTH]) ? DEPTH : 0;
        } else if (tail > head) {
            avail_slots = DEPTH - (tail - head);
        } else {
            avail_slots = head - tail;
        }
    end
    assign rob_rdy[0] = (avail_slots >= 1);
    assign rob_rdy[1] = (avail_slots >= 2);
    assign rob_tag0 = tail[PTR_WIDTH-1:0];
    assign rob_tag1 = (tail+1)[PTR_WIDTH-1:0];
    assign rob_head = head[PTR_WIDTH-1:0];
    assign rob_tail = tail[PTR_WIDTH-1:0];

    //-------------------------------------------------------------
    // Allocation Logic (Write entries from Dispatch)
    //-------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            for (int i = 0; i < ROB_ENTRIES; i++) rob_entries[i].is_valid <= 1'b0;
        end else begin
            if (rob_we[0]) rob_entries[rob_tag0] <= rob_entry0;
            if (rob_we[1]) rob_entries[rob_tag1] <= rob_entry1;
        end
    end

    //-------------------------------------------------------------
    // Writeback Logic (Update entries from CDB)
    //-------------------------------------------------------------
    function automatic rob_entry_t cdb_snoop (
        input rob_entry_t           curr_entry,
        input writeback_packet_t    wb_packet,
        input logic [TAG_WIDTH-1:0] entry_tag
    );
        rob_entry_t updated_entry = curr_entry;
        if (wb_packet.is_valid && (wb_packet.dest_tag == entry_tag) && curr_entry.is_valid) begin
            updated_entry.is_ready      = 1'b1;
            updated_entry.result        = wb_packet.result; // Store raw result
            updated_entry.has_exception = wb_packet.is_exception;
        end
        return updated_entry;
    endfunction

    always_comb begin
        rob_entry_t entry_after_cdb0;
        for (int i = 0; i < ROB_ENTRIES; i++) begin
            entry_after_cdb0    = cdb_snoop(rob_entries[i], cdb_port0, i[TAG_WIDTH-1:0]);
            rob_entries_next[i] = cdb_snoop(entry_after_cdb0, cdb_port1, i[TAG_WIDTH-1:0]);
        end
    end
    
    always_ff @(posedge clk) begin
        if (!rst && !flush) begin
            for (int i = 0; i < ROB_ENTRIES; i++) begin
                logic is_committed0 = (commit_cnt >= 1) && (i == head[PTR_WIDTH-1:0]);
                logic is_committed1 = (commit_cnt >= 2) && (i == (head+1)[PTR_WIDTH-1:0]);
                if (rob_entries[i].is_valid && !is_committed0 && !is_committed1) begin
                rob_entries[i] <= rob_entries_next[i];
                end else if (is_committed0 || is_committed1) begin
                    rob_entries[i].is_valid <= 1'b0;
                end
            end
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
        logic [TAG_WIDTH-1:0]       commit_store_id;
        logic                       commit_store_val;
    } commit_info_t;

    function automatic commit_info_t proc_commit(input logic [PTR_WIDTH-1:0] ptr);
        commit_info_t info = '{default:'0};
        rob_entry_t entry = rob_entries[ptr];
        
        logic handshake = entry.is_ready && entry.is_valid;
        logic has_exception = handshake && entry.is_exception;
        logic is_mispredict = handshake && (entry.is_branch && entry.result[0]);
        logic is_jump = handshake &&  entry.is_jump;

        info.do_flush = has_exception || is_mispredict || is_jump;
        info.do_commmit = !has_exception && !is_mispredict; // Jumps need commit to link

        if (info.do_commmit) begin 
            // Commit Info
            info.prf_commit.addr    = entry.rd;
            info.prf_commit.result  = (entry.is_jump)? entry.pc+4 : entry.result;
            info.prf_commit.tag     = ptr;
            info.prf_commit.we      = entry.has_rd;

            // LSQ Commit Info
            info.commit_store_id    = ptr;
            info.commit_store_val   = entry.is_store;
        end

        if (has_exception) begin
            info.redirect_pc = 'x; // TODO: Exception Handler PC
        end else begin
            info.redirect_pc = {entry.result[31:1], 1'b0};
        end

        return info;
    endfunction

    commit_info_t commit0_info, commit1_info;

    assign commit0_info = proc_commit(head[PTR_WIDTH-1:0]);
    // Only process second candidate if first doesnt flush
    assign commit1_info = commit0_info.do_flush? '{default:'0} : proc_commit((head + 1)[PTR_WIDTH-1:0]);

    always_comb begin
        rob_pc  = '0;
        flush   = 1'b0;
        commit_0_write_port = '{default:'0};
        commit_1_write_port = '{default:'0};
        commit_store_id0    = '0;
        commit_store_id1    = '0;
        commit_store_val0   = 1'b0;
        commit_store_val1   = 1'b0;
        commit_cnt          = '0;

        if (commit0_info.do_flush) begin
            rob_pc  = commit0_info.redirect_pc;
            flush   = 1'b1;
        end else if (commit1_info.do_flush) begin
            rob_pc  = commit1_info.redirect_pc;
            flush   = 1'b1;
        end

        if (commit0_info.do_commmit) begin
            commit_cnt = 2'd1;
            commit_0_write_port = commit0_info.prf_commit;
            commit_store_id0    = commit0_info.commit_store_id;
            commit_store_val0   = commit0_info.commit_store_val;
        end
        if (commit1_info.do_commmit) begin
            commit_cnt = 2'd2;
            commit_1_write_port = commit1_info.prf_commit;
            commit_store_id1    = commit1_info.commit_store_id;
            commit_store_val1   = commit1_info.commit_store_val;
        end
    end

endmodule