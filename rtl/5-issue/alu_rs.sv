module rs (
   //wip
    input logic clk, rst, flush, cache_stall,
    // Ports from Displatch
    input instruction_t rs_entry[PIPE_WIDTH - 1 : 0],
    input logic [RS_SIZE - 1 : 0] rs_we,
    //Ports to Dispatch
    output logic [PIPE_WIDTH - 1 : 0] rs_rdy, //2,1,0 = 2+, 1, 0
    //Ports to Execute
    output  instruction_t execute_pkt [1:0],
    //Ports from Execute
    input logic [1:0] alu_rdy,
    //CDB PORT 
    input writeback_packet_t cdb_ports [PIPE_WIDTH - 1 : 0] 
);
//how many alu we have
function  int oh_2_i (logic [PIPE_WIDTH-1:0] v);
        int o;
        o = 0;
        onehot_to_idx = -1;
        for (int i = 0; i < NUM_CDB; i++) if (v[i]) o = i;
        return o;
    endfunction


bit [RS_SIZE - 1 : 0] indv_rs_we;
bit [RS_SIZE - 1 : 0] indv_rs_write_rdy ;
bit [RS_SIZE - 1 : 0] [PIPE_WIDTH - 1 : 0]  rs_sel;
bit [RS_SIZE - 1 : 0] indv_rs_read_rdy ;
instruction_t indv_execute_pkt [RS_SIZE - 1 : 0];

genvar i;
generate
    for (i = 0; i < RS_SIZE; i++) begin
        rs rs(
        .clk(clk), 
        .rst(rst), 
        .flush(flush), 
        .cache_stall(cache_stall),
        // Ports from Displatch
        .rs_entry(muxed_rs_entry),
        .rs_we(indv_rs_we[i])
        //Ports to Dispatch
        .rs_write_rdy(indv_rs_write_rdy[i]),
        .rs_read_rdy(indv_rs_read_rdy[i]),
        //Ports to Execute
        .execute_pkt(indv_execute_pkt[i]),
        //Ports from Execute
        .alu_re(indv_alu_rdy[i]),
        //CDB PORT 
        .cdb_ports(cdb_ports));
    end

endgenerate

logic [$clog2(PIPE_WIDTH) + 1 : 0] s;
logic [$clog2(RS_SIZE) + 1 : 0] total_open_entries, total_ready_entries;
function int ret_exe_candidate(int best_no);
    instruction_t candidate [best_no];
    int o [best_no];
    foreach(canditate[i]) candidate[i] = '0;

    for(int i = 0; i < best_no; i++) begin
        foreach(indv_execute_pkt[j]) begin
            if(indv_rs_read_rdy[j]) begin
                if(candidate[i] == '0)begin
                     candidate[i] = indv_execute_pkt[j];
                     o[i] = j;
                end
                else if (indv_execute_pkt[j].pc < candidate[i].pc)begin
                    if(i == 0) begin
                        canditate[i] = indv_execute_pkt[j];
                        o[i] = j;
                    end
                    else if (o[i] != o[i - 1]) begin
                        canditate[i] = indv_execute_pkt[j];
                        o[i] = j;
                    end
                end
            end
        end
    end
    return o[best_no];
endfunction

int c1, c2;
always_comb begin
    s = 0;
    foreach (indv_alu_rdy[i]) indv_alu_rdy[i] = 1'b0;
    total_open_entries = '0;
    for(int i = 0; i < RS_SIZE; i++) begin
        //this if condition is hella sus if it works thank god but idk
        if(indv_rs_write_rdy[i] == 1'b1 && rs_we[s] == 1'b1 && s < PIPE_WIDTH) begin
             rs_sel[i][s] = 1'b1;
             indv_rs_we[i] = 1'b1;
             s = s + 1'b1;
        end
        total_open_entries += indv_rs_write_rdy[i];
        total_ready_entries += indv_rs_read_rdy[i];
        muxed_rs_entry[i] = rs_entry[oh_2_i(rs_sel[i])];
    end
    for(int i = 0; i < PIPE_WIDTH; i++) rs_rdy[i] = (total_open_entries > i + 1) ? 1 : 0;

    //outputs
    if(^alu_rdy = 1'b1) begin
        c1 = ret_exe_candidate(1);
        indv_alu_rdy[c1] = 1'b1;
        execute_pkt[alu_rdy - 1] = indv_execute_pkt[c1];
    end
    else if(alu_rdy[0] && alu_rdy[1]) begin
        c1 = ret_exe_candidate(1);
        c2 = ret_exe_candidate(2);
        indv_alu_rdy[c1] = 1'b1;
        indv_alu_rdy[c2] = 1'b1;
        execute_pkt[0] = indv_execute_pkt[c1];
        execute_pkt[1] = indv_execute_pkt[c2];
    end
end

//logic to select open reservation stations and write to them
//if possible  select lowest  2 reservation stations
//if 1 res station open and 2 entries, select entry 0, and flip flip_count, next time select entry 1 and flip...




endmodule