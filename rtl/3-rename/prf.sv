import riscv_isa_pkg::*;
import uarch_pkg::*;

module prf (
    // Module I/O
    input logic clk, rst, flush,

    //-------------------------------------------------------------
    // RENAME STAGE PORTS (4 READ, 2 TAG WRITE)
    //-------------------------------------------------------------
    // Read Ports for Instruction 0
    input  logic [$clog2(ARCH_REGS)-1:0]    rs1_0,              rs2_0,
    output source_t                         rs1_0_read_port,    rs2_0_read_port,

    // Read Ports for Instruction 1
    input  logic [$clog2(ARCH_REGS)-1:0]    rs1_1,              rs2_1,
    output source_t                         rs1_1_read_port,    rs2_1_read_port,

    // Tag Write Ports
    input  prf_rat_write_port_t             rat_0_write_port,   rat_1_write_port,

    //-------------------------------------------------------------
    // COMMIT STAGE PORTS (2 DATA WRITE)
    //-------------------------------------------------------------
    input  prf_commit_write_port_t          commit_0_write_port, commit_1_write_port
);

    // Internal storage for the PRF
    logic [CPU_DATA_BITS-1:0]   data_reg    [ARCH_REGS-1:0];
    logic [TAG_WIDTH-1:0]       tag_reg     [ARCH_REGS-1:0];
    logic                       renamed_reg [ARCH_REGS-1:0];

    //-------------------------------------------------------------
    // READ LOGIC (Asynchronous)
    //-------------------------------------------------------------
    assign rs1_0_read_port = '{data: data_reg[rs1_0], tag: tag_reg[rs1_0], is_renamed: renamed_reg[rs1_0]};
    assign rs2_0_read_port = '{data: data_reg[rs2_0], tag: tag_reg[rs2_0], is_renamed: renamed_reg[rs2_0]};
    assign rs1_1_read_port = '{data: data_reg[rs1_1], tag: tag_reg[rs1_1], is_renamed: renamed_reg[rs1_1]};
    assign rs2_1_read_port = '{data: data_reg[rs2_1], tag: tag_reg[rs2_1], is_renamed: renamed_reg[rs2_1]};

    //-------------------------------------------------------------
    // WRITE LOGIC (Synchronous)
    //-------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < ARCH_REGS; i++) begin
                data_reg[i]    <= '0;
                renamed_reg[i] <= '0;
                tag_reg[i]     <= '0;
            end
        end else if (flush) begin
            for (int i = 0; i < ARCH_REGS; i++) begin
                renamed_reg[i] <= 1'b0;
            end
        end else begin
            // --- Commit Stage Writes ---
            if (commit_0_write_port.we && commit_0_write_port.addr != 0) begin
                data_reg[commit_0_write_port.addr] <= commit_0_write_port.data;
                if (renamed_reg[commit_0_write_port.addr] && (tag_reg[commit_0_write_port.addr] == commit_0_write_port.tag)) begin
                    renamed_reg[commit_0_write_port.addr] <= 1'b0;
                end
            end
            
            if (commit_1_write_port.we && commit_1_write_port.addr != 0) begin
                data_reg[commit_1_write_port.addr] <= commit_1_write_port.data;
                if (renamed_reg[commit_1_write_port.addr] && (tag_reg[commit_1_write_port.addr] == commit_1_write_port.tag)) begin
                    renamed_reg[commit_1_write_port.addr] <= 1'b0;
                end
            end

            // --- Rename Stage Writes ---
            if (rat_0_write_port.we && rat_0_write_port.addr != 0) begin
                tag_reg[rat_0_write_port.addr]     <= rat_0_write_port.tag;
                renamed_reg[rat_0_write_port.addr] <= 1'b1;
            end

            if (rat_1_write_port.we && rat_1_write_port.addr != 0) begin
                tag_reg[rat_1_write_port.addr]     <= rat_1_write_port.tag;
                renamed_reg[rat_1_write_port.addr] <= 1'b1;
            end
        end
    end

endmodule

