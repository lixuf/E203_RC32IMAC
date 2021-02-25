`include "gen_defines.v"
module ex_alu_lsuagu(
//与alu总控
  input  agu_i_valid, 
  output agu_i_ready, 

  input  [`E203_XLEN-1:0] agu_i_rs1,//操作数1
  input  [`E203_XLEN-1:0] agu_i_rs2,//操作数2
  input  [`E203_XLEN-1:0] agu_i_imm,//立即数
  input  [`E203_DECINFO_AGU_WIDTH-1:0] agu_i_info,//信息总线
  input  [`E203_ITAG_WIDTH-1:0] agu_i_itag,//指令在oitf中的位置

  output agu_i_longpipe,//对于地址对齐的访存指令，当作长指令执行
                        //该信号表示当前指令是否当作长指令即为地址对齐的访存指令

  input  flush_req,//表示有流水线冲刷发生
  input  flush_puls,//??

  output amo_wait,//A型扩展指令在执行过程中不可打断，当状态机开始即代表A型扩展指
                  //令正在执行，该信号表示有A型扩展指令执行，其他指令需要等待
  input  oitf_empty,//表示oitf为空，即无长指令执行

//与写回单元&交付单元
  output agu_o_valid, 
  input  agu_o_ready, 
///与写回单元
   output [`E203_XLEN-1:0] agu_o_wbck_wdat,//待写回的数据
   output agu_o_wbck_err,//错误码
///与交付单元
   output agu_o_cmt_misalgn,//地址非对齐异常
   output agu_o_cmt_ld,//产生访存错误的为load指令
   output agu_o_cmt_stamo,//产生访存错误的为A扩展指令或者是store指令
   output agu_o_cmt_buserr,//访存错误异常
   output [`E203_ADDR_SIZE-1:0] agu_o_cmt_badaddr,//访存错误的地址
	
//与lsu--通过icb协议
////cmd通道
  //握手
  output                       agu_icb_cmd_valid,//传输给lsu的读写请求指令
  input                        agu_icb_cmd_ready,//lsu传来的读写请求准许指令
  //数据
  output [`E203_ADDR_SIZE-1:0] agu_icb_cmd_addr,
  output                       agu_icb_cmd_read,//表示是否为读或则写
  output [`E203_XLEN-1:0]      agu_icb_cmd_wdata,//待写入的数据
  output [`E203_XLEN/8-1:0]    agu_icb_cmd_wmask,//写入mask，对于按字节或半字访存防止其他位被覆盖 
  output                       agu_icb_cmd_back2agu, 
  output                       agu_icb_cmd_lock,
  output                       agu_icb_cmd_excl,//来自信息总线的agu_i_excl
  output [1:0]                 agu_icb_cmd_size,//访问存储器的基本单位 字节/字/半字
  output [`E203_ITAG_WIDTH-1:0]agu_icb_cmd_itag,//当前指令在oitf中的位置
  output                       agu_icb_cmd_usign,//来自信息总线agu_i_usign
////rsp通道
  input                        agu_icb_rsp_valid,//反馈请求信号 
  output                       agu_icb_rsp_ready,//反馈请求准许信号
  input                        agu_icb_rsp_err,//传输的错误码
  input                        agu_icb_rsp_excl_ok,
  input  [`E203_XLEN-1:0]      agu_icb_rsp_rdata,//

//与alu公共数据通路
  output [`E203_XLEN-1:0] agu_req_alu_op1,//操作数1
  output [`E203_XLEN-1:0] agu_req_alu_op2,//操作数2
  //操作请求，表示需要何种运算
  output agu_req_alu_swap,
  output agu_req_alu_add ,
  output agu_req_alu_and ,
  output agu_req_alu_or  ,
  output agu_req_alu_xor ,
  output agu_req_alu_max ,
  output agu_req_alu_min ,
  output agu_req_alu_maxu,
  output agu_req_alu_minu,
  input  [`E203_XLEN-1:0] agu_req_alu_res,//公共数据通路的运算结果

  //共享的66位数据缓冲器，该66位缓冲器由两个33位寄存器组成
  ///低33位
  output agu_sbf_0_ena,
  output [`E203_XLEN-1:0] agu_sbf_0_nxt,
  input  [`E203_XLEN-1:0] agu_sbf_0_r,
  ///高33位
  output agu_sbf_1_ena,
  output [`E203_XLEN-1:0] agu_sbf_1_nxt,
  input  [`E203_XLEN-1:0] agu_sbf_1_r,

  input  clk,
  input  rst_n

  );
  
  
