import riscv_isa_pkg::*; 
import uarch_pkg::*;
module alu_rs_tb ();
    
logic clk, rst, flush, cache_stall;
logic [1:0] alu_rdy; 
logic [PIPE_WIDTH - 1 : 0] rs_we, rs_rdy;

instruction_t rs_entry [PIPE_WIDTH - 1 : 0];
instruction_t execute_pkt [1:0];
writeback_packet_t cdb_ports [PIPE_WIDTH - 1 : 0];
    alu_rs rs(
    .clk(clk), 
    .rst(rst), 
    .flush(flush), 
    .cache_stall(cache_stall),
    .rs_entry(rs_entry),
    .rs_we(rs_we),
    .rs_rdy(rs_rdy),
    .execute_pkt(execute_pkt),
    .alu_rdy(alu_rdy),
    .cdb_ports(cdb_ports) 
);

initial begin
    clk = 0;
    flush = 0;
    cache_stall = 0;
    rs_we = '0; 
    foreach(alu_rdy[i]) alu_rdy[i] = '0;
    foreach(rs_entry[i]) rs_entry[i] = '0;
    foreach(cdb_ports[i])cdb_ports[i] = '0;
    cdb_ports[1] = '0;
end
always #10 clk = ~clk;

task toggle_rst();
    rst = 0;
    #20;
    rst = 1;
    #20; 
    rst = 0;
    #20;
endtask
function instruction_t gen_random_instr_pkt(logic [TAG_WIDTH-1:0] tag_h, tag_l, int ren = 1);
    instruction_t out;
    int r;
    out = '0;
    out.is_valid = 1'b1;

    out.src_0_a.data        = $random % 100;
    out.src_0_a.tag         = (tag_h == tag_l) ? tag_h :$random % (tag_h - tag_l) + tag_l;
    out.src_0_b.data        = $random % 100;
    out.src_0_b.tag         = (tag_h == tag_l) ? tag_h :$random % (tag_h - tag_l) + tag_l;;
    out.src_1_a.data        = $random % 100;
    out.src_1_a.tag         = (tag_h == tag_l) ? tag_h :$random % (tag_h - tag_l) + tag_l;;
    out.src_1_b.data        = $random % 100;
    out.src_1_b.tag         = (tag_h == tag_l) ? tag_h :$random % (tag_h - tag_l) + tag_l;;
    if(ren == 1) begin 
        r = $random % 2;
        out.src_0_a.is_renamed  = r;
        out.src_0_b.is_renamed  = r;
        out.src_1_a.is_renamed  = r;
        out.src_1_b.is_renamed  = r;
    end
    else if (ren == 2) begin
        out.src_0_a.is_renamed  = 1'b1; 
        out.src_0_b.is_renamed  = 1'b1; 
        out.src_1_a.is_renamed  = 1'b1; 
        out.src_1_b.is_renamed  = 1'b1; 
    end
    return out;
endfunction
function writeback_packet_t gen_random_cbd_pkt(logic [TAG_WIDTH-1:0] tag_h, tag_l);
    writeback_packet_t out;
    out.result = $random % 100;
    out.is_valid = 1'b1;
    out.dest_tag = (tag_h == tag_l) ? tag_h :$random % (tag_h - tag_l) + tag_l;;
    out.exception = '0;
    return out;
endfunction

task rndm_tst();
    instruction_t j, k;
    forever begin
        if(|rs_rdy == 1'b1) begin
            j = gen_random_instr_pkt(5'd8, 5'd0);
            k = gen_random_instr_pkt(5'd8, 5'd0);
            rs_entry[0] <= j;
            if(rs_rdy == 2'b11) begin
                if($time % 2) rs_entry[1] <= k;
                rs_we <= 2'b11;
            end
            else rs_we <= 2'b01;

        end
        alu_rdy <= 2'b11;
        @(posedge clk);
        rs_we <= 2'b00;
        while(!execute_pkt[0].is_valid & !execute_pkt[1].is_valid) begin
            cdb_ports[0] <= gen_random_cbd_pkt(5'd8, 5'd5);
            cdb_ports[1] <= gen_random_cbd_pkt(5'd4, 5'd0);
            @(posedge clk);
        end
        alu_rdy[0] <= 1'b1;
        if($time % 2) alu_rdy[1] <= 1'b1;
        @(posedge clk);
    end
endtask

task single_trasaction();

    #1;
    if(|rs_rdy == 1'b1) begin
        alu_rdy <= 2'b11;
        rs_entry[0] <= gen_random_instr_pkt(5'd8, 5'd8, 2); //tag is 8, renamed
        rs_we[0] <= 1'b1;
        @(posedge clk);
        rs_we[0] <= 1'b0;
        @(posedge clk);
        @(posedge clk);
        cdb_ports[0] <= gen_random_cbd_pkt(5'd8, 5'd8);
        @(posedge clk);
        cdb_ports[0] <= '0;
        @(posedge clk);
        $finish;
    end
endtask

task cdb_forward();
     if(|rs_rdy == 1'b1) begin
        rs_entry[0] = gen_random_instr_pkt(5'd8, 5'd8, 2); //tag is 8, renamed
        cdb_ports[0] <= gen_random_cbd_pkt(5'd8, 5'd8);
        rs_we <= 1'b1;
        @(posedge clk);
        rs_we <= 1'b0;
        @(posedge clk);      
        cdb_ports[0] <= '0;
        @(posedge clk);
        $finish;
    end
endtask
initial begin
    toggle_rst();
    rndm_tst();
    //single_trasaction();
    //cdb_forward();
end

endmodule