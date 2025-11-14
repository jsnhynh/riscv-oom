module rs 
import riscv_isa_pkg::*; 
import uarch_pkg::*;
 (
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
    input writeback_packet_t cdb_ports [PIPE_WIDTH - 1 : 0]
);
    function  int oh_2_i (logic [PIPE_WIDTH-1:0] v);
        int o;
        o = -1;
        for (int i = 0; i < PIPE_WIDTH; i++) if (v[i]) o = i;
        return o;
    endfunction

    //ONE HOT encoded vector which says which  src_... is in if it is there at all
    logic [PIPE_WIDTH - 1 : 0] src_0_a_in_cdb, c0_src_0_a_in_cdb; 
    logic [PIPE_WIDTH - 1 : 0] src_0_b_in_cdb, c0_src_0_b_in_cdb;
    logic [PIPE_WIDTH - 1 : 0] src_1_a_in_cdb, c0_src_1_a_in_cdb;
    logic [PIPE_WIDTH - 1 : 0] src_1_b_in_cdb, c0_src_1_b_in_cdb;

    always_comb begin
        for(int i = 0; i < PIPE_WIDTH; i++) begin
            src_0_a_in_cdb[i] = execute_pkt.src_0_a.is_renamed && (cdb_ports[i].is_valid && (cdb_ports[i].dest_tag == execute_pkt.src_0_a.tag));
            src_0_b_in_cdb[i] = execute_pkt.src_0_b.is_renamed && (cdb_ports[i].is_valid && (cdb_ports[i].dest_tag == execute_pkt.src_0_b.tag));
            src_1_a_in_cdb[i] = execute_pkt.src_1_a.is_renamed && (cdb_ports[i].is_valid && (cdb_ports[i].dest_tag == execute_pkt.src_1_a.tag));
            src_1_b_in_cdb[i] = execute_pkt.src_1_b.is_renamed && (cdb_ports[i].is_valid && (cdb_ports[i].dest_tag == execute_pkt.src_1_b.tag));
            
            c0_src_0_a_in_cdb[i] = rs_entry.src_0_a.is_renamed && (cdb_ports[i].is_valid && (cdb_ports[i].dest_tag == rs_entry.src_0_a.tag));
            c0_src_0_b_in_cdb[i] = rs_entry.src_0_b.is_renamed && (cdb_ports[i].is_valid && (cdb_ports[i].dest_tag == rs_entry.src_0_b.tag));
            c0_src_1_a_in_cdb[i] = rs_entry.src_1_a.is_renamed && (cdb_ports[i].is_valid && (cdb_ports[i].dest_tag == rs_entry.src_1_a.tag));
            c0_src_1_b_in_cdb[i] = rs_entry.src_1_b.is_renamed && (cdb_ports[i].is_valid && (cdb_ports[i].dest_tag == rs_entry.src_1_b.tag));
        end
    end

    //rs_entry register

    always_ff @( posedge clk ) begin 
        if (rst || flush) execute_pkt <= '0;
        else begin //updating rs reg with new value
        //this deals with the edge case that the packet to be rewritten is on the output of dispatch
            if(rs_entry.is_valid && !cache_stall && rs_we && rs_write_rdy)begin
                //execute_pkt <= rs_entry;
                execute_pkt.pc <= rs_entry.pc;
                execute_pkt.rd <= rs_entry.rd;
                execute_pkt.dest_tag <= rs_entry.dest_tag;
                if(c0_src_0_a_in_cdb) begin
                    execute_pkt.src_0_a.data <= cdb_ports[oh_2_i(c0_src_0_a_in_cdb)].result;
                    execute_pkt.src_0_a.is_renamed <= 1'b0;
                end
                else execute_pkt.src_0_a <= rs_entry.src_0_a;    // a_sel? PC  : RS1
                if(c0_src_0_b_in_cdb) begin
                    execute_pkt.src_0_b.data <= cdb_ports[oh_2_i(c0_src_0_b_in_cdb)].result;
                    execute_pkt.src_0_b.is_renamed <= 1'b0;
                end
                else execute_pkt.src_0_b <= rs_entry.src_0_b;    // b_sel? IMM : RS2
                execute_pkt.uop_0 <= rs_entry.uop_0;      // Func3, replace with ADD for address generation
                if(c0_src_1_a_in_cdb) begin
                    execute_pkt.src_1_a.data <= cdb_ports[oh_2_i(c0_src_1_a_in_cdb)].result;
                    execute_pkt.src_1_a.is_renamed <= 1'b0;
                end
                else execute_pkt.src_1_a <= rs_entry.src_1_a;    // Always RS1 (For Branches)
                if(c0_src_1_b_in_cdb) begin
                    execute_pkt.src_1_b.data <= cdb_ports[oh_2_i(c0_src_1_b_in_cdb)].result;
                    execute_pkt.src_1_b.is_renamed <= 1'b0;
                end
                else execute_pkt.src_1_b <= rs_entry.src_1_b;    // Always RS2 (For Branches/Store_Data)

                execute_pkt.uop_1 <= rs_entry.uop_1;      // Func3, Used for Branch Operation, use ADD for uop_0
                execute_pkt.is_valid <= rs_entry.is_valid;
                execute_pkt.has_rd <= rs_entry.has_rd;
                execute_pkt.br_taken <= rs_entry.br_taken;         // Set to 1 if jump, can be later used for Branch Prediction
                execute_pkt.opcode <= rs_entry.opcode;
                execute_pkt.funct7 <= rs_entry.funct7;

            end
            else begin //updating rs reg with cdb port
                if(|src_0_a_in_cdb) begin
                     execute_pkt.src_0_a.is_renamed <= 1'b0;
                     execute_pkt.src_0_a.data <= cdb_ports[oh_2_i(src_0_a_in_cdb)].result;
                end
                if(|src_0_b_in_cdb) begin
                     execute_pkt.src_0_b.is_renamed <= 1'b0;
                     execute_pkt.src_0_b.data <= cdb_ports[oh_2_i(src_0_b_in_cdb)].result;
                end
                if(|src_1_a_in_cdb) begin
                     execute_pkt.src_1_a.is_renamed <= 1'b0;
                     execute_pkt.src_1_a.data <= cdb_ports[oh_2_i(src_1_a_in_cdb)].result;
                end
                if(|src_1_b_in_cdb) begin
                     execute_pkt.src_1_b.is_renamed <= 1'b0;
                     execute_pkt.src_1_b.data <= cdb_ports[oh_2_i(src_1_b_in_cdb)].result;
                end
            
            end
        end
    end


