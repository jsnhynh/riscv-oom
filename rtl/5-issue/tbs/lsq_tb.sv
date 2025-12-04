import riscv_isa_pkg::*; 
import uarch_pkg::*;


module lsq_tb ();
localparam STQ_DEPTH = 5;
logic clk, rst, flush, cache_stall, alu_re, forward_re, forward_rdy;

    instruction_t ld_lsq_entry[PIPE_WIDTH - 1 : 0];
    localparam RS_SIZE = 5;
    logic [PIPE_WIDTH - 1 : 0] ld_lsq_we;
    instruction_t st_lsq_entry[PIPE_WIDTH - 1 : 0];
    logic [PIPE_WIDTH - 1 : 0] st_lsq_we;
    //Ports to Dispatch
    logic [PIPE_WIDTH - 1 : 0] ld_lsq_rdy; //2,1,0 = 2+, 1, 0
    logic [PIPE_WIDTH - 1 : 0] st_lsq_rdy;
    //Ports to Execute
    instruction_t execute_pkt;
    //Ports from Execute
    logic alu_rdy;
    //CDB PORT 
    writeback_packet_t cdb_ports [PIPE_WIDTH - 1 : 0];
    //AGU PORT
    logic agu_rdy;
    instruction_t agu_execute_pkt;
    writeback_packet_t agu_result;
    //FORWARD 
    writeback_packet_t forward_pkt;
    logic forward_rdy;
    logic forward_re;


instruction_t store_q [STQ_DEPTH];
    lsq lsq(
    .clk(clk), 
    .rst(rst), 
    .flush(flush), 
    .cache_stall(cache_stall),
    .ld_lsq_entry(ld_lsq_entry),
    .ld_lsq_we(ld_lsq_we),
    .st_lsq_entry(st_lsq_entry),
    .st_lsq_we(st_lsq_we),
    //Ports to Dispatch
    .ld_lsq_rdy(ld_lsq_rdy), //2,1,0 = 2+, 1, 0
    .st_lsq_rdy(st_lsq_rdy),
    //Ports to Execute
    .execute_pkt(execute_pkt),
    //Ports from Execute
    .alu_rdy(alu_rdy),
    //CDB PORT 
    .cdb_ports(cdb_ports),
    //AGU PORT
    .agu_rdy(agu_rdy),
    .agu_execute_pkt(agu_execute_pkt),
    .agu_result(agu_result),
    //FORWARD 
    .forward_pkt(forward_pkt),
    .forward_rdy(forward_rdy),
    .forward_re(forward_re)

);

initial begin
    clk = 0;
    flush = 0;
    cache_stall = 0;
    foreach(ld_lsq_we[i]) ld_lsq_we[i] = 2'b0;
    foreach(st_lsq_we[i]) st_lsq_we[i] = 2'b0; 
    alu_re = 0;
    agu_rdy = '0;
    agu_result = '0;
    foreach(ld_lsq_entry[i]) ld_lsq_entry[i] = '0;
    foreach(st_lsq_entry[i]) st_lsq_entry[i] = '0;
    cdb_ports[0] = '0;
    cdb_ports[1] = '0;
    agu_rdy = '0;
    agu_result = '0;
    forward_re = '0;
    alu_rdy = '0;
    
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
    if (ren == 0) begin
        out.src_0_a.is_renamed  = 0;
        out.src_0_b.is_renamed  = 0;
        out.src_1_a.is_renamed  = 0;
        out.src_1_b.is_renamed  = 0;
    end
    else if(ren == 1) begin 
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

// task rndm_tst();
//     instruction_t j;
//     forever begin
//         if(rs_write_rdy == 1'b1) begin
//             j = gen_random_instr_pkt(32'hffff_ffff, 32'h000_0000, 5'd8, 5'd0);
//             rs_entry <= j;
//             rs_we <= 1'b1;

//         end
//         @(posedge clk);
//         rs_we <= 1'b0;
//         while(rs_read_rdy == 1'b0) begin
//             cdb_ports[0] <= gen_random_cbd_pkt(32'hffff_ffff, 32'h000_0000, 5'd8, 5'd5);
//             cdb_ports[1] <= gen_random_cbd_pkt(32'hffff_ffff, 32'h000_0000, 5'd4, 5'd0);
//             @(posedge clk);
//         end
//         if($time % 2 == 0) alu_re <= 1'b1;
//         else begin
//             alu_re <= 1'b1;
//             @(posedge clk);
//         end
//     end
// endtask

function writeback_packet_t gen_agu(instruction_t agu_e_p);
    writeback_packet_t g;
    g.is_valid = 1'b1;
    g.dest_tag = agu_e_p.dest_tag;
    g.result = agu_e_p.src_0_a.data + agu_e_p.src_0_b.data;
    g.exception = 1'b0;
    return g;
endfunction


task single_trasaction(bit load); //default store
instruction_t temp;
    bit [1:0] es;
    #1;
    if(load == 0 && |st_lsq_rdy == 1) begin
        st_lsq_entry[0] <= gen_random_instr_pkt(32'h000_000f, 32'h000_0000, 5'd8, 5'd8, 0, 20);
        st_lsq_we[0] <= 1'b1;
    end
    else if (load == 1 && |ld_lsq_rdy == 1) begin
        ld_lsq_entry[0] <= gen_random_instr_pkt(32'h000_000f, 32'h000_0000, 5'd8, 5'd8, 0, 20);
        ld_lsq_we[0] <= 1'b1;
    end
        $display("LINE 183");
        @(posedge clk);
        st_lsq_we <= 1'b0;
        ld_lsq_we <= 1'b0;
        agu_rdy <= 1'b1;
        @(posedge clk);
        $display("LINE 189");
        wait(agu_execute_pkt.is_valid);
        $display("line 191");
        @(posedge clk);
        agu_result <= gen_agu(agu_execute_pkt);
        agu_rdy <= 1'b1;
        @(posedge clk);
        $display("line 196");
        agu_rdy <= 1'b1;
        @(posedge clk);
        alu_rdy <= 1'b1;
        $display("line 199");
        @(posedge clk);
        $display("line 201");
        @(posedge clk);
        $display("line 203");
        @(posedge clk);
        $finish;
    
endtask

// task cdb_forward();
//      if(rs_write_rdy == 1'b1) begin
//         rs_entry = gen_random_instr_pkt(32'hffff_ffff, 32'h000_0000, 5'd8, 5'd8, 2); //tag is 8, renamed
//         cdb_ports[0] <= gen_random_cbd_pkt(32'hffff_ffff, 32'h000_0000, 5'd8, 5'd8);
//         rs_we <= 1'b1;
//         @(posedge clk);
//         rs_we <= 1'b0;
//         @(posedge clk);      
//         cdb_ports[0] <= '0;
//         @(posedge clk);
//         $finish;
//     end
// endtask
initial begin
    toggle_rst();
    //rndm_tst();
    single_trasaction(1);
    //cdb_forward();
end

endmodule