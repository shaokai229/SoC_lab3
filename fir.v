`include "../../bram/bram11.v"

`timescale 1ns / 1ps
module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,    
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready, 
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  reg [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  reg [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);
begin

//  FSM
reg[3:0] cs, ns;
parameter idle        = 4'd0 ;

parameter input_1  = 4'd1 ; // addr
parameter input_2  = 4'd2 ; // write

parameter calculte_1    = 4'd3 ; 
parameter calculte_2    = 4'd4 ; 
parameter last_multi   = 4'd5 ;
parameter accumulate   = 4'd6 ;
parameter out_state  = 4'd7 ;


reg [(pDATA_WIDTH-1):0] tap_Di_reg;
reg [(pADDR_WIDTH-1):0] tap_A_reg;
reg [(pADDR_WIDTH-1):0] tap_A_reg_read;
reg [3:0]tap_WE_reg;

reg[3:0] coef_count;

reg awready_reg;
reg  [(pADDR_WIDTH-1):0]addr_reg;
reg rvalid_reg;
reg work; // 0: write ; 1:read

reg [3:0]stream_count_ss;
reg [(pDATA_WIDTH-1):0] data_Di_reg, ap_ceeck;
reg [(pADDR_WIDTH-1):0] data_A_reg;
reg [3:0]               data_WE_reg;
reg [3:0]               now_data_addr;
reg [3:0]               ptr, initial_ptr;
reg [3:0]               X_count, coef_ptr, out_count;
reg    [(pDATA_WIDTH-1):0]  Xn;
reg    [(pDATA_WIDTH-1):0]  Yn;
reg    [(pDATA_WIDTH-1):0]  multi_result;
reg out_EN, out_EN_t,out_EN_2,out_EN_t2, out_EN_t3;
reg do_cal;
reg [(pDATA_WIDTH-1):0] mult_a;
reg [9:0]pattern_number;
reg ap_start, ap_done, ap_idle;
//####################################################
//                      FSM
//####################################################
always@(posedge axis_clk or negedge axis_rst_n) begin
	if(!axis_rst_n)        
		cs <= idle;
	else
		cs <= ns;
end

//ns
always@(*) begin
    case(cs)
        idle: //0
        begin
          ns = input_1;
        end

        input_1: // 1  
        // addr
        begin
          if(awaddr == 12'h000 && wdata == 32'd1)
            ns = calculte_1 ;
          else if(awvalid)
            ns = input_2;
          else 
            ns = input_1;
        end
        input_2:
        // write
        begin
          if(awaddr == 12'h000 && wdata == 32'd1)
            ns = calculte_1;
          else if(wvalid)
            ns = input_1;
          else  
            ns = input_2;
        end

        calculte_1 : //2
        begin
          if(out_count == 10)
            ns = calculte_2;
          else 
            ns = calculte_1;
        end

        calculte_2 : //3
        begin
          if(X_count == ptr )
            ns = last_multi;
          else 
            ns = calculte_2;
        end

        last_multi:      
        begin
          ns = accumulate;
        end

        accumulate:
        begin
          ns = out_state;
        end

        out_state :
        begin
          ns = calculte_2;
        end

        default: 
            ns= idle; 
    endcase
end

//####################################################
//                   TAPE SRAM
//####################################################
assign tap_EN = 1'b1;
assign tap_Di = tap_Di_reg;

always @(*)begin
  if(cs == calculte_2) 
    tap_A = {coef_ptr,2'b0};
  else 
    tap_A = (!work)? tap_A_reg: araddr -12'h020;
end
assign tap_WE = tap_WE_reg;

always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n) 
    work <= 0;
  else if(ns == calculte_1 || ns == calculte_2)
    work <= 0;
  else if(rready)
    work <= 1;
  else 
    work <= 0;
end

always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n) 
      tap_WE_reg <= 4'b0000;
  else if ((wvalid && wready == 1) && (awaddr != 12'h010)) 
      tap_WE_reg <= 4'b1111;
  else 
      tap_WE_reg <= 4'b0000;
end

always @(posedge axis_clk or negedge axis_rst_n) begin
  //(counter & wvalid) 
  if(~axis_rst_n) 
    coef_count <=0 ;
  else if(ns == input_1 && wvalid)
    coef_count <= coef_count+1;
  else 
    coef_count <= coef_count;
end

always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n) 
    tap_Di_reg <= 0;
  else if(cs == input_2 && wvalid && awaddr != 12'h010)
    tap_Di_reg <= wdata;
  else 
    tap_Di_reg <= tap_Di_reg;
end

always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n) 
    tap_A_reg <= 0;
  else if(cs == input_2 && wvalid)
    if (addr_reg == 12'h020)      tap_A_reg <= 12'h000;
    else if (addr_reg == 12'h024) tap_A_reg <= 12'h004;
    else if (addr_reg == 12'h028) tap_A_reg <= 12'h008;
    else if (addr_reg == 12'h02C) tap_A_reg <= 12'h00C;
    else if (addr_reg == 12'h030) tap_A_reg <= 12'h010;
    else if (addr_reg == 12'h034) tap_A_reg <= 12'h014;
    else if (addr_reg == 12'h038) tap_A_reg <= 12'h018;
    else if (addr_reg == 12'h03C) tap_A_reg <= 12'h01C;
    else if (addr_reg == 12'h040) tap_A_reg <= 12'h020;
    else if (addr_reg == 12'h044) tap_A_reg <= 12'h024;
    else tap_A_reg <= 12'h028;
  else if(ns == calculte_1 || ns == calculte_2)
    case(coef_ptr)  // modify
      0 : tap_A_reg = 12'h000;
      1 : tap_A_reg = 12'h004;
      2 : tap_A_reg = 12'h008;
      3 : tap_A_reg = 12'h00C;
      4 : tap_A_reg = 12'h010;
      5 : tap_A_reg = 12'h014;
      6 : tap_A_reg = 12'h018;
      7 : tap_A_reg = 12'h01C;
      8 : tap_A_reg = 12'h020;
      9 : tap_A_reg = 12'h024;
      10: tap_A_reg = 12'h028;
    endcase
  else 
    tap_A_reg <= tap_A_reg;
end
always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n)
    coef_ptr <= 0;
  else if(ns == calculte_1 && coef_ptr != 0)
    coef_ptr <= coef_ptr -1 ;
  else if( ns == calculte_1)
    coef_ptr <= X_count ; 
  else if(cs == out_state && ns == calculte_2)
    coef_ptr <= 10;
  else if(cs == calculte_1 && ns == calculte_2)
    coef_ptr <= X_count ; 
  else if(ns == calculte_2 && coef_ptr != 0)
    coef_ptr <= coef_ptr -1 ;
  else 
    coef_ptr <= coef_ptr;
end
always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n)
    tap_A_reg_read <=0 ;
  else 
    tap_A_reg_read <= araddr;
end
always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n)
    X_count <= 0;
    
  else if(cs == calculte_2)
    if(X_count == ptr)
      X_count <= (X_count ==10)?0: X_count + 1 ;
    else 
       X_count  <=  X_count  ;  
  else if(cs == calculte_1 && ptr == X_count)
    X_count <= X_count + 1 ;
  else 
    X_count <= X_count;
end
//####################################################
//                   AXi Lite
//####################################################
//------------------------WRITE-------------------------//
assign awready = (cs==input_1) ? 1:0;
assign wready = (cs==input_2) ? 1:0;


always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n) 
    addr_reg <= 0;
  else if(ns==input_2)
    addr_reg <= awaddr;
  else if(ns == calculte_1)  //modify
    addr_reg <= X_count;
  else 
    addr_reg <= addr_reg;
end
//------------------------READ-------------------------//
assign arready = (arvalid )? 1:0;

assign rvalid = rvalid_reg;
assign rdata = (araddr == 0)? ap_ceeck : tap_Do;
always @(posedge axis_clk or negedge axis_rst_n) begin
    if(~axis_rst_n) 
      rvalid_reg <= 1'b0;
    else 
      rvalid_reg <= arready;
end
always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n) 
    ap_ceeck <= 0;
  else 
    ap_ceeck <= {ap_idle, ap_done, ap_start};
end
//####################################################
//                   AXi Stream
//####################################################

assign ss_tready  = (((cs == input_1 || cs == input_2) & (stream_count_ss <10)) || (cs == last_multi) ) ? 1 : 0 ; //|| (out_EN_t)

always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n)
    stream_count_ss <= 0;
  else if(stream_count_ss == 11)
    stream_count_ss <= stream_count_ss;
  else if(cs == input_1 || cs == input_2)
    stream_count_ss <= stream_count_ss +1;
  else 
    stream_count_ss <= stream_count_ss;
end
//####################################################
//                   Data SRAM
//####################################################

assign data_Di = (cs == accumulate) ? ss_tdata : data_Di_reg;
always@(*)begin
  if(cs == accumulate)
    data_A = {ptr,2'b0};
  else 
    data_A = (cs == calculte_2) ? {ptr,2'b0} : data_A_reg;
end

assign data_EN = 1'b1;
assign data_WE = data_WE_reg;

always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n) 
    data_WE_reg <= 4'b0000;
  else if(ns == accumulate)
    data_WE_reg <= 4'b1111;
  else if ((cs == input_1 || cs == input_2)& (stream_count_ss <11)) 
    data_WE_reg <= 4'b1111;
  else if(cs == calculte_1 && ss_tready == 1) // rotate
    data_WE_reg <= 4'b1111;
  else 
    data_WE_reg <= 4'b0000;
end
wire [3:0]ptr_plus = (ptr == 10) ? 0 : ptr + 1;
always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n) 
    ptr <= 0 ;
  else if(cs == out_state)
    ptr <= initial_ptr;
    /*
  else if( ((cs== input_2)||(cs== input_1))&&(ns == calculte_1))
    ptr <= initial_ptr  ;*/
  else if(cs == calculte_1 )
    if(ns == calculte_2)
      ptr <= 0;
    else 
      ptr <= (X_count == ptr)? 0 : ptr_plus ;
  else if(cs == calculte_2)
    ptr <= (X_count == ptr)? initial_ptr : ptr_plus ;
  else if(cs == last_multi)
    ptr <= ptr; 
  else if(ss_tready && ss_tvalid) // stream write to data SRAM
    ptr <= ptr_plus ;
  else 
    ptr <= ptr;
end

always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n) 
    initial_ptr <= 0;
  else if(cs == calculte_1)
    initial_ptr <=(ns == calculte_2)?0:initial_ptr;
  else if (cs == calculte_2)
    if(ns == last_multi)
   initial_ptr <= (initial_ptr == 10)? 0 : initial_ptr +1 ; 
   else 
   initial_ptr <= initial_ptr;
  else 
   initial_ptr <= initial_ptr; 
  // else if(ns == calculte_2)
  //   if(cs == calculte_1)
  //     initial_ptr<=0;
  //   else
  //     if(X_count == ptr)
  //       initial_ptr <= initial_ptr  +1 ; 
  //     else 
  //       initial_ptr <= initial_ptr;
  // else
  //   initial_ptr <= initial_ptr;
end

always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n) 
    data_A_reg <= 0;
  else begin
    case(ptr)
      0 : data_A_reg = 12'h000;
      1 : data_A_reg = 12'h004;
      2 : data_A_reg = 12'h008;
      3 : data_A_reg = 12'h00C;
      4 : data_A_reg = 12'h010;
      5 : data_A_reg = 12'h014;
      6 : data_A_reg = 12'h018;
      7 : data_A_reg = 12'h01C;
      8 : data_A_reg = 12'h020;
      9 : data_A_reg = 12'h024;
      10: data_A_reg = 12'h028;
    endcase 
  end
end
//####################################################
//                   Calculate
//####################################################
always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n) 
      pattern_number <= 0;
    else if(ss_tvalid && ss_tready) 
      pattern_number <= pattern_number + 1;
    else 
      pattern_number <= pattern_number;
end
always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n) 
    do_cal <= 0;
  else if(X_count == 2 )
    do_cal <= 1;
  else 
    do_cal <= do_cal ;

end
always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n) 
    data_Di_reg <= 0;
  else if((ss_tvalid && ss_tready || stream_count_ss < 11) && (cs == input_1 ||cs == input_2) )
    data_Di_reg <= ss_tdata;
