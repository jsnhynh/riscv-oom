module rs (
   //wip
        input logic clk, rst, flush, cache_stall,
    // Ports from Displatch
    input instruction_t rs_entry[1:0],
    //Ports to Dispatch
    output logic [1:0] rs_rdy, //2,1,0 = 2+, 1, 0

    //Ports to Execute
    output  instruction_t execute_pkt[EXE_COUNT - 1 : 0],

    //Ports from Execute
    input logic [1:0] alu_rdy,

    //CDB PORT 
    input writeback_packet_t cdb_port0, cdb_port1
);
//how many alu we have


bit indv_rs_rdy [RS_SIZE - 1 : 0];
bit rs_we [RS_SIZE - 1 : 0];
bit rs_sel [RS_SIZE - 1 : 0];
bit indv_alu_rdy [RS_SIZE - 1 : 0];
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
        .rs_entry(rs_sel[i] ? rs_entry[1] : rs_entry[0]),
        .rs_we(rs_we[i])
        //Ports to Dispatch
        .rs_rdy(indv_rs_rdy[i]),
        //Ports to Execute
        .execute_pkt(indv_execute_pkt[i]),
        //Ports from Execute
        .alu_rdy(indv_alu_rdy[i]),
        //CDB PORT 
        .cdb_port0(cdb_port0), 
        .cdb_port1(cdb_port1) );
    end
endgenerate

int sum;
bit[$clog2(RS_SIZE) : 0] o1, o2;

always_comb begin
    if(o1 > 0) rs_we[o1 - RS_SIZE'd1] = 1'b1;
    if(o2 > 0) rs_we[o2 - RS_SIZE'd1] = 1'b1;
    for(int i = 0; i < RS_SIZE; i++) begin
        if(rs_rdy < 2'b11) rs_rdy += indv_rs_rdy[i];
        if(rs_rdy == 2'b0) begin
             o1 = '0;
             o2 = '0;
        end
        else if (rs_rdy == 2'b1) begin
            if(indv_rs_rdy[i] && o1 <= i) o1 = i;
        end
        else begin
            if(indv_rs_rdy[i] && o1 <= i) o1 = i;
            if(indv_rs_rdy[i] && o1 < i) o2 = i;
        end
    end

    if(rs_rdy < 2'b11) rs_rdy += indv_rs_rdy[i];
        if(rs_rdy == 2'b0) begin
            
        end
        else if (rs_rdy == 2'b1) begin

        end
        else begin
            
        end

end

always_ff @( posedge clk ) begin 
    if(rs_rdy = 2'b1 && flip_count <= ~flip_count;
end
endmodule