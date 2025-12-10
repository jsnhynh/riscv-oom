module lsq_rs_st
import riscv_isa_pkg::*; 
import uarch_pkg::*;
 #(
    parameter STQ_DEPTH = 5
 )(
    input logic clk, rst, flush, cache_stall,
    // Ports from Displatch
    input instruction_t rs_entry,
    input logic rs_we,
    //Ports to Dispatch
    output logic rs_write_rdy,
    output logic rs_read_rdy,
    //Ports to Execute
    output  instruction_t execute_pkt,

    //Ports from Execute
    input logic alu_re,


    //CDB PORT 
    input writeback_packet_t cdb_ports [PIPE_WIDTH - 1 : 0],

    //Ports to AGU
    output logic agu_read_rdy,
    output instruction_t agu_execute_pkt,
    input writeback_packet_t agu_port,

    //ROB PERMISSION
    input  logic [TAG_WIDTH-1:0]    commit_store_ids    [PIPE_WIDTH-1:0],
    input  logic [PIPE_WIDTH-1:0]   commit_store_vals,
    //rob_head
    input  logic [TAG_WIDTH-1:0]    rob_head
);
//instruction_t fwd_entry;
logic rob_perm_grant, clear_p;
logic base_rs_write_rdy, base_rs_read_rdy, agu_we, man_flush;
instruction_t muxed_rs_entry, agu_rs_entry;
rs rs (
    .clk(clk), 
    .rst(rst), 
    .flush(flush || man_flush), 
    .cache_stall(cache_stall),
    // Ports from Displatch
    .rs_entry(muxed_rs_entry),
    .rs_we(rs_we || agu_we),
    //Ports to Dispatch
    .rs_write_rdy(base_rs_write_rdy),
    //when rs is ready to be read, it is when all REGISTER values are accounted for
    //but agu operation has not been complete
    .rs_read_rdy(base_rs_read_rdy), 
    //Ports to Execute
    .execute_pkt(execute_pkt),

    //Ports from Execute
    .alu_re(alu_re || agu_we),

    //CDB PORT 
    .cdb_ports(cdb_ports)
);
    assign agu_we = agu_port.is_valid && agu_port.dest_tag == execute_pkt.dest_tag;

    always_comb begin
        if(rs_we) muxed_rs_entry = rs_entry;
        else if (agu_we) muxed_rs_entry = agu_rs_entry;
        else muxed_rs_entry = '0;
    end
    assign agu_execute_pkt = execute_pkt;
    always_comb begin  
        agu_rs_entry = execute_pkt;
        agu_rs_entry.src_0_a.data = agu_port.result;
        agu_rs_entry.agu_comp = 1'b1;
    end
typedef enum logic [2:0] {
    IDLE,
    WAIT_REG,
    WAIT_AGU,      
    VALID_ENTRY,
    FWD_ENTRY
} state_t;
state_t state, next_state;

always_ff @( posedge clk ) begin
    if(rst) state <= IDLE;
    else state <= next_state;
end

always_comb begin
    rs_write_rdy = 1'b0;
    rs_read_rdy = 1'b0;
    agu_read_rdy = 1'b0;
    man_flush = 1'b0; 
    clear_p = 1'b0;
    case (state)
        IDLE : begin
            if(base_rs_write_rdy) rs_write_rdy = 1'b1;
            if(rs_we) next_state = WAIT_REG;
            else begin
                next_state = IDLE;
                clear_p = 1'b1;
            end
        end 
        WAIT_REG : begin
            if(base_rs_read_rdy)begin
                 agu_read_rdy = 1'b1;
                next_state = WAIT_AGU;
            end
            else next_state = WAIT_REG;
        end
        WAIT_AGU : begin
            
            if(agu_we) begin
                agu_read_rdy = 1'b0;
                 next_state = VALID_ENTRY;
            end
            else begin
                agu_read_rdy = 1'b1;
                next_state = WAIT_AGU;
            end
        end
        VALID_ENTRY : begin
            if(!rob_perm_grant) begin
                next_state = VALID_ENTRY;
            end
            else begin
                rs_read_rdy = 1'b1;
                if(alu_re) begin
                    rs_write_rdy = 1'b1;
                    clear_p = 1'b1;
                    if(rs_we) next_state = WAIT_REG;
                    else begin
                        man_flush = 1'b1;
                        next_state = IDLE;
                    end
                end
                else next_state = VALID_ENTRY;
            end
        end

    endcase
end

always_ff @ (posedge clk) begin
    if(rst || flush || clear_p) begin
        rob_perm_grant <= 1'b0;
    end
    else begin
            if((commit_store_vals[0] == 1'b1) && (commit_store_ids[0] == execute_pkt.dest_tag)) rob_perm_grant <= 1'b1;
            else if ((commit_store_vals[1] == 1'b1) && (commit_store_ids[1] == execute_pkt.dest_tag)) rob_perm_grant <= 1'b1;
    end
end


endmodule