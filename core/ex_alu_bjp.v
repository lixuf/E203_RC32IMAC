//该模块为alu运算控制模块之一，控制分支预测解析，弄明白与其他模块的关系是实现的关键
//功能：对于无条件跳转指令：利用公共数据通路计算下一条指令的pc，并送入写回单元
//     对于有条件跳转指令：利用公共数据通路计算是否跳转，并将跳转信息送入交付单元
//                       由交付单元来判断跳转是否出错，错了则计算新的跳转目标并冲刷流水线
//实现：1.从信息总线获取各个用于表示是何种指令的控制位
//     2. 向alu公共数据通路发送操作数-需要根据是否为无条件跳转指令判断发送哪个操作数
//     3. 向alu公共数据通路发生控制位-其中是否选用加法器需要特殊判断，仅无条件用加法器
//     4. 向交付模块写入各种有关预测的数据
//     5. 向回写单元写入下一条指令的pc用于jalr


`include "gen_defines.v"
module ex_alu_bjp(
//来自alu总控
  //握手信号
  input  bjp_i_valid, 
  output bjp_i_ready, 
  //操作数
  input  [`E203_XLEN-1:0] bjp_i_rs1,//操作数1
  input  [`E203_XLEN-1:0] bjp_i_rs2,//操作数2
  input  [`E203_XLEN-1:0] bjp_i_imm,//立即数字段
  input  [`E203_PC_SIZE-1:0] bjp_i_pc,//当前指令的pc
  //数据总线
  input  [`E203_DECINFO_BJP_WIDTH-1:0] bjp_i_info,
  
//与交付模块
  //握手信号，与alu总控来的握手信号直接连接
  output bjp_o_valid, 
  input  bjp_o_ready, 
  //来自数据总线
  output bjp_o_cmt_bjp,
  output bjp_o_cmt_mret,
  output bjp_o_cmt_dret,
  output bjp_o_cmt_fencei,
  //跳转预测
  output bjp_o_cmt_prdt,//预测结果
  output bjp_o_cmt_rslv,//真实跳转结果，无条件跳转一直为真，有条件跳转结果由公共数据通路给出
  
//与写回模块
  output [`E203_XLEN-1:0] bjp_o_wbck_wdat,//当前指令的下一条指令地址，用于jalr
  output bjp_o_wbck_err,//错误码
  
//与alu公共数据通路
  //输出至alu公共运算通路
  output [`E203_XLEN-1:0] bjp_req_alu_op1,//操作数1
  output [`E203_XLEN-1:0] bjp_req_alu_op2,//操作数2
  output bjp_req_alu_cmp_eq ,             //无条件和有条件跳转所用操作数不同
  output bjp_req_alu_cmp_ne ,
  output bjp_req_alu_cmp_lt ,
  output bjp_req_alu_cmp_gt ,
  output bjp_req_alu_cmp_ltu,
  output bjp_req_alu_cmp_gtu,
  output bjp_req_alu_add,//表示是否用加法器，只有无条件跳转指令需要
  //从运算通路输入
  input  bjp_req_alu_cmp_res,//表示是否跳转
  input  [`E203_XLEN-1:0] bjp_req_alu_add_res,//当前指令的下一条指令地址，用于jalr

  input  clk,
  input  rst_n
  
);
//来自公共信号总线
wire mret   = bjp_i_info [`E203_DECINFO_BJP_MRET ];//异常返回指令
wire dret   = bjp_i_info [`E203_DECINFO_BJP_DRET ];//中断返回指令
wire fencei = bjp_i_info [`E203_DECINFO_BJP_FENCEI ];//存储器屏障指令
wire bxx   = bjp_i_info [`E203_DECINFO_BJP_BXX ]; 
wire jump  = bjp_i_info [`E203_DECINFO_BJP_JUMP ];//表示是否为无条件跳转指令
wire rv32  = bjp_i_info [`E203_DECINFO_RV32];//表明是否为32位
wire bjp_i_bprdt = bjp_i_info [`E203_DECINFO_BJP_BPRDT ];//跳转预测

//输出到alu公共数据通路的操作数
wire wbck_link = jump;//表示是否为无条件跳转，若为无条件跳转，操作数应使用pc+4/2
assign bjp_req_alu_op1 = wbck_link ? //若不是无条件跳转应使用两个待比较的操作数
                            bjp_i_pc
                          : bjp_i_rs1;
assign bjp_req_alu_op2 = wbck_link ? 
                            (rv32 ? `E203_XLEN'd4 : `E203_XLEN'd2)
                          : bjp_i_rs2;



//写入alu公共数据通路的控制信号
assign bjp_req_alu_cmp_eq  = bjp_i_info [`E203_DECINFO_BJP_BEQ  ]; 
assign bjp_req_alu_cmp_ne  = bjp_i_info [`E203_DECINFO_BJP_BNE  ]; 
assign bjp_req_alu_cmp_lt  = bjp_i_info [`E203_DECINFO_BJP_BLT  ]; 
assign bjp_req_alu_cmp_gt  = bjp_i_info [`E203_DECINFO_BJP_BGT  ]; 
assign bjp_req_alu_cmp_ltu = bjp_i_info [`E203_DECINFO_BJP_BLTU ]; 
assign bjp_req_alu_cmp_gtu = bjp_i_info [`E203_DECINFO_BJP_BGTU ]; 
assign bjp_req_alu_add  = wbck_link;//表示是否需要加法器，仅无条件跳转需要加法器


//与交付模块传输数据
	//与alu总控和交付模块的握手
	assign bjp_o_valid     = bjp_i_valid;
	assign bjp_i_ready     = bjp_o_ready;
	//数据
	assign bjp_o_cmt_prdt  = bjp_i_bprdt;//跳转预测，静态预测，向后为真
	assign bjp_o_cmt_rslv  = jump ? 1'b1 : bjp_req_alu_cmp_res;//真实跳转结果
   assign bjp_o_cmt_bjp = bxx | jump;                       //若为jump(无条件跳转)则一定跳
   assign bjp_o_cmt_mret = mret;                            //若为有条件则用数据通路发来的控制信号
   assign bjp_o_cmt_dret = dret;
   assign bjp_o_cmt_fencei = fencei;

//与写回单元
assign bjp_o_wbck_wdat  = bjp_req_alu_add_res;//来自运算通路的下一条指令地址，用于jalr
assign bjp_o_wbck_err   = 1'b0;//一定不会出错

endmodule