typedef enum logic {IDLE, PASS_THRU} rs_state_e;
rs_state_e state, next_state;
always_ff @( posedge clk ) begin 
    if(rst || flush) begin 
        state <= IDLE;
    end
    else begin
        state <= next_state;
    end
end
logic man_flush;
//I THINK THERE IS AN ERROR WITH RS_WRITE_READY BEING ASSIGNED A CYCLE EARLY, WILL UPDATE LATER
always_comb begin
    rs_write_rdy = 1'b0;
    rs_read_rdy = 1'b0;
    man_flush = 1'b0;
    case (state)
        IDLE : begin
            rs_write_rdy = 1'b1;
             if(rs_entry.is_valid && rs_we) begin
                next_state = PASS_THRU;
             end
             else next_state = IDLE;
        end
        PASS_THRU: begin
            if( !execute_pkt.src_0_a.is_renamed &&  
                !execute_pkt.src_0_b.is_renamed && 
                !execute_pkt.src_1_a.is_renamed &&
                !execute_pkt.src_1_b.is_renamed) begin
                    rs_read_rdy = 1'b1;
                if(alu_re) begin
                    if(rs_we) next_state = PASS_THRU;
                    else begin
                        next_state = IDLE;
                        man_flush = 1'b1;
                    end
                    rs_write_rdy = 1'b1;
                end
                else begin
                    next_state = PASS_THRU;
                    rs_write_rdy = 1'b0;
                end
            end
            else begin //if something renamed cant read/write
                 next_state = PASS_THRU;
                 rs_read_rdy = 1'b0;
                 rs_write_rdy = 1'b0;
            end   
        end 

    endcase
end



endmodule