//判断是否满足继续执行下一条指令的条件
                           //icb_sta_is_idle A型扩展指令执行阶段的状态机的第一个状态，表示无A指令执行
assign amo_wait = ~icb_sta_is_idle; //A指令执行的时候不可被打断，需执行完毕才可执行其他指令
wire flush_block = flush_req & icb_sta_is_idle;//当有A指令执行或者有流水线冲刷
                                                     //发生，则无法执行下一个指令

																	  
//从信息总线中接收数据
wire       agu_i_load    = agu_i_info [`E203_DECINFO_AGU_LOAD   ] & (~flush_block);//表示需执行load指令
wire       agu_i_store   = agu_i_info [`E203_DECINFO_AGU_STORE  ] & (~flush_block);//表示需执行store指令
wire       agu_i_amo     = agu_i_info [`E203_DECINFO_AGU_AMO    ] & (~flush_block);//表示需执行A指令

wire [1:0] agu_i_size    = agu_i_info [`E203_DECINFO_AGU_SIZE   ];//访存的基本单位
wire       agu_i_usign   = agu_i_info [`E203_DECINFO_AGU_USIGN  ];
wire       agu_i_excl    = agu_i_info [`E203_DECINFO_AGU_EXCL   ];
////需执行哪一个A指令
	wire       agu_i_amoswap = agu_i_info [`E203_DECINFO_AGU_AMOSWAP];
	wire       agu_i_amoadd  = agu_i_info [`E203_DECINFO_AGU_AMOADD ];
	wire       agu_i_amoand  = agu_i_info [`E203_DECINFO_AGU_AMOAND ];
	wire       agu_i_amoor   = agu_i_info [`E203_DECINFO_AGU_AMOOR  ];
	wire       agu_i_amoxor  = agu_i_info [`E203_DECINFO_AGU_AMOXOR ];
	wire       agu_i_amomax  = agu_i_info [`E203_DECINFO_AGU_AMOMAX ];
	wire       agu_i_amomin  = agu_i_info [`E203_DECINFO_AGU_AMOMIN ];
	wire       agu_i_amomaxu = agu_i_info [`E203_DECINFO_AGU_AMOMAXU];
	wire       agu_i_amominu = agu_i_info [`E203_DECINFO_AGU_AMOMINU];

	
	



 

 
  
//访存非对齐判断 
///判断访问的基本单位
wire agu_i_size_b  = (agu_i_size == 2'b00);//以字节为基本访问单位
wire agu_i_size_hw = (agu_i_size == 2'b01);//以半字为基本访问单位
wire agu_i_size_w  = (agu_i_size == 2'b10);//以字为基本访问单位
///判断访问地址是否与基本访问单位对齐
   //表示访存是否与基本访问单位对齐，下面要分具体A指令还是load or store
   wire agu_i_addr_unalgn = 
   (agu_i_size_hw &  agu_icb_cmd_addr[0])//若地址最低位不为0，则意味着和半字不对齐
   | (agu_i_size_w  &  (|agu_icb_cmd_addr[1:0]));//若地址最低两位不为0，则意味着和字不对齐
  
	//A扩展指令的访存非对齐信号,A指令需要状态机因此其访存不对称信号需要保持住，直到指令执行完毕  
                            //state_last_exit_ena表明正在执行的指令执行完毕的退出使能信号
                            //state_idle_exit_ena表明开始执行指令，退出闲置状态
	wire unalgn_flg_r;
	wire unalgn_flg_set = agu_i_addr_unalgn & state_idle_exit_ena;//当访存非对齐且该指令为A指令
	wire unalgn_flg_clr = unalgn_flg_r & state_last_exit_ena;//当该信号为1且重新开始状态机(重新开始执行A指令)
	wire unalgn_flg_ena = unalgn_flg_set | unalgn_flg_clr;
	wire unalgn_flg_nxt = unalgn_flg_set | (~unalgn_flg_clr);
	sirv_gnrl_dfflr #(1) unalgn_flg_dffl (unalgn_flg_ena, unalgn_flg_nxt, unalgn_flg_r, clk, rst_n);

	//最终得到的表示是否对齐的控制信号
   wire agu_addr_unalgn = icb_sta_is_idle ? agu_i_addr_unalgn : unalgn_flg_r;//icb_sta_is_idle==1表示该指令不是A指令
                                                                          //==0 表示该指令是A指令
///节省门，就像解码器部分，提前把可能用到的信号用逻辑门组合起来																							  
wire agu_i_unalgnld = (agu_addr_unalgn & agu_i_load);//表示该指令为Load且访存不对齐
wire agu_i_unalgnst = (agu_addr_unalgn & agu_i_store);//表示该指令为store且访存非对齐
wire agu_i_unalgnldst = (agu_i_unalgnld | agu_i_unalgnst);//表示store或者load非对齐
wire agu_i_algnld = (~agu_addr_unalgn) & agu_i_load;//表示该指令为load且对齐
wire agu_i_algnst = (~agu_addr_unalgn) & agu_i_store;//表示该指令为store且对齐
wire agu_i_algnldst = (agu_i_algnld | agu_i_algnst);//表示store或者load对齐
wire agu_i_unalgnamo = (agu_addr_unalgn & agu_i_amo);//表示该指令为A指令且不对齐
wire agu_i_algnamo = ((~agu_addr_unalgn) & agu_i_amo) ;//表示该指令为A指令且对齐
wire agu_i_ofst0  = agu_i_amo | ((agu_i_load | agu_i_store) & agu_i_excl);//表明该指令为A指令或者存在异常的load或store指令





						 
//A指令和访存指令的状态机部分
///状态控制部分
	//状态机参数设置
	localparam ICB_STATE_WIDTH = 4;//状态码宽度，共7个状态
	localparam ICB_STATE_IDLE = 4'd0;//状态0闲置状态，表明无A指令执行请求，当请求到来时发送第一次读操作，之后进入下一个状态
	localparam ICB_STATE_1ST  = 4'd1;//状态1即开始执行A指令，等待第一次发送的读操作的读数据返回
	localparam ICB_STATE_WAIT2ND  = 4'd2;//状态2，发送第二次写操作
	localparam ICB_STATE_2ND  = 4'd3;//状态3，等待第二次写操作的反馈
	localparam ICB_STATE_AMOALU  = 4'd4;//状态4，收到第一次读操作的数据，复用ALU运算
	localparam ICB_STATE_AMORDY  = 4'd5;//状态5，运算结束并收到运算结果，发送写回操作，写回操作反馈后进入下一个状态
	localparam ICB_STATE_WBCK  = 4'd6;//状态6，将指令的结果写回结果寄存器
	//状态机用于转换状态的信号
	///指示下一个状态
	wire [ICB_STATE_WIDTH-1:0] state_idle_nxt   ;//当前为状态0时的下一个状态
	wire [ICB_STATE_WIDTH-1:0] state_1st_nxt    ;//当前为状态1时的下一个状态
	wire [ICB_STATE_WIDTH-1:0] state_wait2nd_nxt;//当前为状态2时的下一个状态
	wire [ICB_STATE_WIDTH-1:0] state_2nd_nxt    ;//当前为状态3时的下一个状态
	wire [ICB_STATE_WIDTH-1:0] state_amoalu_nxt ;//当前为状态4时的下一个状态
	wire [ICB_STATE_WIDTH-1:0] state_amordy_nxt ;//当前为状态5时的下一个状态
	wire [ICB_STATE_WIDTH-1:0] state_wbck_nxt ;//当前为状态6时的下一个状态
	///指示是否可以退出当前状态进入下一个状态
   wire state_idle_exit_ena     ;//离开状态0的使能信号，该信号为1时表明可进入下一个状态
	wire state_1st_exit_ena      ;//离开状态1的使能信号，该信号为1时表明可进入下一个状态
	wire state_wait2nd_exit_ena  ;//离开状态2的使能信号，该信号为1时表明可进入下一个状态
	wire state_2nd_exit_ena      ;//离开状态3的使能信号，该信号为1时表明可进入下一个状态
	wire state_amoalu_exit_ena   ;//离开状态4的使能信号，该信号为1时表明可进入下一个状态
	wire state_amordy_exit_ena   ;//离开状态5的使能信号，该信号为1时表明可进入下一个状态
	wire state_wbck_exit_ena   ;//离开状态6的使能信号，该信号为1时表明可进入下一个状态
   ///指示当前为何状态，提前定义好以节省门
   wire   icb_sta_is_idle    = (icb_state_r == ICB_STATE_IDLE   );//表明当前为状态0
   wire   icb_sta_is_1st     = (icb_state_r == ICB_STATE_1ST    );//表明当前为状态1
   wire   icb_sta_is_amoalu  = (icb_state_r == ICB_STATE_AMOALU );//表明当前为状态4
   wire   icb_sta_is_amordy  = (icb_state_r == ICB_STATE_AMORDY );//表明当前为状态5
   wire   icb_sta_is_wait2nd = (icb_state_r == ICB_STATE_WAIT2ND);//表明当前为状态2
   wire   icb_sta_is_2nd     = (icb_state_r == ICB_STATE_2ND    );//表明当前为状态3
   wire   icb_sta_is_wbck    = (icb_state_r == ICB_STATE_WBCK    );//表明当前为状态6
	//状态机主体
	///状态0
   assign state_idle_exit_ena = icb_sta_is_idle & ( agu_i_algnamo & oitf_empty) 
                                & agu_icb_cmd_hsked & (~flush_pulse);
   assign state_idle_nxt = ICB_STATE_1ST;
	///状态1
	assign state_1st_exit_ena = icb_sta_is_1st & (agu_icb_rsp_hsked | flush_pulse);
   assign state_1st_nxt      = flush_pulse ? ICB_STATE_IDLE : ( ICB_STATE_AMOALU );
	///状态4
	assign state_amoalu_exit_ena = icb_sta_is_amoalu & ( 1'b1 | flush_pulse);
   assign state_amoalu_nxt = flush_pulse ? ICB_STATE_IDLE : ICB_STATE_AMORDY;
	///状态5
	assign state_amordy_exit_ena = icb_sta_is_amordy & ( 1'b1 | flush_pulse);
   assign state_amordy_nxt      = flush_pulse ? ICB_STATE_IDLE : ( ICB_STATE_WAIT2ND );
	///状态2
	assign state_wait2nd_exit_ena = icb_sta_is_wait2nd & (agu_icb_cmd_ready | flush_pulse);
   assign state_wait2nd_nxt = flush_pulse ? ICB_STATE_IDLE : ICB_STATE_2ND;
	///状态3
   assign state_2nd_exit_ena = icb_sta_is_2nd & (agu_icb_rsp_hsked | flush_pulse);
   assign state_2nd_nxt      = flush_pulse ? ICB_STATE_IDLE : ( ICB_STATE_WBCK );
	///状态6
	assign state_wbck_exit_ena = icb_sta_is_wbck & (agu_o_ready | flush_pulse);
   assign state_wbck_nxt      = flush_pulse ? ICB_STATE_IDLE :  ( ICB_STATE_IDLE );
	//更新状态机的寄存器
	wire icb_state_ena;//更新使能，当任一状态的退出使能时即置一
	assign icb_state_ena = 1'b0 
            | state_idle_exit_ena | state_1st_exit_ena  
            | state_amoalu_exit_ena  | state_amordy_exit_ena  
            | state_wait2nd_exit_ena | state_2nd_exit_ena   
            | state_wbck_exit_ena ;
	wire [ICB_STATE_WIDTH-1:0] icb_state_nxt;//待写入寄存器的数据
	assign icb_state_nxt = //and-or多选器，由状态退出使能做为选择信号
              ({ICB_STATE_WIDTH{1'b0}})
            | ({ICB_STATE_WIDTH{state_idle_exit_ena   }} & state_idle_nxt   )
            | ({ICB_STATE_WIDTH{state_1st_exit_ena    }} & state_1st_nxt    )
            | ({ICB_STATE_WIDTH{state_amoalu_exit_ena }} & state_amoalu_nxt )
            | ({ICB_STATE_WIDTH{state_amordy_exit_ena }} & state_amordy_nxt )
            | ({ICB_STATE_WIDTH{state_wait2nd_exit_ena}} & state_wait2nd_nxt)
            | ({ICB_STATE_WIDTH{state_2nd_exit_ena    }} & state_2nd_nxt    )
            | ({ICB_STATE_WIDTH{state_wbck_exit_ena   }} & state_wbck_nxt   );
	wire [ICB_STATE_WIDTH-1:0] icb_state_r;//寄存器当前存储的数据
	sirv_gnrl_dfflr #(ICB_STATE_WIDTH) icb_state_dfflr (icb_state_ena, icb_state_nxt, icb_state_r, clk, rst_n);
	//状态机退出部分，即完成指令的执行开始执行新的指令
	wire  icb_sta_is_last = icb_sta_is_wbck;//表示当前执行到最后一个状态
	wire state_last_exit_ena;
	assign state_last_exit_ena = state_wbck_exit_ena;//表明当前最后一个状态准备退出，指令已经执行完毕
	
	
	
	
	
//剩余缓存
///下面需要用到的控制信号
wire amo_1stuop = icb_sta_is_1st & agu_i_algnamo;//表明为访存对齐的A指令的状态1
                                                 //状态1为等待第一次读操作返回数据
																 //leftover0存该数据
wire amo_2nduop = icb_sta_is_2nd & agu_i_algnamo;//表明为访存对齐的A指令的状态3
                                                 //状态3为第二次写操作等待反馈
///0--存第一次读操作返回的数据
wire leftover_ena;//写使能，当状态1或3且反馈信道传输完毕时使能
assign leftover_ena = agu_icb_rsp_hsked & ( amo_1stuop | amo_2nduop  );
wire [`E203_XLEN-1:0] leftover_nxt;//待写入数据
assign leftover_nxt = {`E203_XLEN{1'b0}}//状态1写入读取到的数据，状态3不改变寄存器内数据
                     | ({`E203_XLEN{amo_1stuop}} & agu_icb_rsp_rdata)
                     | ({`E203_XLEN{amo_2nduop }} & leftover_r);
wire [`E203_XLEN-1:0] leftover_r;
	//复用ALU多周期乘除法的寄存器
	assign agu_sbf_0_ena = leftover_ena;
	assign agu_sbf_0_nxt = leftover_nxt;
	assign leftover_r    = agu_sbf_0_r;
///1--存算术运算结果
wire [`E203_XLEN-1:0] leftover_1_r;
wire leftover_1_ena;
assign leftover_1_ena = icb_sta_is_amoalu ;
wire [`E203_XLEN-1:0] leftover_1_nxt;
assign leftover_1_nxt = agu_req_alu_res;
	//复用ALU多周期乘除法的寄存器
	assign agu_sbf_1_ena   = leftover_1_ena;
	assign agu_sbf_1_nxt   = leftover_1_nxt;
	assign leftover_1_r = agu_sbf_1_r;
///err--leftover_0的错误码
wire leftover_err_nxt;
assign leftover_err_nxt = 
         ({{amo_1stuop}} & agu_icb_rsp_err)
         | ({{amo_2nduop}} & (agu_icb_rsp_err | leftover_err_r));
wire leftover_err_r;
sirv_gnrl_dfflr #(1) icb_leftover_err_dfflr (leftover_ena, leftover_err_nxt, leftover_err_r, clk, rst_n);





//向alu发送运算请求--要熟悉每个指令，大致分为两种，一访存指令有普通的和A指令，二A指令的其他运算
//操作数
assign agu_req_alu_op1 =  icb_sta_is_idle   ? agu_i_rs1: icb_sta_is_amoalu ? leftover_r
                          : (agu_i_amo & (icb_sta_is_wait2nd | icb_sta_is_2nd | icb_sta_is_wbck)) ? agu_i_rs1;

wire [`E203_XLEN-1:0] agu_addr_gen_op2 = agu_i_ofst0 ? `E203_XLEN'b0 : agu_i_imm;
assign agu_req_alu_op2 =  icb_sta_is_idle   ? agu_addr_gen_op2 
                          : icb_sta_is_amoalu ? agu_i_rs2
                          : (agu_i_amo & (icb_sta_is_wait2nd | icb_sta_is_2nd | icb_sta_is_wbck)) ? agu_addr_gen_op2;
//运算请求
assign agu_req_alu_add  = (icb_sta_is_amoalu & agu_i_amoadd)
                           | (agu_i_amo & (icb_sta_is_wait2nd | icb_sta_is_2nd | icb_sta_is_wbck))
                           | icb_sta_is_idle ;
assign agu_req_alu_swap = (icb_sta_is_amoalu & agu_i_amoswap );
assign agu_req_alu_and  = (icb_sta_is_amoalu & agu_i_amoand  );
assign agu_req_alu_or   = (icb_sta_is_amoalu & agu_i_amoor   );
assign agu_req_alu_xor  = (icb_sta_is_amoalu & agu_i_amoxor  );
assign agu_req_alu_max  = (icb_sta_is_amoalu & agu_i_amomax  );
assign agu_req_alu_min  = (icb_sta_is_amoalu & agu_i_amomin  );
assign agu_req_alu_maxu = (icb_sta_is_amoalu & agu_i_amomaxu );
assign agu_req_alu_minu = (icb_sta_is_amoalu & agu_i_amominu );


//向ALU总控反馈
assign agu_i_ready =//读写请求完成反馈
       agu_i_algnamo ? state_last_exit_ena :
      (agu_icb_cmd_ready & agu_o_ready) ;
assign agu_i_longpipe = agu_i_algnldst;//若非对齐，则按长指令执行




//与写回单元通讯，经由写回到commit
assign agu_o_valid = //读写请求信号
      icb_sta_is_last 
      |( agu_i_valid & ( agu_i_algnldst 
      | agu_i_unalgnldst
      | agu_i_unalgnamo )
      & agu_icb_cmd_ready);
assign agu_o_wbck_wdat = ({`E203_XLEN{agu_i_algnamo  }} & leftover_r) 
                       | ({`E203_XLEN{agu_i_unalgnamo}} & `E203_XLEN'b0) ;
assign agu_o_wbck_err = agu_o_cmt_buserr | agu_o_cmt_misalgn;		 
///去commit---全是异常相关
assign agu_o_cmt_buserr = (agu_i_algnamo    & leftover_err_r) 
                        | (agu_i_unalgnamo  & 1'b0) ;
assign agu_o_cmt_badaddr = agu_icb_cmd_addr;
assign agu_o_cmt_misalgn = agu_i_unalgnamo 
                        | (agu_i_unalgnldst) ;
assign agu_o_cmt_ld      = agu_i_load & (~agu_i_excl); 
assign agu_o_cmt_stamo   = agu_i_store | agu_i_amo | agu_i_excl;





//通过icb与lsu通讯
wire [`E203_XLEN-1:0] algnst_wdata = //待写回数据，按照访问尺寸分割出来
            ({`E203_XLEN{agu_i_size_b }} & {4{agu_i_rs2[ 7:0]}})
          | ({`E203_XLEN{agu_i_size_hw}} & {2{agu_i_rs2[15:0]}})
          | ({`E203_XLEN{agu_i_size_w }} & {1{agu_i_rs2[31:0]}});
wire [`E203_XLEN/8-1:0] algnst_wmask = //写回数据的mask，防止半字字节访问覆盖掉其他位的数据
            ({`E203_XLEN/8{agu_i_size_b }} & (4'b0001 << agu_icb_cmd_addr[1:0]))
          | ({`E203_XLEN/8{agu_i_size_hw}} & (4'b0011 << {agu_icb_cmd_addr[1],1'b0}))
          | ({`E203_XLEN/8{agu_i_size_w }} & (4'b1111));

///cmd通道
   //握手
	assign agu_icb_cmd_valid = //读写请求信号
					((agu_i_algnldst & agu_i_valid)
				 & (agu_o_ready))
				 | (agu_i_algnamo & (
					(icb_sta_is_idle & agu_i_valid 
				 & agu_o_ready)
				 | (icb_sta_is_wait2nd)))
				 | (agu_i_unalgnamo & 1'b0) ;
	wire agu_icb_cmd_hsked = agu_icb_cmd_valid & agu_icb_cmd_ready;//握手成功
	//发送数据
	assign agu_icb_cmd_addr = agu_req_alu_res[`E203_ADDR_SIZE-1:0];
	assign agu_icb_cmd_read = //读请求
					(agu_i_algnldst & agu_i_load) 
				 | (agu_i_algnamo & icb_sta_is_idle & 1'b1)
				 | (agu_i_algnamo & icb_sta_is_wait2nd & 1'b0) ;
	assign agu_icb_cmd_wdata = 
			agu_i_amo ? leftover_1_r :
			algnst_wdata;
	assign agu_icb_cmd_wmask =
			agu_i_amo ? (leftover_err_r ? 4'h0 : 4'hF) :
			algnst_wmask; 
	assign agu_icb_cmd_back2agu =agu_i_algnamo  ;
	assign agu_icb_cmd_lock     = (agu_i_algnamo & icb_sta_is_idle);
	assign agu_icb_cmd_excl     = agu_i_excl;
	assign agu_icb_cmd_itag     = agu_i_itag;
	assign agu_icb_cmd_usign    = agu_i_usign;
	assign agu_icb_cmd_size     =  agu_i_size;
///rsp通道
assign agu_icb_rsp_ready = 1'b1;//读写反馈请求准许信号
wire agu_icb_rsp_hsked = agu_icb_rsp_valid & agu_icb_rsp_ready;//握手成功

   





          



endmodule                     