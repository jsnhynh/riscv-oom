/*
 * Generic Reservation Station (N inputs × M outputs)
 * 
 * Option 2: Wakeup-to-issue takes 1 cycle (simpler timing)
 */

import riscv_isa_pkg::*;
import uarch_pkg::*;

module reservation_station #(
    parameter int NUM_ENTRIES = 8,
    parameter int ISSUE_WIDTH = 2
) (
    input  logic clk, rst, flush,
    
    // Dispatch Interface
    output logic [PIPE_WIDTH-1:0]   rs_rdy,
    input  logic [PIPE_WIDTH-1:0]   rs_we,
    input  instruction_t            rs_entries_in [PIPE_WIDTH-1:0],
    
    // Issue Interface
    input  logic [ISSUE_WIDTH-1:0]  fu_rdy,
    output instruction_t            fu_packets [ISSUE_WIDTH-1:0],
    
    // Wakeup Interface
    input  writeback_packet_t       cdb_ports [PIPE_WIDTH-1:0],
    
    // Age tracking
    input  logic [TAG_WIDTH-1:0]    rob_head
);

    //-------------------------------------------------------------
    // RS Entries
    //-------------------------------------------------------------
    instruction_t entries      [NUM_ENTRIES-1:0];
    instruction_t entries_next [NUM_ENTRIES-1:0];

    //-------------------------------------------------------------
    // Allocation Logic
    //-------------------------------------------------------------
    logic [NUM_ENTRIES-1:0] entry_free;
    logic [PIPE_WIDTH-1:0] can_allocate;
    int alloc_indices [PIPE_WIDTH-1:0];

    // Entry is free if: (1) currently invalid, OR (2) being issued this cycle
    always_comb begin
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            entry_free[i] = ~entries[i].is_valid || issue_grants[i];
        end
    end

    always_comb begin
        automatic logic [NUM_ENTRIES-1:0] used_mask = '0;
        
        for (int d = 0; d < PIPE_WIDTH; d++) begin
            alloc_indices[d] = -1;
            can_allocate[d] = 0;
            
            for (int e = 0; e < NUM_ENTRIES; e++) begin
                if (entry_free[e] && !used_mask[e]) begin
                    alloc_indices[d] = e;
                    can_allocate[d] = 1;
                    used_mask[e] = 1;
                    break;
                end
            end
        end
    end

always_comb begin
    for (int d = 0; d < PIPE_WIDTH; d++) begin
        rs_rdy[d] = can_allocate[d];
    end
end

    //-------------------------------------------------------------
    // Wakeup Logic (Check if source is ready - NO CDB forwarding)
    //-------------------------------------------------------------
    logic [NUM_ENTRIES-1:0] entry_ready;
    
    always_comb begin
        for (int e = 0; e < NUM_ENTRIES; e++) begin
            entry_ready[e] = entries[e].is_valid &&
                            (~entries[e].src_0_a.is_renamed) &&
                            (~entries[e].src_0_b.is_renamed) &&
                            (~entries[e].src_1_a.is_renamed) &&
                            (~entries[e].src_1_b.is_renamed);
        end
    end

    //-------------------------------------------------------------
    // Age Calculation
    //-------------------------------------------------------------
    logic [TAG_WIDTH-1:0] entry_ages [NUM_ENTRIES-1:0];
    
    always_comb begin
        for (int e = 0; e < NUM_ENTRIES; e++) begin
            entry_ages[e] = entries[e].dest_tag - rob_head;
        end
    end

    //-------------------------------------------------------------
    // Issue Selection
    //-------------------------------------------------------------
    logic [NUM_ENTRIES-1:0] issue_grants;
    int issue_indices [ISSUE_WIDTH-1:0];
    
    always_comb begin
        automatic logic [NUM_ENTRIES-1:0] used_mask = '0;
        issue_grants = '0;
        
        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            automatic int oldest_idx = -1;
            automatic logic [TAG_WIDTH-1:0] oldest_age = '1;
            
            issue_indices[i] = -1;
            
            for (int e = 0; e < NUM_ENTRIES; e++) begin
                if (entry_ready[e] && !used_mask[e] && fu_rdy[i]) begin
                    if (entry_ages[e] < oldest_age) begin
                        oldest_age = entry_ages[e];
                        oldest_idx = e;
                    end
                end
            end
            
            if (oldest_idx >= 0) begin
                issue_grants[oldest_idx] = 1'b1;
                issue_indices[i] = oldest_idx;
                used_mask[oldest_idx] = 1'b1;
            end
        end
    end
    
    // Issue outputs - read from stable entries array (simpler!)
    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            if (issue_indices[i] >= 0) begin
                fu_packets[i] = entries[issue_indices[i]];  // Read from entries
            end else begin
                fu_packets[i] = '{default: '0};
            end
        end
    end

    //-------------------------------------------------------------
    // Data Capture from CDB
    //-------------------------------------------------------------
    
    function automatic source_t update_source(input source_t src);
        source_t result = src;
        
        // If not renamed or already has data, don't update
        if (!src.is_renamed) return result;
        
        // Check CDB ports for data
        for (int c = 0; c < PIPE_WIDTH; c++) begin
            if (cdb_ports[c].is_valid && cdb_ports[c].dest_tag == src.tag) begin
                result.data = cdb_ports[c].result;
                result.is_renamed = '0;
            end
        end
        
        return result;
    endfunction

    //-------------------------------------------------------------
    // RS Update Logic
    //-------------------------------------------------------------
    always_comb begin
        entries_next = entries;
        
        // Step 1: Allocate new entries
        for (int d = 0; d < PIPE_WIDTH; d++) begin
            if (rs_we[d] && can_allocate[d] && alloc_indices[d] >= 0) begin
                int idx = alloc_indices[d];
                entries_next[idx] = rs_entries_in[d];
            end
        end
        
        // Step 2: Wakeup and capture data for all entries
        for (int e = 0; e < NUM_ENTRIES; e++) begin
            if (entries_next[e].is_valid) begin
                entries_next[e].src_0_a = update_source(entries_next[e].src_0_a);
                entries_next[e].src_0_b = update_source(entries_next[e].src_0_b);
                entries_next[e].src_1_a = update_source(entries_next[e].src_1_a);
                entries_next[e].src_1_b = update_source(entries_next[e].src_1_b);
            end
        end
        
        // Step 3: Clear issued entries (unless being re-allocated)
        for (int e = 0; e < NUM_ENTRIES; e++) begin
            if (issue_grants[e]) begin
                // Check if this entry is being re-allocated this cycle
                automatic logic being_allocated = 0;
                for (int d = 0; d < PIPE_WIDTH; d++) begin
                    if (rs_we[d] && can_allocate[d] && alloc_indices[d] == e) begin
                        being_allocated = 1;
                    end
                end
                
                // Only clear if NOT being re-allocated
                if (!being_allocated) begin
                    entries_next[e] = '{default:'x};
                    entries_next[e].is_valid = 1'b0;
                end
            end
        end
    end

    //-------------------------------------------------------------
    // Sequential Logic
    //-------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            for (int e = 0; e < NUM_ENTRIES; e++) begin
                entries[e] <= '{default: 'x};
                entries[e].is_valid <= '0;
            end
        end else begin
            entries <= entries_next;
        end
    end

endmodule