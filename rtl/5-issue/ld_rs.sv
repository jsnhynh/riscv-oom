module lsq_rs
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

    //Forwarding ports, super high cost
    //in the future maybe switch to an address buffer, or with a fast l1 cache maybe j remove forwarding?
    //compiler can deal with it, doesn't feel worth
    input instruction_t store_q [STQ_DEPTH],
    input logic forward_re,
    output writeback_packet_t forward_pkt,
    output logic forward_rdy,
    //rob_head
    input  logic [TAG_WIDTH-1:0]    rob_head
);
instruction_t fwd_entry;
logic forward_match;
logic base_rs_write_rdy, base_rs_read_rdy, agu_we, man_flush, fwd_we;
instruction_t muxed_rs_entry, agu_rs_entry;
rs rs (
    .clk(clk), 
    .rst(rst), 
    .flush(flush || man_flush), 
    .cache_stall(cache_stall),
    // Ports from Displatch
    .rs_entry(muxed_rs_entry),
    .rs_we(rs_we || agu_we || fwd_we),
    //Ports to Dispatch
    .rs_write_rdy(base_rs_write_rdy),
    //when rs is ready to be read, it is when all REGISTER values are accounted for
    //but agu operation has not been complete
    .rs_read_rdy(base_rs_read_rdy), 
    //Ports to Execute
    .execute_pkt(execute_pkt),

    //Ports from Execute
    .alu_re(alu_re || agu_we || fwd_we),

    //CDB PORT 
    .cdb_ports(cdb_ports)
);
    assign agu_we = agu_port.is_valid && agu_port.dest_tag == execute_pkt.dest_tag;
    //muxed_rs_entry = '0;
    // case ({rs_we, agu_we, fwd_we})
    //     3'b100: muxed_rs_entry = rs_entry;
    //     3'b010: muxed_rs_entry = agu_rs_entry;
    //     3'b001: muxed_rs_entry = fwd_entry; 
    //     default: muxed_rs_entry = rs_entry;
    // endcase
    always_comb begin
        if(rs_we) muxed_rs_entry = rs_entry;
        else if (agu_we) muxed_rs_entry = agu_rs_entry;
        else if (fwd_we) muxed_rs_entry = fwd_entry;
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
    forward_rdy = 1'b0;
    fwd_we = 1'b0;
    case (state)
        IDLE : begin
            if(base_rs_write_rdy) rs_write_rdy = 1'b1;
            if(rs_we) next_state = WAIT_REG;
            else next_state = IDLE;
        end 
        WAIT_REG : begin
            if(base_rs_read_rdy)begin
                 agu_read_rdy = 1'b1;
                next_state = WAIT_AGU;
            end
            else next_state = WAIT_REG;
        end
        WAIT_AGU : begin
            agu_read_rdy = 1'b1;
            if(agu_we) begin
                 next_state = VALID_ENTRY;
            end
            else next_state = WAIT_AGU;
        end
        VALID_ENTRY : begin
            if(forward_match) begin
                fwd_we = 1'b1;
                next_state = FWD_ENTRY;
            end
            else begin
                rs_read_rdy = 1'b1;
                if(alu_re) begin
                    rs_write_rdy = 1'b1;
                    if(rs_we) next_state = WAIT_REG;
                    else begin
                        man_flush = 1'b1;
                        next_state = IDLE;
                    end
                end
                else next_state = VALID_ENTRY;
            end
        end
        FWD_ENTRY : begin
            forward_rdy = 1'b1;
            if(forward_re) begin
                if(rs_we) next_state = WAIT_REG;
                else
                next_state = IDLE;
            end
        end
    endcase
end

//something aint right here
function instruction_t find_fwd();
    instruction_t out;
    out = '0;
    foreach(store_q[i]) begin
        if(store_q[i].dest_tag - rob_head < execute_pkt - rob_head) begin
            if(store_q[i].src_0_a.data == execute_pkt.src_0_a.data) out = store_q[i];
        end
    end
    return out;
endfunction

instruction_t ff;
always_comb begin 
    fwd_entry = execute_pkt;
    ff = find_fwd();
    if(ff != 0) begin
        forward_match = 1'b1;
        fwd_entry.src_0_a = ff.src_1_b;
    end
    else forward_match = 1'b0;

    forward_pkt.dest_tag = execute_pkt.dest_tag;
    forward_pkt.exception = 1'b0;
    forward_pkt.is_valid = forward_rdy;
    forward_pkt.result = execute_pkt.src_0_a;
end


endmodule