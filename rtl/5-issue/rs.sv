module rs (
    input logic clk, rst, flush, cache_stall,
    // Ports from Displatch
    input renamed_inst_t rs_entry,
    //Ports to Dispatch
    output logic rs_rdy,

    //Ports to Execute
    output  execute_packet_t execute_pkt,

    //Ports from Execute
    input logic alu_re,

    //CDB PORT 
    input writeback_packet_t cdb_port0, cdb_port1
);

    bit rs1_data_in_cdb0, rs2_data_in_cdb0, rs1_data_in_cdb1, rs2_data_in_cdb1;
    assign rs1_data_in_cdb0 = rs_entry_ff.rs1_renamed && (cdb_port0.is_valid && (cdb_port0.dest_tag == rs_entry_ff.rs1_tag));
    assign rs2_data_in_cdb0 = rs_entry_ff.rs2_renamed && (cdb_port0.is_valid && (cdb_port0.dest_tag == rs_entry_ff.rs2_tag));
    assign rs1_data_in_cdb1 = rs_entry_ff.rs1_renamed && (cdb_port1.is_valid && (cdb_port1.dest_tag == rs_entry_ff.rs1_tag));
    assign rs2_data_in_cdb1 = rs_entry_ff.rs2_renamed && (cdb_port1.is_valid && (cdb_port1.dest_tag == rs_entry_ff.rs2_tag));
    //rs_entry register
    renamed_inst_t rs_entry_ff;
    always_ff @( posedge clk ) begin 
        if (rst || flush) rs_entry_ff <= '0;
        else begin //updating rs reg with new value
            if(rs_entry.is_valid && rs_rdy && !cache_stall) rs_entry_ff <= rs_entry;
            else begin //updating rs reg with cdb port
                if(rs1_data_in_cdb0 || rs1_data_in_cdb1) rs_entry_ff.rs1_renamed <= 1'b0;
                if(rs2_data_in_cdb0 || rs2_data_in_cdb1) rs_entry_ff.rs2_renamed <= 1'b0;
                if(rs1_data_in_cdb0) rs_entry_ff.rs1_data <= cdb_port0.result;
                else if (rs1_data_in_cdb1) rs_entry_ff.rs1_data <= cdb_port1.result;
                if(rs2_data_in_cdb0) rs_entry_ff.rs2_data <= cdb_port0.result;
                else if (rs2_data_in_cdb1) rs_entry_ff.rs2_data <= cdb_port1.result;
            end
        end
    end

    always_comb begin 
        execute_pkt.dest_tag = rs_entry_ff.dest_tag;
        execute_pkt.operand_a = ?;
        execute_pkt.operand_b = ?;
        execute_pkt.uop = rs_entry_ff.uop;
        execute_pkt.is_branch = rs_entry_ff.is_branch;
        execute_pkt.uop_br = rs_entry_ff.uop_br;
        execute_pkt.rs1_data = rs_entry_ff.rs1_data;
        execute_pkt.rs2_data = rs_entry_ff.rs2_data;
        execute_pkt.is_load = rs_entry_ff.is_load;
        execute_pkt.is_store = rs_entry_ff.is_store;
        execute_pkt.store_data = ?;
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
            if(rs_entry.is_valid) begin
                if( !rs_entry_ff.rs1_renamed &&  !rs_entry_ff.rs2_renamed && alu_re) begin
                    next_state = PASS_THRU;
                    valid_nxt = 1'b1; 
                    rs_rdy = 1'b1;
                end
                else next_state = STALLED;
            end
            else rs_entry.is_valid = 1'b1;
        end 
        STALLED: begin
            if(!rs_entry_ff.rs1_renamed && !rs_entry_ff.rs2_renamed && alu_re) begin
                next_state = PASS_THRU;
                valid_nxt = 1'b1;
                rs_rdy = 1'b1;
            end
            else next_state = STALLED;
        end
    endcase
end



endmodule