module rs (
    input logic clk, rst, flush, cache_stall,
    // Ports from Displatch
    input instruction_t rs_entry,
    input bit rs_we,
    //Ports to Dispatch
    output logic rs_rdy,

    //Ports to Execute
    output  instruction_t execute_pkt,

    //Ports from Execute
    input logic alu_re,

    //CDB PORT 
    input writeback_packet_t cdb_port0, cdb_port1
);

    bit src_0_a_data_in_cdb0, src_0_b_data_in_cdb0, src_0_a_data_in_cdb1, src_0_b_data_in_cdb1;
    bit src_1_a_data_in_cdb0, src_1_b_data_in_cdb0, src_1_a_data_in_cdb1, src_1_b_data_in_cdb1;
    
    assign src_0_a_data_in_cdb0 = execute_pkt.src_0_a.is_renamed && (cdb_port0.is_valid && (cdb_port0.dest_tag == execute_pkt.src_0_a.tag));
    assign src_0_b_data_in_cdb0 = execute_pkt.src_0_b.is_renamed && (cdb_port0.is_valid && (cdb_port0.dest_tag == execute_pkt.src_0_b.tag));
    assign src_0_a_data_in_cdb1 = execute_pkt.src_0_a.is_renamed && (cdb_port1.is_valid && (cdb_port1.dest_tag == execute_pkt.src_0_a.tag));
    assign src_0_b_data_in_cdb1 = execute_pkt.src_0_b.is_renamed && (cdb_port1.is_valid && (cdb_port1.dest_tag == execute_pkt.src_0_b.tag));
    
    assign src_1_a_data_in_cdb0 = execute_pkt.src_1_a.is_renamed && (cdb_port0.is_valid && (cdb_port0.dest_tag == execute_pkt.src_1_a.tag));
    assign src_1_b_data_in_cdb0 = execute_pkt.src_1_b.is_renamed && (cdb_port0.is_valid && (cdb_port0.dest_tag == execute_pkt.src_1_b.tag));
    assign src_1_a_data_in_cdb1 = execute_pkt.src_1_a.is_renamed && (cdb_port1.is_valid && (cdb_port1.dest_tag == execute_pkt.src_1_a.tag));
    assign src_1_b_data_in_cdb1 = execute_pkt.src_1_b.is_renamed && (cdb_port1.is_valid && (cdb_port1.dest_tag == execute_pkt.src_1_b.tag));

    //rs_entry register
    always_ff @( posedge clk ) begin 
        if (rst || flush) execute_pkt <= '0;
        else begin //updating rs reg with new value
            if(rs_entry.is_valid && rs_rdy && !cache_stall && rs_we) execute_pkt <= rs_entry;
            else begin //updating rs reg with cdb port
                if(src_0_a_data_in_cdb0 || src_0_a_data_in_cdb1) execute_pkt.src_0_a_renamed <= 1'b0;
                if(src_0_b_data_in_cdb0 || src_0_b_data_in_cdb1) execute_pkt.src_0_b_renamed <= 1'b0;
                if(src_1_a_data_in_cdb0 || src_1_a_data_in_cdb1) execute_pkt.src_1_a_renamed <= 1'b0;
                if(src_1_b_data_in_cdb0 || src_1_b_data_in_cdb1) execute_pkt.src_1_b_renamed <= 1'b0;

                if      (src_0_a_data_in_cdb0) execute_pkt.src_0_a.data <= cdb_port0.result;
                else if (src_0_a_data_in_cdb1) execute_pkt.src_0_a.data <= cdb_port1.result;
                if      (src_0_b_data_in_cdb0) execute_pkt.src_0_b.data <= cdb_port0.result;
                else if (src_0_b_data_in_cdb1) execute_pkt.src_0_b.data <= cdb_port1.result;
                
                if      (src_1_a_data_in_cdb0) execute_pkt.src_1_a.data <= cdb_port0.result;
                else if (src_1_a_data_in_cdb1) execute_pkt.src_1_a.data <= cdb_port1.result;
                if      (src_1_b_data_in_cdb0) execute_pkt.src_1_b.data <= cdb_port0.result;
                else if (src_1_b_data_in_cdb1) execute_pkt.src_1_b.data <= cdb_port1.result;
            end
        end
    end


typedef enum bit {PASS_THRU, STALLED} rs_state_e;
rs_state_e state, nxt_state;
bit valid_nxt; 
always_ff @( posedge clock ) begin 
    if(rst || flush) begin 
        state <= PASS_THRU;
        execute_pkt.is_valid <= 1'b0;
    end
    else begin
        state <= next_state;
        execute_pkt.is_valid <= valid_nxt;
    end
end
always_comb begin
    valid_nxt = 1'b0;
    rs_rdy = 1'b0;
    case (state)
        PASS_THRU: begin
            if(rs_entry.is_valid && rs_we) begin
                if( !execute_pkt.src_0_a_renamed &&  !execute_pkt.src_0_b_renamed && alu_re) begin
                    next_state = PASS_THRU;
                    valid_nxt = 1'b1; 
                    rs_rdy = 1'b1;
                end
                else next_state = STALLED;
            end
            else rs_entry.is_valid = 1'b1;
        end 
        STALLED: begin
            if(!execute_pkt.src_0_a_renamed && !execute_pkt.src_0_b_renamed && alu_re) begin
                next_state = PASS_THRU;
                valid_nxt = 1'b1;
                rs_rdy = 1'b1;
            end
            else next_state = STALLED;
        end
    endcase
end



endmodule