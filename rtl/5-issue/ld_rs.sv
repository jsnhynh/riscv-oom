module ld_rs (
    input logic clk, rst, flush, cache_stall,
    // Ports from Displatch
    input instruction_t rs_entry,
    input bit rs_we,
    //Ports to Dispatch
    output bit rs_write_rdy,
    output bit rs_read_rdy,
    //Ports to Execute
    output  instruction_t execute_pkt,

    //Ports from Execute
    input logic alu_re,

    //Ports to AGU
    output bit agu_rs_read_rdy,
    input writeback_packet_t agu_port,
    //Ports for storeQ forwarding
    input instruction_t store_q [STORE_Q_ENTRIES - 1 : 0],
    output writeback_packet_t forwarded_pkt,
    output forward_read_rdy,
    input forward_re, //forward read enable

    //CDB PORT 
    input writeback_packet_t cdb_ports [PIPE_WIDTH - 1 : 0]
);

bit temp_rs_write_rdy;
bit temp_rs_read_rdy;
instruction_t muxed_rs_entry, agu_rs_entry;
rs rs (
    .clk(clk), 
    .rst(rst), 
    .flush(flush), 
    .cache_stall(cache_stall),
    // Ports from Displatch
    .rs_entry(muxed_rs_entry),
    .rs_we(rs_we || agu_we),
    //Ports to Dispatch
    .rs_write_rdy(temp_rs_write_rdy),
    //when rs is ready to be read, it is when all REGISTER values are accounted for
    //but agu operation has not been complete
    .rs_read_rdy(agu_rs_read_rdy), 
    //Ports to Execute
    .execute_pkt(execute_pkt),

    //Ports from Execute
    .alu_re(mem_re || agu_we),

    //CDB PORT 
    .cdb_ports(cdb_ports)
);
assign agu_we = agu_port.is_valid && agu_port.dest_tag == execute_pkt.dest_tag;
assign muxed_rs_entry = agu_we ? rs_entry : agu_rs_entry;
always_comb begin
    agu_rs_entry = execute_pkt;
    agu_rs_entry.src_0_a.data = agu_port.result;
end

typedef enum logic [2:0] {
    IDLE,
    WAIT_AGU,      
} state_t;
state_t state, next_state;

always_ff @( posedge clk ) begin
    if(rst) state <= IDLE;
    else state <= NEXT_STATE;
end
//when the rs is empty LD_RS_write_rdy should b high
//when alu_re or forward_re are set high then LD_RS_write_ready should be high as well

//when rs_read_rdy is high, AGU_RS_read_rdy is high, since the rs module does not know about agu

//when we get something over the agu_port then, either we need to shuffle the RS with the recieved value
//or we store the value elsewhere, shuffling makes the most sense


endmodule