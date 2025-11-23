import riscv_isa_pkg::*; 
import uarch_pkg::*;


module lsq_rs_tb ();
localparam STQ_DEPTH = 5;
logic clk, rst, flush, cache_stall, alu_re, rs_write_rdy, rs_read_rdy, rs_we, agu_read_rdy, forward_re, forward_rdy;
instruction_t rs_entry, execute_pkt, agu_execute_pkt;
writeback_packet_t cdb_ports [PIPE_WIDTH - 1 : 0];
writeback_packet_t forward_pkt, agu_port;
instruction_t store_q [STQ_DEPTH];
    lsq_rs rs(
    .clk(clk), 
    .rst(rst), 
    .flush(flush), 
    .cache_stall(cache_stall),
    .rs_entry(rs_entry),
    .rs_we(rs_we),
    .rs_write_rdy(rs_write_rdy),
    .rs_read_rdy(rs_read_rdy),
    .execute_pkt(execute_pkt),
    .alu_re(alu_re),
    .cdb_ports(cdb_ports),


    .agu_read_rdy(agu_read_rdy),
    .agu_execute_pkt(agu_execute_pkt),
    .agu_port(agu_port),

    //Forwarding ports, super high cost
    //in the future maybe switch to an address buffer, or with a fast l1 cache maybe j remove forwarding?
    //compiler can deal with it, doesn't feel worth
    .store_q(store_q),
    .forward_re(forward_re),
    .forward_pkt(forward_pkt),
    .forward_rdy(forward_rdy)

);

initial begin
    clk = 0;
    flush = 0;
    cache_stall = 0;
    rs_we = 0; 
    alu_re = 0;
    rs_entry = '0;
    cdb_ports[0] = '0;
    cdb_ports[1] = '0;
    agu_port = '0;
    forward_re = '0;
    foreach(store_q[i]) store_q[i] = '0;
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
function instruction_t gen_random_instr_pkt(logic [CPU_DATA_BITS-1:0]   data_h, data_l, logic [TAG_WIDTH-1:0] tag_h, tag_l, int ren = 1, int pc = 0);
    instruction_t out;
    int r;
    out = '0;
    out.is_valid = 1'b1;

    out.src_0_a.data        = (data_h == data_l) ? data_h :$random % (data_h - data_l) + data_l;
    out.src_0_a.tag         = (tag_h == tag_l) ? tag_h :$random % (tag_h - tag_l) + tag_l;
    out.src_0_a.data        = (data_h == data_l) ? data_h :$random % (data_h - data_l) + data_l;
    out.src_0_b.tag         = (tag_h == tag_l) ? tag_h :$random % (tag_h - tag_l) + tag_l;
    out.src_0_a.data        = (data_h == data_l) ? data_h :$random % (data_h - data_l) + data_l;
    out.src_1_a.tag         = (tag_h == tag_l) ? tag_h :$random % (tag_h - tag_l) + tag_l;
    out.src_0_a.data        = (data_h == data_l) ? data_h :$random % (data_h - data_l) + data_l;
    out.src_1_b.tag         = (tag_h == tag_l) ? tag_h :$random % (tag_h - tag_l) + tag_l;
    out.pc = pc;
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
function writeback_packet_t gen_random_cbd_pkt(logic [CPU_DATA_BITS-1:0] data_h, data_l, logic [TAG_WIDTH-1:0] tag_h, tag_l);
    writeback_packet_t out;
    out.result = (data_h == data_l) ? data_h :$random % (data_h - data_l) + data_l;
    out.is_valid = 1'b1;
    out.dest_tag = (tag_h == tag_l) ? tag_h :$random % (tag_h - tag_l) + tag_l;;
    out.exception = '0;
    return out;
endfunction

task rndm_tst();
    instruction_t j;
    forever begin
        if(rs_write_rdy == 1'b1) begin
            j = gen_random_instr_pkt(32'hffff_ffff, 32'h000_0000, 5'd8, 5'd0);
            rs_entry <= j;
            rs_we <= 1'b1;

        end
        @(posedge clk);
        rs_we <= 1'b0;
        while(rs_read_rdy == 1'b0) begin
            cdb_ports[0] <= gen_random_cbd_pkt(32'hffff_ffff, 32'h000_0000, 5'd8, 5'd5);
            cdb_ports[1] <= gen_random_cbd_pkt(32'hffff_ffff, 32'h000_0000, 5'd4, 5'd0);
            @(posedge clk);
        end
        if($time % 2 == 0) alu_re <= 1'b1;
        else begin
            alu_re <= 1'b1;
            @(posedge clk);
        end
    end
endtask

task single_trasaction();
instruction_t temp;

    #1;
    if(rs_write_rdy == 1'b1) begin
        rs_entry <= gen_random_instr_pkt(32'h000_0000, 32'h000_0000, 5'd8, 5'd8, 0, 20); //tag is 8, renamed
        rs_we <= 1'b1;
        @(posedge clk);
        rs_we <= 1'b0;
        @(posedge clk);
        wait(agu_read_rdy == 1'b1);
        agu_port <= gen_random_cbd_pkt(32'h0000_ffff, 32'h0000_ffff, 5'd0, 5'd0);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        while(forward_rdy == 0) begin
            temp = gen_random_instr_pkt(32'h0000_ffff, 32'h0000_ffff, 5'd8, 5'd8, 2, 18);
            temp.agu_comp = 1'b1;
            store_q[0] <= temp;
            @(posedge clk);
        end
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        $finish;
    end
endtask

task cdb_forward();
     if(rs_write_rdy == 1'b1) begin
        rs_entry = gen_random_instr_pkt(32'hffff_ffff, 32'h000_0000, 5'd8, 5'd8, 2); //tag is 8, renamed
        cdb_ports[0] <= gen_random_cbd_pkt(32'hffff_ffff, 32'h000_0000, 5'd8, 5'd8);
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
    //rndm_tst();
    single_trasaction();
    //cdb_forward();
end

endmodule