end

always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n) 
    Xn <= 0;
  else if(cs == calculte_1 || cs == calculte_2)
    Xn <= data_Do;
  else 
    Xn <= Xn;
end
always @(*)begin
  if(cs== calculte_1 )
    mult_a = Xn;
  else if(cs== calculte_2)
    mult_a = data_Do;
  else 
    mult_a = 0;
end

always @(posedge axis_clk or negedge axis_rst_n) begin // single multi result 
  if(~axis_rst_n)
    multi_result <=0 ;
  else if(mult_EN_2)
    multi_result <=0 ;   
  else if(cs ==  calculte_1 || cs ==  calculte_2 || cs == last_multi)
    multi_result <= mult_a * tap_Do;
  else 
    multi_result <= multi_result;
end

assign mult_EN =  (tap_A == 12'h000) ? 1:0;
assign mult_EN_2 = (tap_A == 12'h028 && cs == calculte_2) ? 1:0;

always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n)
    out_EN <= 0;
  else if((tap_A == 12'h000))
    out_EN <=  1;
  else 
    out_EN <= 0;
end

always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n)
    out_EN_t <= 0;
  else  if((cs ==  calculte_1 ))
    out_EN_t <=  out_EN;
  else 
    out_EN_t <= out_EN_t;
end
always @(posedge axis_clk or negedge axis_rst_n) begin // accumulate result 
  if(~axis_rst_n)
    Yn <=0 ;
  else if(out_EN_t || mult_EN_2)
    Yn <= 0;
  else if((cs ==  calculte_1 || cs ==  calculte_2 ) || cs == last_multi || cs == accumulate)
    Yn <= Yn  +  multi_result;
  else 
    Yn <= Yn;
end
always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n)
    out_count <= 0;
  else if(out_EN_t && do_cal)
    out_count <= out_count +1 ;
  else 
    out_count <= out_count;
end

//####################################################
//                   Out_stream
//####################################################
always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n)
    out_EN_2 <= 0;
  else 
    if(out_EN_2)
         out_EN_2 <= 0;
    else
       if((tap_A == 12'h000))
        out_EN_2 <=  1;
      else 
        out_EN_2 <= 0;
end

always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n)
    out_EN_t2 <= 0;
  else  if((cs ==  calculte_2 ))
    out_EN_t2 <=  out_EN_2;
  else 
    out_EN_t2 <= out_EN_t2;
end

always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n)
    out_EN_t3 <= 0;
  else  if((cs ==  calculte_2 ))
    out_EN_t3 <=  out_EN_t2;
  else 
    out_EN_t3 <= out_EN_t3;
end

assign sm_tvalid = ((out_EN_t && do_cal) && (cs == calculte_1)) || (cs == out_state); 
assign sm_tdata = Yn;
//####################################################
//                   ap control
//####################################################
always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n)
    ap_done <= 0;
  else if(pattern_number == 600)
    ap_done <= 1;
  else 
    ap_done <= ap_done;
end

always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n)
    ap_start <= 0;
  else if(awaddr == 0 && wdata == 1 && cs != input_1 )
    ap_start <= 0;
  else if(awaddr == 0 && wdata == 1 && cs == input_1 )
    ap_start <= 1;
  else 
    ap_start <= ap_start;
end

always @(posedge axis_clk or negedge axis_rst_n) begin
  if(~axis_rst_n)
    ap_idle <= 1;
  else if(ap_start)
    ap_idle <= 0;
  else if(ap_done)
    ap_idle <= 1;
  else 
    ap_idle <= ap_idle ;
end
end
endmodule
