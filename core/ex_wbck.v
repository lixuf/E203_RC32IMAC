//该模块为最终写回仲裁模块，相当于优先选择器，长指令的优先级大于单周期指令，较易实现
//实现：1. 熟悉输入和输出，输入由二，一是alu，为单周期指令，二是oitf，为长指令
//        输出仅为寄存器堆
//		 2. 先于优先仲裁单元得出结果，在根据结果准备数据，最终与寄存器堆握手传输

`include "gen_defines.v"
module ex_wbck(
//单周期指令的写回-来自alu
  //握手信号
  input  alu_wbck_i_valid,//请求 
  output alu_wbck_i_ready,//反馈
  //数据
  input  [`E203_XLEN-1:0] alu_wbck_i_wdat,//待写回的数据
  input  [`E203_RFIDX_WIDTH-1:0] alu_wbck_i_rdidx,//待写入的寄存器索引

//长指令的写回-来自写回仲裁模块
  //握手信号
  input  longp_wbck_i_valid,//请求 
  output longp_wbck_i_ready,//准许
  //数据
  input  [`E203_FLEN-1:0] longp_wbck_i_wdat,//待写回的数据
  input  [5-1:0] longp_wbck_i_flags,//？？？
  input  [`E203_RFIDX_WIDTH-1:0] longp_wbck_i_rdidx,//待写入的寄存器的索引
  input  longp_wbck_i_rdfpu,//浮点运算，本cpu无fpu故不需理会
  
  
//与寄存器堆的通信
  output  rf_wbck_o_ena,//写使能
  output  [`E203_XLEN-1:0] rf_wbck_o_wdat,//待写回的数据
  output  [`E203_RFIDX_WIDTH-1:0] rf_wbck_o_rdidx,//待写回的寄存器的索引


  
  input  clk,
  input  rst_n
);
//与alu或长指令模块传输
  //总的握手信号
  wire wbck_i_valid;//由alu或者oitf发来的读写请求信号
  wire wbck_i_ready;//发往alu或oitf的读写请求完成反馈信号
  assign wbck_i_ready  = rf_wbck_o_ready;
  ////与alu传输  wbck_ready4xxxx 表明是否达到写回xxxx的条件
	  //握手
	  assign alu_wbck_i_ready   = wbck_ready4alu   & wbck_i_ready;//读写请求反馈
  ////与oitf传输
     //握手
	  assign longp_wbck_i_ready = wbck_ready4longp & wbck_i_ready;//读写请求反馈
	  
//写回优先仲裁部分-长指令优先
	//单周期指令写回判断--仅当无长指令发生时写回
	wire wbck_ready4alu = (~longp_wbck_i_valid);//longp_wbck_i_valid表明有长指令待写回
	wire wbck_sel_alu = alu_wbck_i_valid & wbck_ready4alu;//alu_wbck_i_valid表明有单周期指令待写回
	//长指令写回判断                                       //wbck_sel_alu表明选择写回单周期指令
	wire wbck_ready4longp = 1'b1;//因为长指令优先级最高，无需等待故为1
	wire wbck_sel_longp = longp_wbck_i_valid & wbck_ready4longp;//表明选择写回长指令
	
	
//写回
  //数据准备 wbck_sel_alu表明写回的是否是单周期指令
  wire [`E203_FLEN-1:0] wbck_i_wdat;
  wire [5-1:0] wbck_i_flags;
  wire [`E203_RFIDX_WIDTH-1:0] wbck_i_rdidx;
  wire wbck_i_rdfpu;
  assign wbck_i_valid = wbck_sel_alu ? alu_wbck_i_valid : longp_wbck_i_valid;//写回请求
  assign wbck_i_wdat  = wbck_sel_alu ? alu_wbck_i_wdat  : longp_wbck_i_wdat;//待写回的数据
  assign wbck_i_flags = wbck_sel_alu ? 5'b0  : longp_wbck_i_flags;
  assign wbck_i_rdidx = wbck_sel_alu ? alu_wbck_i_rdidx : longp_wbck_i_rdidx;//寄存器索引
  assign wbck_i_rdfpu = wbck_sel_alu ? 1'b0 : longp_wbck_i_rdfpu;//浮点运算，无需理会
  //握手
  wire rf_wbck_o_valid = wbck_i_valid;//向寄存器堆发出读写请求
  wire rf_wbck_o_ready = 1'b1;//寄存器堆一直可写，因此读写请求一直被准许
  //传输数据
  wire wbck_o_ena   = rf_wbck_o_valid & rf_wbck_o_ready;//与寄存器握手成功，输出使能
  assign rf_wbck_o_ena   = wbck_o_ena & (~wbck_i_rdfpu);//寄存器写使能
  assign rf_wbck_o_wdat  = wbck_i_wdat[`E203_XLEN-1:0];//待写入的数据
  assign rf_wbck_o_rdidx = wbck_i_rdidx;//待写入数据的寄存器索引
endmodule