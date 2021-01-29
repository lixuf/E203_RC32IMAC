`include "gen_defines.v"

module ifu_ift2icb(//接收取指请求和pc，从相应存储器取指令
	
	//与pc_fetch的通讯
	////cmd通道
	input  ifu_req_valid,//fetch发来的读写信号
	output ifu_req_ready,//读写准许信号
	input  [`PC_Size-1:0] ifu_req_pc,//收到的当前的用来取指的pc
	input  ifu_req_seq,//表明该次操作是否为顺序取指
	input  ifu_req_seq_rv32,//表明是否为32位
	input  [`E203_PC_SIZE-1:0] ifu_req_last_pc,//上次取指的pc
	////rsp通道
	output ifu_rsp_valid,//向fetch发送读写反馈信号
	input  ifu_rsp_ready,//fetch发来的读写反馈准许信号
	output ifu_rsp_err, //向fetch发送的错误码
	output [32-1:0] ifu_rsp_instr, //向fetch发送的pc取来的指令
	
	//与itcm通信
	////cmd通道
	output ifu2itcm_icb_cmd_valid, 
   input  ifu2itcm_icb_cmd_ready, 
   output [`E203_ITCM_ADDR_WIDTH-1:0]   ifu2itcm_icb_cmd_addr, 
	////rsq通道
	input  ifu2itcm_icb_rsp_valid, 
   output ifu2itcm_icb_rsp_ready, 
   input  ifu2itcm_icb_rsp_err,  
   input  [`E203_ITCM_DATA_WIDTH-1:0] ifu2itcm_icb_rsp_rdata, 
	
	//于biu通讯
	////cmd通道
	output ifu2biu_icb_cmd_valid, 
	input  ifu2biu_icb_cmd_ready,
	output [`E203_ADDR_SIZE-1:0]   ifu2biu_icb_cmd_addr, 
	////rsp通道
	input  ifu2biu_icb_rsp_valid,
	output ifu2biu_icb_rsp_ready, 
	input  ifu2biu_icb_rsp_err,
	input  [`E203_SYSMEM_DATA_WIDTH-1:0] ifu2biu_icb_rsp_rdata, 
	
	
	input [`E203_ADDR_SIZE-1:0] itcm_region_indic,//itcm的基地址
	input  ifu2itcm_holdup,//表明上次访问的是否为itcm
	input  itcm_nohold,//表明itcm是否无holdup特性
	input  clk,
	input  rst_n
	);
	
//产生地址
////向itcm读写的地址 //还需好好研读
wire icb_addr_sel_1stnxtalgn = holdup2leftover_sel;
wire icb_addr_sel_2ndnxtalgn = req_need_2uop_r &
                     (
                          icb_sta_is_1st 
                       |  icb_sta_is_wait2nd
                     );
