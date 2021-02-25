//该模块为分支预测指令交付模块，虽然不长，但是比较琐碎，要对该cpu有一个整体认识才容易实现
//功能：1. 根据条件产生流水线冲刷信号
//     2. 若预测错误需要跳转，还需生成计算目标pc的俩个操作数
//     3. 控制mret，dret和fencei的执行，即只有在冲刷完成后才可继续执行
//实现：1. 按功能的顺序实现
//     2. icb握手后根据条件产生请求信号，待完成后传来确认信号
//     3. 根据条件用if-else判断生成操作数，特殊条件直接生成目标pc
//		 4. 用hsked表示流水线执行完毕，当hsked为真时才可使得mret，dret和fencei使能



`include "gen_defines.v"
module ex_branchslv(
  //与commit的握手信号
  input  cmt_i_valid,  
  output cmt_i_ready,
  //与commit传输的数据
  input  cmt_i_rv32,//表明是否为32位 
  input  cmt_i_dret,//表明是否为dret指令
  input  cmt_i_mret,//表明是否为mret指令
  input  cmt_i_fencei,//表明是否为fencei指令
  input  cmt_i_bjp,//表明是否为跳转指令  
  input  cmt_i_bjp_prdt,//预测结果
  input  cmt_i_bjp_rslv,//真实的结果
  input  [`E203_PC_SIZE-1:0] cmt_i_pc,//该指令的pc 
  input  [`E203_XLEN-1:0] cmt_i_imm,//立即数字段
  //来自csr的字段
  input  [`E203_PC_SIZE-1:0] csr_epc_r,//存储发生异常处的pc，用于异常返回指令
  input  [`E203_PC_SIZE-1:0] csr_dpc_r,//存储发生中断处的pc，用于中断返回指令

  //流水线冲刷相关信号
  input  nonalu_excpirq_flush_req_raw,//该信号为1会使得流水线冲刷不发生
	//流水线冲刷握手信号，握手成功表明冲刷成功
   input  brchmis_flush_ack,
   output brchmis_flush_req,
   //传输至交付模块用以计算目标pc
   output [`E203_PC_SIZE-1:0] brchmis_flush_add_op1,  
   output [`E203_PC_SIZE-1:0] brchmis_flush_add_op2,  
   //一些特殊情况，提前获得目标pc  
   output [`E203_PC_SIZE-1:0] brchmis_flush_pc,

  //当流水线冲刷完成后这些指令才能继续执行
  output  cmt_mret_ena,
  output  cmt_dret_ena,
  output  cmt_fencei_ena,

  input  clk,
  input  rst_n
  
);
//cmt_i_valid commit传来的读写请求信号
//读写请求准许信号
assign cmt_i_ready = (~cmt_i_is_branch) | 
                             (
                                 (brchmis_need_flush ? brchmis_flush_ack_pre : 1'b1) 
                                     & (~nonalu_excpirq_flush_req_raw) 
                             );
//流水线冲刷请求，应commit的请求传数据
wire brchmis_need_flush = (//表示是否需要流水线冲刷，当预测和真实不符，存储器屏障指令，
        (cmt_i_bjp & (cmt_i_bjp_prdt ^ cmt_i_bjp_rslv))//异常返回指令和中断返回指令时候
       | cmt_i_fencei //fence.i被当作特殊的流水线冲刷	  //需要冲刷流水线
       | cmt_i_mret 
       | cmt_i_dret 
      );
wire brchmis_flush_req_pre;   ///cmt_i_valid commit传来的读写请求信号
assign brchmis_flush_req_pre = cmt_i_valid & brchmis_need_flush;
assign brchmis_flush_req = brchmis_flush_req_pre & (~nonalu_excpirq_flush_req_raw);
//流水线冲刷确认，commit传来确认信号，确认刚刚传输的信号被正确接受
wire brchmis_flush_ack_pre;
assign brchmis_flush_ack_pre = brchmis_flush_ack & (~nonalu_excpirq_flush_req_raw);
//流水线冲刷信号握手成功，表明信号传输完毕
wire brchmis_flush_hsked = brchmis_flush_req & brchmis_flush_ack;



wire cmt_i_is_branch = (//表示是否需要分支跳转
         cmt_i_bjp 
       | cmt_i_fencei 
       | cmt_i_mret 
       | cmt_i_dret 
      );

  

//pc在各种情况下的取值   格式：情况->取值
//DRET->DPC   MRET->EPC   接受预测但预测错误->pc+2/4(取决下一个是16位指令还是32位的)
//预测未被采取但应该采取->pc+offset
assign brchmis_flush_add_op1 = cmt_i_dret ? csr_dpc_r : cmt_i_mret ? csr_epc_r : cmt_i_pc; 
assign brchmis_flush_add_op2 = cmt_i_dret ? `E203_PC_SIZE'b0 : cmt_i_mret ? `E203_PC_SIZE'b0 :
                                 (cmt_i_fencei | cmt_i_bjp_prdt) ? (cmt_i_rv32 ? `E203_PC_SIZE'd4 : `E203_PC_SIZE'd2)
                                    : cmt_i_imm[`E203_PC_SIZE-1:0];

//冲刷请求pc，也是从冲刷请求pc开始重新执行
assign brchmis_flush_pc = (cmt_i_fencei | (cmt_i_bjp & cmt_i_bjp_prdt)) ? (cmt_i_pc + (cmt_i_rv32 ? `E203_PC_SIZE'd4 : `E203_PC_SIZE'd2)) :
                          (cmt_i_bjp & (~cmt_i_bjp_prdt)) ? (cmt_i_pc + cmt_i_imm[`E203_PC_SIZE-1:0]) :
                          cmt_i_dret ? csr_dpc_r : csr_epc_r ;

//当冲刷成功后mert，dret和fencei指令才可以继续执行  
assign cmt_mret_ena = cmt_i_mret & brchmis_flush_hsked;
assign cmt_dret_ena = cmt_i_dret & brchmis_flush_hsked;
assign cmt_fencei_ena = cmt_i_fencei & brchmis_flush_hsked;

  

endmodule                                 