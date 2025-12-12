module lsq
import riscv_isa_pkg::*; 
import uarch_pkg::*;
  #(
    parameter STQ_DEPTH = 5,
    parameter RS_SIZE = 5
 )(
   //wip
    input logic clk, rst, flush, cache_stall,
    // Ports from Displatch
    input instruction_t ld_lsq_entry[PIPE_WIDTH - 1 : 0],
    input instruction_t st_lsq_entry[PIPE_WIDTH - 1 : 0],
    input logic [PIPE_WIDTH - 1 : 0] ld_lsq_we,
    input logic [PIPE_WIDTH - 1 : 0] st_lsq_we,
    //Ports to Dispatch
    output logic [PIPE_WIDTH - 1 : 0] ld_lsq_rdy, //2,1,0 = 2+, 1, 0
    output logic [PIPE_WIDTH - 1 : 0] st_lsq_rdy,
    //Ports to Execute
    output  instruction_t execute_pkt,
    //Ports from Execute
    input logic alu_rdy,
    //CDB PORT 
    input writeback_packet_t cdb_ports [PIPE_WIDTH - 1 : 0],
    //AGU PORT
    input logic agu_rdy,
    output instruction_t agu_execute_pkt,
    input writeback_packet_t agu_result,
    //ROB PERMISSION 2 SPANK
    input  logic [TAG_WIDTH-1:0]    commit_store_ids    [PIPE_WIDTH-1:0],
    input  logic [PIPE_WIDTH-1:0]   commit_store_vals,
    //ROB
    input  logic [TAG_WIDTH-1:0]    rob_head 
);
//how many alu we have
function int oh_2_i (logic [PIPE_WIDTH-1:0] v);
        int o;
        o = 0;
        for (int i = 0; i < PIPE_WIDTH; i++) if (v[i]) o = i;
        return o;
  endfunction







//LD 
logic [RS_SIZE - 1 : 0] ld_we_arr;
logic [RS_SIZE - 1 : 0] ld_write_rdy_arr ;
logic [RS_SIZE - 1 : 0] [PIPE_WIDTH - 1 : 0]  ld_sel_arr;
logic [RS_SIZE - 1 : 0] ld_read_rdy_arr ;
logic [RS_SIZE - 1 : 0] ld_re_arr ;

//store
instruction_t store_q [STQ_DEPTH];

instruction_t ld_execute_pkt_arr [RS_SIZE - 1 : 0];
instruction_t mux_ld_entry_arr [RS_SIZE - 1 : 0];


//AGU 
instruction_t agu_execute_pkt_arr [RS_SIZE + STQ_DEPTH - 1 : 0];
logic [RS_SIZE + STQ_DEPTH - 1 : 0] agu_read_rdy_arr ;





genvar i;
generate
    for (i = 0; i < RS_SIZE; i++) begin
        lsq_rs ld_rs(
        .clk(clk), 
        .rst(rst), 
        .flush(flush), 
        .cache_stall(cache_stall),
        // Ports from Displatch
        .rs_entry(mux_ld_entry_arr[i]),
        .rs_we(ld_we_arr[i]),
        //Ports to Dispatch
        .rs_write_rdy(ld_write_rdy_arr[i]),
        .rs_read_rdy(ld_read_rdy_arr[i]),
        //Ports to Execute
        .execute_pkt(ld_execute_pkt_arr[i]),
        //Ports from Execute
        .alu_re(ld_re_arr[i]),
        //CDB PORT 
        .cdb_ports(cdb_ports),
        //AGU
        .agu_read_rdy(agu_read_rdy_arr[i]),
        .agu_execute_pkt(agu_execute_pkt_arr[i]),
        .agu_port(agu_result),
        //Forward 
        .store_q(store_q),
        .rob_head(rob_head)
        );
    end

endgenerate

logic [$clog2(PIPE_WIDTH) + 1 : 0] s;
logic [$clog2(RS_SIZE) + 1 : 0] ld_total_open_entries, ld_total_ready_entries;


