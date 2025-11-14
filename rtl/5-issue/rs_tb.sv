import riscv_isa_pkg::*; 
import uarch_pkg::*;

logic clk, rst, flush, cache_stall, alu_re, rs_write_rdy, rs_read_rdy, rs_we;
instruction_t rs_entry, execute_pkt;
writeback_packet_t cdb_ports [PIPE_WIDTH - 1 : 0];
module rs_tb ();
    rs rs(
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
    .cdb_ports(cdb_ports) 
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
function instruction_t gen_random_instr_pkt(logic [CPU_DATA_BITS-1:0]   data_h, data_l, logic [TAG_WIDTH-1:0] tag_h, tag_l, int ren = 1);
    instruction_t out;
    out = '0;
    out.is_valid = 1'b1;
    out.src_0_a.data        = $random % 100;
    out.src_0_a.tag         = $urandom_range(tag_h, tag_l);
    out.src_0_b.data        = $random % 100;
    out.src_0_b.tag         = $urandom_range(tag_h, tag_l);
    out.src_1_a.data        = $random % 100;
    out.src_1_a.tag         = $urandom_range(tag_h, tag_l);
    out.src_1_b.data        = $random % 100;
    out.src_1_b.tag         = $urandom_range(tag_h, tag_l);
    if(ren == 1) begin 
        out.src_0_a.is_renamed  = $urandom_range(1, 0);
        out.src_0_b.is_renamed  = $urandom_range(1, 0);
        out.src_1_a.is_renamed  = $urandom_range(1, 0);
        out.src_1_b.is_renamed  = $urandom_range(1, 0);
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
    out.result = $random % 100;
    out.is_valid = 1'b1;
    out.dest_tag = $urandom_range(tag_h, tag_l);
    out.exception = '0;
    return out;
endfunction

task rndm_tst();
    alu_re = 1'b0;
    rs_we = 1'b0;
    forever begin
        #1;
        if(rs_write_rdy == 1'b1) begin
            rs_entry = gen_random_instr_pkt(32'hffff_ffff, 32'h000_0000, 5'd8, 5'd0);
            rs_we <= 1'b1;

        end
        @(posedge clk);
        rs_we <= 1'b0;
        while(rs_read_rdy == 1'b0) begin
            cdb_ports[0] = gen_random_cbd_pkt(32'hffff_ffff, 32'h000_0000, 5'd8, 5'd5);
            cdb_ports[1] = gen_random_cbd_pkt(32'hffff_ffff, 32'h000_0000, 5'd4, 5'd0);
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

    #1;
    if(rs_write_rdy == 1'b1) begin
        rs_entry = gen_random_instr_pkt(32'hffff_ffff, 32'h000_0000, 5'd8, 5'd8, 2); //tag is 8, renamed
        rs_we <= 1'b1;
        @(posedge clk);
        rs_we <= 1'b0;
        @(posedge clk);
        @(posedge clk);
        cdb_ports[0] <= gen_random_cbd_pkt(32'hffff_ffff, 32'h000_0000, 5'd8, 5'd8);
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
end

endmodule