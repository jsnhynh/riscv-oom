module lsq_rs (
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
    output logic forward_rdy
    
);

bit base_rs_write_rdy, base_rs_read_rdy, agu_we, alu_re, man_flush, fwd_we;
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
always_comb begin
    agu_we = agu_port.is_valid && agu_port.dest_tag == execute_pkt.dest_tag;
    case ({rs_we, agu_we, fwd_we})
        3'b100: muxed_rs_entry = rs_entry;
        3'b010: muxed_rs_entry = agu_rs_entry;
        3'b001: muxed_rs_entry = fwd_entry; 
        default: muxed_rs_entry = rs_entry;
    endcase
    agu_execute_pkt = execute_pkt;
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
    else state <= NEXT_STATE;
end

always_comb begin
    rs_write_rdy = 1'b0;
    rs_read_rdy = 1'b0;
    agu_read_rdy = 1'b0;
    man_flush = 1'b1; 
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
                else next_state = IDLE;
            end
        end
    endcase
end

logic [$clog2(STQ_DEPTH) : 0] forward_match_indx;
logic forward_match;
always_comb begin 
    foreach(store_q[i]) begin
        if(store_q[i].agu_comp && (store_q[i].src_0_a.data == execute_pkt.src_0_a.data) && store_q[i].agu_comp)begin
             forward_match_index = i;
             forward_match = 1'b1;
             break;
        end
        else begin
            forward_match = 1'b0;
            forward_match_index = 1'b0;
        end
    end
    fwd_entry = execute_pkt;
    fwd_entry.src_0_a = store_q[forward_match_index].src_0_a;
    
    forward_pkt.dest_tag = execute_pkt.dest_tag;
    forward_pkt.exception = 1'b0;
    forward_pkt.is_valid = forward_rdy;
    forward_pkt.result = execute_pkt.src_0_a;
end


endmodule