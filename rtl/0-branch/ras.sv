import riscv_isa_pkg::*;
import uarch_pkg::*;

module ras #(
    parameter DEPTH = 16
)(
    input  logic clk, rst,

    // Push/Pop (speculative)
    input  logic                        push,
    input  logic                        pop,
    input  logic [CPU_ADDR_BITS-1:0]    push_addr,
    output logic [CPU_ADDR_BITS-1:0]    pop_addr,
    output logic                        push_rdy,
    output logic                        pop_rdy,

    // Checkpoint (save with branch in FTQ/ROB)
    output logic [$clog2(DEPTH):0]      ptr,

    // Recovery (on misprediction)
    input  logic                        recover,
    input  logic [$clog2(DEPTH):0]      recover_ptr
);
    localparam PTR_WIDTH = $clog2(DEPTH);

    // Stack storage
    logic [CPU_ADDR_BITS-1:0] stack [DEPTH-1:0];
    logic [PTR_WIDTH:0] ptr_r;

    //----------------------------------------------------------
    // Async Read
    //----------------------------------------------------------
    assign pop_addr = (ptr_r > 0) ? stack[ptr_r[PTR_WIDTH-1:0] - 1'b1] : '0;

    // Ready signals
    assign push_rdy = (ptr_r < DEPTH[PTR_WIDTH:0]);  // Can push if not full
    assign pop_rdy  = (ptr_r > 0);                    // Can pop if not empty
    assign ptr      = ptr_r;

    //----------------------------------------------------------
    // Sequential Write
    //----------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            ptr_r <= '0;
            for (int i = 0; i < DEPTH; i++) begin
                stack[i] <= '0;
            end
        end else if (recover) begin
            // Restore pointer to checkpointed state
            ptr_r <= recover_ptr;
        end else if (push) begin
            // Push only (CALL)
            if (ptr_r < DEPTH) begin
                stack[ptr_r[PTR_WIDTH-1:0]] <= push_addr;
                ptr_r <= ptr_r + 1'b1;
            end
        end else if (pop) begin
            // Pop only (RET)
            if (ptr_r > 0) begin
                ptr_r <= ptr_r - 1'b1;
            end
        end
    end

endmodule
