//该模块为ALU中的普通运算单元，数据数据的流动即可轻松实现
//功能：利用信息总线判断是哪个运算，包括整型的加、减、异或、左移、逻辑
//      右移、算数右移、且、或等。判断后交付共享数据通路，
//			运算结果由共享数据通路回传回来，并交付给写回单元进行写回。
//实现：1.注意nop与addl编码一致需要特殊判断
//		 2. 实现运算时注意，该单元不进行运算，只是判断使用何种运算
//        并交付参加运算的；两个操作数，交付至共享数据通路，运算完后
//			 经过该模块写回。
`include "gen_defines.v"
module ex_alu_rglr(
//来自alu总控的数据
  //握手信号
  input  alu_i_valid,//来自alu总控的读写请求信号 
  output alu_i_ready,//发生给alu总控的读写请求准许信号  
  //传输数据
  input  [`E203_XLEN-1:0] alu_i_rs1,//操作数1
  input  [`E203_XLEN-1:0] alu_i_rs2,//操作数2
  input  [`E203_XLEN-1:0] alu_i_imm,//立即数
  input  [`E203_PC_SIZE-1:0] alu_i_pc,//当前指令pc，可能作为运算的操作数
  input  [`E203_DECINFO_ALU_WIDTH-1:0] alu_i_info,//信息总线
//输出至写回单元
  //握手信号  
  output alu_o_valid,//输出至写回单元的读写请求信号 
  input  alu_o_ready,//来自写回单元的读写准许信号
  //传输数据
  output [`E203_XLEN-1:0] alu_o_wbck_wdat,//结果，来自共享运算数据通路
  output alu_o_wbck_err,//表示是否产生错误或者异常   
  output alu_o_cmt_ecall,   
  output alu_o_cmt_ebreak,   
  output alu_o_cmt_wfi,  
//共享数据通路
  //判断使用何种运算-输出
  output alu_req_alu_add ,
  output alu_req_alu_sub ,
  output alu_req_alu_xor ,
  output alu_req_alu_sll ,
  output alu_req_alu_srl ,
  output alu_req_alu_sra ,
  output alu_req_alu_or  ,
  output alu_req_alu_and ,
  output alu_req_alu_slt ,
  output alu_req_alu_sltu,
  output alu_req_alu_lui ,
  //操作数-输出
  output [`E203_XLEN-1:0] alu_req_alu_op1,
  output [`E203_XLEN-1:0] alu_req_alu_op2,
  //结果-从共享数据通路输入，送至写回单元
  input  [`E203_XLEN-1:0] alu_req_alu_res,

  input  clk,
  input  rst_n  
 );
 
 



  

  
  //共享数据通路
    //判断使用何种运算
        //在RISC5中nop与addi编码一致，顾需要增加一个判断，判定是否位nop
	 assign alu_req_alu_add  = alu_i_info [`E203_DECINFO_ALU_ADD ] & (~nop);
	 assign alu_req_alu_sub  = alu_i_info [`E203_DECINFO_ALU_SUB ];
	 assign alu_req_alu_xor  = alu_i_info [`E203_DECINFO_ALU_XOR ];
	 assign alu_req_alu_sll  = alu_i_info [`E203_DECINFO_ALU_SLL ];
	 assign alu_req_alu_srl  = alu_i_info [`E203_DECINFO_ALU_SRL ];
    assign alu_req_alu_sra  = alu_i_info [`E203_DECINFO_ALU_SRA ];
	 assign alu_req_alu_or   = alu_i_info [`E203_DECINFO_ALU_OR  ];
	 assign alu_req_alu_and  = alu_i_info [`E203_DECINFO_ALU_AND ];
    assign alu_req_alu_slt  = alu_i_info [`E203_DECINFO_ALU_SLT ];
    assign alu_req_alu_sltu = alu_i_info [`E203_DECINFO_ALU_SLTU];
	 assign alu_req_alu_lui  = alu_i_info [`E203_DECINFO_ALU_LUI ];
    //操作数
	 wire op2imm  = alu_i_info [`E203_DECINFO_ALU_OP2IMM ];//表示操作数2是否使用立即数
    wire op1pc   = alu_i_info [`E203_DECINFO_ALU_OP1PC  ];//表示操作数1是否使用pc
	 assign alu_req_alu_op1  = op1pc  ? alu_i_pc  : alu_i_rs1;
    assign alu_req_alu_op2  = op2imm ? alu_i_imm : alu_i_rs2;
  
  
  //输出icb
   //握手信号
   assign alu_o_valid = alu_i_valid;//其中中间为i是alu总控的信号
   assign alu_i_ready = alu_o_ready;//中间为o是写回单元的信号
                                    //alu总控与写回直接握手
   //传输数据，结果来自共享数据通路
   assign alu_o_wbck_wdat = alu_req_alu_res;  
      //来自信息总线
   wire nop    = alu_i_info [`E203_DECINFO_ALU_NOP ] ;
   wire ecall  = alu_i_info [`E203_DECINFO_ALU_ECAL ];
   wire ebreak = alu_i_info [`E203_DECINFO_ALU_EBRK ];
   wire wfi    = alu_i_info [`E203_DECINFO_ALU_WFI ];
   assign alu_o_cmt_ecall  = ecall;   
   assign alu_o_cmt_ebreak = ebreak;   
   assign alu_o_cmt_wfi = wfi;
      //判断是否异常和错误
   assign alu_o_wbck_err = alu_o_cmt_ecall | alu_o_cmt_ebreak | alu_o_cmt_wfi;

endmodule  
  