// -----------------------------------------------------------------------------
// FIFO (single clock) — FWFT only (show-ahead + bypass)
//  - Ready/valid handshakes
//  - First-word fall-through via combinational deq_data
//  - Empty-cycle bypass: if empty & enq_valid & deq_ready, data passes through
//  - Safe push/pop on same cycle; full handled with pop opening space
// -----------------------------------------------------------------------------
module fifo_fwft #(
  parameter int DATA_W  = 32,
  parameter int DEPTH   = 16,                 // >= 2
  localparam int ADDR_W = $clog2(DEPTH)
) (
  input  logic              clk,
  input  logic              rst_n,            // async active-low reset

  // Enqueue (producer)
  input  logic              enq_valid,
  output logic              enq_ready,
  input  logic [DATA_W-1:0] enq_data,

  // Dequeue (consumer)
  output logic              deq_valid,
  input  logic              deq_ready,
  output logic [DATA_W-1:0] deq_data,

  // Status
  output logic              empty,
  output logic              full,
  output logic [ADDR_W:0]   level
);

  // Storage
  logic [DATA_W-1:0] mem [DEPTH];
  logic [ADDR_W-1:0] rd_ptr, wr_ptr;
  logic [ADDR_W:0]   count;

  // Basic status
  assign empty = (count == 0);
  assign full  = (count == DEPTH);
  assign level = count;

  // Show-ahead + bypass interface signals
  // - enq_ready: can accept if not full, OR if consumer pops this cycle (space opens)
  // - deq_valid: data is available if not empty, OR producer presents data when empty
  assign enq_ready = !full || (deq_ready && !empty);
  assign deq_valid = !empty || enq_valid;

  // Bypass occurs when FIFO is empty and both sides handshake this cycle
  wire bypass = empty & enq_valid & deq_ready;

  // Show-ahead (FWFT) data: when empty, expose enq_data; else head word
  assign deq_data = empty ? enq_data : mem[rd_ptr];

  // Determine actual memory push/pop operations (exclude bypass)
  wire push_mem = enq_valid & enq_ready & ~bypass;      // write into mem this cycle
  wire pop_mem  = deq_ready & deq_valid & ~empty;       // read/advance from mem

  // Write pointer and memory
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
    end else if (push_mem) begin
      mem[wr_ptr] <= enq_data;
      wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : (wr_ptr + 1'b1);
    end
  end

  // Read pointer
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_ptr <= '0;
    end else if (pop_mem) begin
      rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : (rd_ptr + 1'b1);
    end
  end

  // Count (level). Note: bypass keeps count at 0.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count <= '0;
    end else begin
      unique case ({push_mem, pop_mem})
        2'b10: if (!full)  count <= count + 1'b1;
        2'b01: if (!empty) count <= count - 1'b1;
        default: /* 00 or 11: no change */ ;
      endcase
    end
  end

  
endmodule