function int ret_exe_candidate(int best_no);
    instruction_t candidate [RS_SIZE];
    int o [RS_SIZE];
    foreach(candidate[i]) candidate[i] = '0;
    for(int i = 0; i < best_no; i++) begin
        foreach(ld_execute_pkt_arr[j]) begin
            if(ld_read_rdy_arr[j]) begin
                if(candidate[i] == '0)begin
                     candidate[i] = ld_execute_pkt_arr[j];
                     o[i] = j;
                end
                else if (ld_execute_pkt_arr[j].dest_tag - rob_head < candidate[i].dest_tag - rob_head)begin
                    if(i == 0) begin
                        candidate[i] = ld_execute_pkt_arr[j];
                        o[i] = j;
                    end
                    else if (o[i] != o[i - 1]) begin
                        candidate[i] = ld_execute_pkt_arr[j];
                        o[i] = j;
                    end
                end
            end
        end
    end
    return o[best_no - 1];
endfunction




int c1;
logic ld_alu_rdy, st_alu_rdy;
instruction_t ld_execute_pkt, st_execute_pkt;
always_comb begin
    //initialization / default values
    s = 0;


    //loop to choose which ld_res station to write to (we write to lowest arr available one, can either write to one or 2 at a time)
    for(int i = 0; i < RS_SIZE; i++) begin
        //this if condition is hella sus if it works thank god but idk
        if(ld_write_rdy_arr[i] == 1'b1 && ld_lsq_we[s] == 1'b1 && s < PIPE_WIDTH) begin
             ld_sel_arr[i][s] = 1'b1;
             ld_we_arr[i] = 1'b1;
             s = s + 1'b1;
        end
        else begin 
          ld_sel_arr[i] = 2'd0;
          ld_we_arr[i] = 1'd0;
        end
    end
end
always_comb begin
    for(int i = 0; i < PIPE_WIDTH; i++) ld_lsq_rdy[i] = (ld_total_open_entries > i + 1) ? 1 : 0; 
end



always_comb begin
  ld_total_open_entries = '0;
    ld_total_ready_entries = '0;
  for(int i = 0; i < RS_SIZE; i++) begin
    ld_total_open_entries += ld_write_rdy_arr[i];
    ld_total_ready_entries += ld_read_rdy_arr[i];
  end
end

always_comb begin
  for(int i = 0; i < RS_SIZE; i++) begin
    if(ld_sel_arr[i] == 2'd0 ||ld_sel_arr[i] == 2'b11 ) mux_ld_entry_arr[i] = '0;
    else if (ld_sel_arr[i] == 2'b01) mux_ld_entry_arr[i] = ld_lsq_entry[0];
    else if (ld_sel_arr[i] == 2'b10) mux_ld_entry_arr[i] = ld_lsq_entry[1];
  end
end




logic [STQ_DEPTH - 1 : 0] st_we_arr;
logic [STQ_DEPTH - 1 : 0] st_write_rdy_arr ;
logic [STQ_DEPTH - 1 : 0] [PIPE_WIDTH - 1 : 0]  st_sel_arr;
logic [STQ_DEPTH - 1 : 0] st_read_rdy ;
logic [STQ_DEPTH - 1 : 0] st_re_arr ;

instruction_t mux_st_entry_arr [STQ_DEPTH - 1 : 0];

instruction_t dummy_stq [STQ_DEPTH];
always_comb begin
  foreach (dummy_stq[i]) dummy_stq[i] = '0;
end

genvar j;
generate
    for (j = 0; j < STQ_DEPTH; j++ ) begin
        lsq_rs_st st_rs(
        .clk(clk), 
        .rst(rst), 
        .flush(flush), 
        .cache_stall(cache_stall),
        // Ports from Displatch
        .rs_entry(mux_st_entry_arr[j]),
        .rs_we(st_we_arr[j]),
        //Ports to Dispatch
        .rs_write_rdy(st_write_rdy_arr[j]),
        .rs_read_rdy(st_read_rdy[j]),
        //Ports to Execute
        .execute_pkt(store_q[j]),
        //Ports from Execute
        .alu_re(st_re_arr[j]),
        //CDB PORT 
        .cdb_ports(cdb_ports),
        //AGU
        .agu_read_rdy(agu_read_rdy_arr[j + RS_SIZE]),
        .agu_execute_pkt(agu_execute_pkt_arr[j + RS_SIZE]),
        .agu_port(agu_result),
        //Forward 
        .commit_store_ids(commit_store_ids),
        .commit_store_vals(commit_store_vals),
        .rob_head(rob_head)
        //.forward_re('0),
        //.forward_pkt(),
        //.forward_rdy()
        );
    end
endgenerate


logic full, empty, pop_rdy, pop_mem;
logic [1:0] push_mem;
logic [$clog2(STQ_DEPTH) : 0] count, wr_ptr, wr_ptr_nxt, rd_ptr;
  always_ff @(posedge clk ) begin
    if (rst || flush) begin
      wr_ptr <= '0;
      wr_ptr_nxt <= 'b1;
    end 
    else if (push_mem[0] & !push_mem[1]) begin
      wr_ptr <= (wr_ptr == STQ_DEPTH-1) ? '0 : (wr_ptr + 1'b1);
      wr_ptr_nxt <= (wr_ptr_nxt == STQ_DEPTH-1) ? '0 : (wr_ptr_nxt + 1'b1);
    end
  else if(push_mem[0] && push_mem[1]) begin
    wr_ptr <= (wr_ptr_nxt == STQ_DEPTH - 1) ? '0 : (wr_ptr_nxt + 1'b1);
    wr_ptr_nxt <= (wr_ptr_nxt >= STQ_DEPTH - 2) ? (wr_ptr_nxt + 2 - STQ_DEPTH) : (wr_ptr_nxt + 2);
  end
  end
    always_ff @(posedge clk) begin
    if (rst || flush) begin
      rd_ptr <= '0;
    end else if (pop_mem) begin
      rd_ptr <= (rd_ptr == STQ_DEPTH-1) ? '0 : (rd_ptr + 1'b1);
    end
  end
   always_ff @(posedge clk) begin
    if (rst || flush) begin
      count <= '0;
    end else begin
      unique case ({push_mem, pop_mem})
        3'b110: count <= count + 2;
        3'b010: count <= count + 1;
        3'b111: count <= count + 1;
        3'b001: count <= count - 1;
        default: /* 00 or 11: no change */ ;
      endcase
    end
  end