wire icb_addr_sel_cur = (~icb_addr_sel_1stnxtalgn) & (~icb_addr_sel_2ndnxtalgn);
wire [`E203_PC_SIZE-1:0] nxtalgn_plus_offset = 	icb_addr_sel_2ndnxtalgn ? `E203_PC_SIZE'd2 :
																ifu_req_seq_rv32        ? `E203_PC_SIZE'd6 :
																								  `E203_PC_SIZE'd4;
wire [`E203_PC_SIZE-1:0] icb_algn_nxt_lane_addr = ifu_req_last_pc + nxtalgn_plus_offset;
wire [`E203_PC_SIZE-1:0] ifu_icb_cmd_addr;//访问存储器的地址		
assign ifu_icb_cmd_addr = 
      ({`E203_PC_SIZE{icb_addr_sel_1stnxtalgn | icb_addr_sel_2ndnxtalgn}} & icb_algn_nxt_lane_addr)
    | ({`E203_PC_SIZE{icb_addr_sel_cur}} & ifu_req_pc);	
////向biu的读写地址
wire [`E203_ADDR_SIZE-1:0]   ifu2biu_icb_cmd_addr_pre = ifu_icb_cmd_addr[`E203_ADDR_SIZE-1:0];//访问存储器的地址
assign ifu2biu_icb_cmd_addr      = ifu2biu_icb_cmd_addr_pre;	




	
//取指
////pc所指地址的状态,以用来判断如何取指
     //ifu_req_pc 由pc_fetch发送来的pc
	  //ifu_req均为与pc_fetch的通信
	
	//pc在哪个存储器范围内
	  //ifu_req_pc2itcm判断pc是否在itcm之内，否则取BIU取
wire ifu_req_pc2itcm = (ifu_req_pc[`E203_ITCM_BASE_REGION] == itcm_region_indic[`E203_ITCM_BASE_REGION]); 
wire ifu_req_pc2mem = ~(ifu_req_pc2itcm);//若pc超出itcm地址范围则需取biu中取
	  //pc的访问是否跨越对齐边界
wire ifu_req_lane_cross = (ifu_req_pc2itcm & (ifu_req_pc[1] == 1'b1)) | (ifu_req_pc2mem  & (ifu_req_pc[1] == 1'b1)) ;
	  //pc是否从对齐边界开始访问
wire ifu_req_lane_begin = (ifu_req_pc2itcm & (ifu_req_pc[1] == 1'b0)) | (ifu_req_pc2mem  & (ifu_req_pc[1] == 1'b0)) ;
	
	//pc的访问是否在同一个itcm地址内，利用itcm的64位宽和保持输出的特性
wire req_lane_cross_r;//同步ifu_req_lane_cross的时钟，握手成功后更新，实质是流水线开始了此级
sirv_gnrl_dfflr #(1) req_lane_cross_dfflr (ifu_req_hsked, ifu_req_lane_cross, req_lane_cross_r, clk, rst_n);
	  //判断pc是否在同一个访存地址内，仅当pc为连续取指时
wire ifu_req_lane_same = ifu_req_seq & (ifu_req_lane_begin ? req_lane_cross_r : 1'b1);
	  //判断itcm的holdup特性是否可利用
wire ifu_req_lane_holdup = (ifu_req_pc2itcm & ifu2itcm_holdup & (~itcm_nohold));
		//判断pc指向地址在itcm中还是biu中
wire ifu_icb_cmd2itcm;
assign ifu_icb_cmd2itcm = (ifu_icb_cmd_addr[`E203_ITCM_BASE_REGION] == itcm_region_indic[`E203_ITCM_BASE_REGION]);//比较pc的高位基地址是否与itcm的基地址相等，以此判断pc所访问的地址是否在itcm中
wire icb_cmd2itcm_r;//同步后，表明pc所访问地址是否在itcm中
sirv_gnrl_dfflr #(1) icb2itcm_dfflr(ifu_icb_cmd_hsked, ifu_icb_cmd2itcm, icb_cmd2itcm_r, clk, rst_n);
		//判断pc指向地址是否在biu中
assign ifu_icb_cmd2biu = ~(ifu_icb_cmd2itcm);//直接对ifu_icb_cmd2itcm取反即可
wire ifu_icb_cmd2biu ;
wire icb_cmd2biu_r;//同步后的
sirv_gnrl_dfflr #(1) icb2mem_dfflr (ifu_icb_cmd_hsked, ifu_icb_cmd2biu , icb_cmd2biu_r,  clk, rst_n);          
  
     //判断读取方式
  //判断是否与上一pc在同一itcm地址上
wire req_same_cross_holdup_r;
wire req_same_cross_holdup = ifu_req_lane_same & ifu_req_lane_cross & ifu_req_lane_holdup;		
sirv_gnrl_dfflr #(1) req_same_cross_holdup_dfflr (ifu_req_hsked, req_same_cross_holdup, req_same_cross_holdup_r, clk, rst_n);//同步时钟
  //判断是否需要读
wire req_need_2uop_r;//同步后的，表明需要去存储器取指
wire req_need_2uop = (  ifu_req_lane_same  & ifu_req_lane_cross & (~ifu_req_lane_holdup))
                     | ((~ifu_req_lane_same) & ifu_req_lane_cross);//三个均在取指第一步中
sirv_gnrl_dfflr #(1) req_need_2uop_dfflr (ifu_req_hsked, req_need_2uop, req_need_2uop_r, clk, rst_n);
	//判断是否需要不读
wire req_need_0uop_r;//同步后的，表明可利用holdup特性，不用去存储器取指
wire req_need_0uop = ifu_req_lane_same & (~ifu_req_lane_cross) & ifu_req_lane_holdup;//三个均在取指第一步中
sirv_gnrl_dfflr #(1) req_need_0uop_dfflr (ifu_req_hsked, req_need_0uop, req_need_0uop_r, clk, rst_n);
//490-507





////状态转换部分
//////状态码
localparam ICB_STATE_WIDTH  = 2;//状态码位数
				//由于是非对齐取指，所以可能需要读两次
				//因为ITCM为SRAM，输出有寄存器特性，且一次读64位，所以可能不需要额外的读操作
localparam ICB_STATE_IDLE = 2'd0;//无需发送读请求，闲置状态
localparam ICB_STATE_1ST  = 2'd1;//第一次读操作
localparam ICB_STATE_WAIT2ND  = 2'd2;//第一次和第二次之间的等待状态
localparam ICB_STATE_2ND  = 2'd3;//第二次读操作

//////控制参数 		icb_state_r为状态控制器，决定当前应处在哪个状态
wire icb_sta_is_idle    = (icb_state_r == ICB_STATE_IDLE   );
wire icb_sta_is_1st     = (icb_state_r == ICB_STATE_1ST    );
wire icb_sta_is_wait2nd = (icb_state_r == ICB_STATE_WAIT2ND);
wire icb_sta_is_2nd     = (icb_state_r == ICB_STATE_2ND    );
		//每个状态的使能
		wire state_idle_exit_ena     ;
		wire state_1st_exit_ena      ;
		wire state_wait2nd_exit_ena  ;
		wire state_2nd_exit_ena      ;
		//指示该状态是否为下一个状态
		wire [ICB_STATE_WIDTH-1:0] state_idle_nxt   ;
		wire [ICB_STATE_WIDTH-1:0] state_1st_nxt    ;
		wire [ICB_STATE_WIDTH-1:0] state_wait2nd_nxt;
		wire [ICB_STATE_WIDTH-1:0] state_2nd_nxt    ;
		
//////状态转换机，控制状态的转换 
wire [ICB_STATE_WIDTH-1:0] icb_state_nxt;//下一个状态，条件= 该状态的next为1且达到触发的条件
wire [ICB_STATE_WIDTH-1:0] icb_state_r;//当前所处状态
wire icb_state_ena;//使能信号 条件为 只要有一个状态达到触发的条件 则为1

assign icb_state_ena = 
				  state_idle_exit_ena 
				| state_1st_exit_ena 
				| state_wait2nd_exit_ena 
				| state_2nd_exit_ena;
assign icb_state_nxt = 
              ({ICB_STATE_WIDTH{state_idle_exit_ena   }} & state_idle_nxt   )
            | ({ICB_STATE_WIDTH{state_1st_exit_ena    }} & state_1st_nxt    )
            | ({ICB_STATE_WIDTH{state_wait2nd_exit_ena}} & state_wait2nd_nxt)
            | ({ICB_STATE_WIDTH{state_2nd_exit_ena    }} & state_2nd_nxt    )
            ;

sirv_gnrl_dfflr #(ICB_STATE_WIDTH) icb_state_dfflr (icb_state_ena, icb_state_nxt, icb_state_r, clk, rst_n);
		//以下为离开状态的使能，和离开后下一个状态
		//闲置状态-idle
		assign state_idle_exit_ena = icb_sta_is_idle & ifu_req_hsked;//ifu_req_hsked 为fetch和该模块的icb通讯的握手信号，
		assign state_idle_nxt      = ICB_STATE_1ST;//按顺序赋给下一个信号的状态码
		//2次读的第一次-1st
		wire ifu_icb_rsp2leftover;//req_need_2uop_r:表明是否需要读存储器
		assign ifu_icb_rsp2leftover = req_need_2uop_r & icb_sta_is_1st;  //ifu_icb_rsp_hsked：pc_fetch和该模块rsp的握手信号,回传取到的指令，表明???
		assign state_1st_exit_ena  = icb_sta_is_1st & (ifu_icb_rsp2leftover ? ifu_icb_rsp_hsked : i_ifu_rsp_hsked);
		assign state_1st_nxt     = 													//i_ifu_rsp_hsked：？？？？
                (//???需要研究
                  (req_need_2uop_r & (~ifu_icb_cmd_ready))  ?  ICB_STATE_WAIT2ND
                  : (req_need_2uop_r & (ifu_icb_cmd_ready)) ?  ICB_STATE_2ND 
                  :  ifu_req_hsked  					  		   ?  ICB_STATE_1ST 
                  : ICB_STATE_IDLE 
                ) ;
		//2次读的第一次和第二次读中间
		assign state_wait2nd_exit_ena = icb_sta_is_wait2nd &  ifu_icb_cmd_ready;//ifu_icb指啥？？？
		assign state_wait2nd_nxt      = ICB_STATE_2ND;//按顺序赋给下一个信号的状态码
		//2次读的第二次
		assign state_2nd_exit_ena     =  icb_sta_is_2nd &  i_ifu_rsp_hsked;
		assign state_2nd_nxt          = 
                (
                  ifu_req_hsked  ?  ICB_STATE_1ST 
						: ICB_STATE_IDLE
                );



					 




//剩余缓存
wire holdup2leftover_sel = req_same_cross_holdup;//当pc所读地址在itcm的holdup中
wire holdup2leftover_ena = ifu_req_hsked & holdup2leftover_sel;
wire [15:0]  put2leftover_data = ({16{icb_cmd2itcm_r}} & ifu2itcm_icb_rsp_rdata[`E203_ITCM_DATA_WIDTH-1:`E203_ITCM_DATA_WIDTH-16])
											| ({16{icb_cmd2biu_r}} & ifu2biu_icb_rsp_rdata [`E203_SYSMEM_DATA_WIDTH-1:`E203_SYSMEM_DATA_WIDTH-16]);




											
											
//icb通信


////与fetch的通信
//////cmd通道
wire ifu_req_ready_condi = 
                (
                    icb_sta_is_idle 
                  | ((~req_need_2uop_r) & icb_sta_is_1st & i_ifu_rsp_hsked)
                  | (  req_need_2uop_r  & icb_sta_is_2nd & i_ifu_rsp_hsked) 
                );//cmd ready信号的产生条件 //ifu_icb_cmd_ready跟存储器部分有关
assign ifu_req_ready     = ifu_icb_cmd_ready & ifu_req_ready_condi; 	
wire ifu_req_hsked = ifu_req_valid & ifu_req_ready;//cmd握手成功信号		
		//传来		
		//ifu_req_pc
		//ifu_req_seq
		//ifu_req_seq_rv32
		//ifu_req_last_pc
//////rsq通道
		//该通道的信号用一个由fifo组成的缓冲单元先缓存在读
		   //缓存单元
			  wire i_ifu_rsp_valid;
			  wire i_ifu_rsp_ready;
			  wire i_ifu_rsp_err;
			  wire [`E203_INSTR_SIZE-1:0] i_ifu_rsp_instr;
			  wire [`E203_INSTR_SIZE+1-1:0]ifu_rsp_bypbuf_i_data;
			  wire [`E203_INSTR_SIZE+1-1:0]ifu_rsp_bypbuf_o_data;

			  assign ifu_rsp_bypbuf_i_data = {
											  i_ifu_rsp_err,
											  i_ifu_rsp_instr
											  };

			  assign {
											  ifu_rsp_err,
											  ifu_rsp_instr
											  } = ifu_rsp_bypbuf_o_data;

			  sirv_gnrl_bypbuf # (
				 .DP(1),
				 .DW(`E203_INSTR_SIZE+1) 
			  ) u_e203_ifetch_rsp_bypbuf(
					.i_vld   (i_ifu_rsp_valid),
					.i_rdy   (i_ifu_rsp_ready),

					.o_vld   (ifu_rsp_valid),
					.o_rdy   (ifu_rsp_ready),

					.i_dat   (ifu_rsp_bypbuf_i_data),
					.o_dat   (ifu_rsp_bypbuf_o_data),
			  
					.clk     (clk  ),
					.rst_n   (rst_n)
			  );
			  
									//利用holdup特性就可读取到指令 //体现在与存储器的icb通信中，表明以取到指令
assign i_ifu_rsp_valid = holdup_gen_fake_rsp_valid | ifu_icb_rsp2ir_valid;
wire i_ifu_rsp_hsked = i_ifu_rsp_valid & i_ifu_rsp_ready;//握手成功
		//直接从缓存单元回传err和指令
		




		
////与ITCM的通讯--部分存在于icb总线部分
//////cmd通道						//icb总线读写请求		//pc指向的地址在itcm中
assign ifu2itcm_icb_cmd_valid = ifu_icb_cmd_valid & ifu_icb_cmd2itcm;//向itcm发送读写请求
assign ifu2itcm_icb_cmd_addr = ifu_icb_cmd_addr[`E203_ITCM_ADDR_WIDTH-1:0];//向itcm传输地址
//////rsq通道
assign ifu2itcm_icb_rsp_ready = ifu_icb_rsp_ready;
    //传来错误码和数据

////于biu的通讯--部分存在于icb总线部分
//////cmd通道                    //icb总线读写请求     //pc指向的地址在biu中
wire ifu2biu_icb_cmd_valid_pre  = ifu_icb_cmd_valid & ifu_icb_cmd2biu;
assign ifu2biu_icb_cmd_valid     = ifu2biu_icb_cmd_valid_pre;
			//传输地址
//////rsp通道
assign ifu2biu_icb_rsp_ready = ifu_icb_rsp_ready;	 
			//接收错误码和数据
		




		
////读itcm和biu共用的icb总线
//////cmd通道
wire ifu2biu_icb_cmd_ready_pre;
assign ifu2biu_icb_cmd_ready_pre = ifu2biu_icb_cmd_ready;//biu传来的信号，表示读写准许
assign ifu_icb_cmd_ready = 1'b0
									| (ifu_icb_cmd2itcm & ifu2itcm_icb_cmd_ready) 
									| (ifu_icb_cmd2biu  & ifu2biu_icb_cmd_ready_pre ) 
									;//当存在读存储器信号且存储器以准备好读写
wire ifu_req_valid_pos;
assign ifu_req_valid_pos = ifu_req_valid     & ifu_req_ready_condi;//表明与fetch的cmd握手，传来了待取指的pc
assign ifu_icb_cmd_valid =  (ifu_req_valid_pos & (~req_need_0uop))
									 | ( req_need_2uop_r & (//且需要读存储器
                                                     ((icb_sta_is_1st & ifu_icb_rsp_hsked)
												                 |  icb_sta_is_wait2nd)//ifu_icb_rsp_hsked 表明上一个存储器的读取周期结束
																   )
                               ) ;
wire ifu_icb_cmd_valid;
wire ifu_icb_cmd_ready;
wire ifu_icb_cmd_hsked = ifu_icb_cmd_valid & ifu_icb_cmd_ready;//握手成功可利用icb总线向存储器传输

//////rsq通道						 //icb_cmd2itcm/biu_r 表明所访问的地址在itmc/biu中
assign ifu_icb_rsp_valid = 1'b0//ifu2itcm/biu_icb_rsp_valid 为itcm/biu发来的读写反馈信号
									| (icb_cmd2itcm_r & ifu2itcm_icb_rsp_valid)
									| (icb_cmd2biu_r  & ifu2biu_icb_rsp_valid)
									;
assign ifu_icb_rsp_ready  = ifu_icb_rsp2leftover ? 1'b1 : ifu_icb_rsp2ir_ready;//与剩余缓存有关
wire ifu_icb_rsp_valid;
wire ifu_icb_rsp_ready;
wire ifu_icb_rsp_hsked = ifu_icb_rsp_valid & ifu_icb_rsp_ready;

endmodule