always_comb begin
    full = (count == STQ_DEPTH);
    st_lsq_rdy = {st_write_rdy_arr[wr_ptr_nxt], st_write_rdy_arr[wr_ptr]};
    push_mem[0] = st_lsq_we[0] & !full & st_lsq_rdy[0];      // write into mem this cycle
    push_mem[1] = st_lsq_we[1] & !full & st_lsq_rdy[1];
    pop_rdy = st_read_rdy[rd_ptr] & !empty;
    pop_mem  = st_alu_rdy & ~empty & pop_rdy;   
    empty = (count == 0);
    foreach (mux_st_entry_arr[i]) begin
       if(st_sel_arr[i] == 2'b01) mux_st_entry_arr[i] = st_lsq_entry[0];
       else if (st_sel_arr[i] == 2'b10) mux_st_entry_arr[i] = st_lsq_entry[1];
       else mux_st_entry_arr[i] = '0;
    end
    
    foreach(st_we_arr[i]) begin
      if(push_mem[0] && i == wr_ptr)begin
         st_we_arr[i] = 1'b1;
         st_sel_arr[i] = 2'b01;
      end
      else if  (push_mem[1] && i == wr_ptr_nxt) begin
        st_we_arr[i] = 1'b1;
        st_sel_arr[i] = 2'b10;
      end
      else begin
        st_we_arr[i] = 1'b0;
        st_sel_arr[i] = 2'b00;
      end
      if(pop_mem && i == rd_ptr) st_re_arr[i] = 1'b1;
      else st_re_arr[i] = 1'b0;
    end

    st_execute_pkt = store_q[rd_ptr];
end


//output selection logic
function int rb_agu_c();
  int o;
  logic flag; 
  flag = 0;
  o = 0;
  foreach(agu_execute_pkt_arr[i]) begin
    if(agu_read_rdy_arr[i]) begin
      if(!flag) begin
         o = i;
         flag = 1;
      end
      else if (agu_execute_pkt_arr[i].dest_tag - rob_head < agu_execute_pkt_arr[o].dest_tag - rob_head) o = i;
    end
  end
  return o;
endfunction


logic [3:0] outstanding_store_cnt;
always_ff @ (posedge clk) begin
  if(rst || flush) outstanding_store_cnt <= '0;
  else begin
    if (commit_store_vals == 2'b01 || commit_store_vals == 2'b10) outstanding_store_cnt <= outstanding_store_cnt + 4'd1 - st_alu_rdy;
    else if (commit_store_vals == 2'b11) outstanding_store_cnt <= outstanding_store_cnt + 4'd2 - st_alu_rdy;
    else outstanding_store_cnt <= outstanding_store_cnt - st_alu_rdy;
  end
end


always_comb begin
  st_alu_rdy = 1'b0;
  ld_alu_rdy = 1'b0;
  if(alu_rdy) begin
    case ({pop_rdy, (ld_total_ready_entries > 0 )})
      2'b01 : ld_alu_rdy = (outstanding_store_cnt == 4'd0);
      2'b10 : st_alu_rdy = 1'b1;
      2'b11 : begin
        st_alu_rdy = 1'b1;    
      end
      default : begin
        ld_alu_rdy = 1'b0;
        st_alu_rdy = 1'b0;
      end
    endcase
    if(st_alu_rdy) execute_pkt = st_execute_pkt;
    else if (ld_alu_rdy) execute_pkt = ld_execute_pkt;
    else execute_pkt = '{default:'0};
  end
  else begin
      execute_pkt = '0;
      st_alu_rdy = 1'b0;
      ld_alu_rdy = 1'b0;
  end
  if(ld_alu_rdy == 1'b1) begin
      c1 = ret_exe_candidate(1);
      ld_execute_pkt = ld_execute_pkt_arr[c1];
      foreach(ld_re_arr[i]) begin
        if(i == c1) ld_re_arr[i] = 1'b1;
        else ld_re_arr[i] = 1'b0;
      end
    end
    else begin
       foreach(ld_re_arr[i]) ld_re_arr[i] = 1'b0;
       ld_execute_pkt = '0;
    end
end

//agu logic
always_comb begin
  if(agu_rdy && |agu_read_rdy_arr) agu_execute_pkt = agu_execute_pkt_arr[rb_agu_c()];
  else agu_execute_pkt = '0;
end




endmodule