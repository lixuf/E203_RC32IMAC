`include "gen_defines.v"

module if_pc_fetch(
	output[`PC_Size-1:0] inspect_pc,//不知道干啥的
	input  clk,
   input  rst_n,
	
	//复位
	input  [`PC_Size-1:0] pc_rtvec,//pc复位默认地址
	
   //停止等待信号
	input  ifu_halt_req,//其他设备传来的停止请求信号
   output ifu_halt_ack,//向其他设备回传-停止信号确认
	
	
	//icb总线通信
	////与ift2icb
	//////cmd通道
	output ifu_req_valid,//主到从-读写请求信号
	input  ifu_req_ready,//从到主-读写准许信号
	output [`PC_Size-1:0] ifu_req_pc,//主到从-读地址
	output ifu_req_seq,//是否为自增
	output ifu_req_seq_rv32,//是否为32位还是16位
	output [`PC_Size-1:0] ifu_req_last_pc,//当前pc
	//////rsp通道
	input  ifu_rsp_valid,//从到主-读写反馈请求信号
	output ifu_rsp_ready,//主到从-读写反馈请求准许信号
	input  ifu_rsp_err,
	input  [`IR_Size-1:0] ifu_rsp_instr,//从到主-根据pc读到的指令
	
	////与exu 传输IR
	//////cmd通道
	output [`IR_Size-1:0] ifu_o_ir,//主到从-输出IR
	output [`PC_Size-1:0] ifu_o_pc,//主到从-输出前一个pc
	   //各种信号，先保存在寄存器中，在输出
	output ifu_o_pc_vld,
	output [`RFIDX_WIDTH-1:0] ifu_o_rs1_indx,
	output [`RFIDX_WIDTH-1:0] ifu_o_rs2_indx,
	output ifu_o_prdt_taken,               
	output ifu_o_misalgn,                  
	output ifu_o_buserr,                   
	output ifu_o_muldiv_b2b, 
	
	output ifu_o_valid,//主到从-读写请求信号 
	input  ifu_o_ready,//从到主-读写请求准许信号
	
	////pipe_flush,流水线冲刷相关,若请求则将ex传来的reg替换给pc--jalr
	input pipe_flush_req,//是否有流水线冲刷发生
	output pipe_flush_ack,//对流水线冲刷信号的确认
	input   [`PC_Size-1:0] pipe_flush_pc//流水线冲刷，从ex送来的pc，是jalr指令的xn
	

);

assign inspect_pc = pc_r;





//与其他块的连线
////mini_decoder
if_minidec u_if_minidec (
	//由pc_fetch输出至minidec
	.in_IR 		(ifu_ir_nxt		),
	//由minidex输入至pc_fetch
	////跳转相关
	.dec_if32	(minidec_if32	),
	.dec_ifj		(minidec_ifj	),
	.dec_jal		(minidec_jal	),
	.dec_jalr	(minidec_jalr	),
	.dec_bxx    (minidec_bxx   ),
	.dec_jalr_rs1_indx	(minidec_jalr_rs1_indx),
	.dec_bjp_imm			(minidec_bjp_imm		 )

);

////bpu
if_bpu u_if_bpu (
	//由fetch输出至bpu
	.in_PC			(pc_r			),
	
	//由minidec输出至bpu
	.dec_jal					(minidec_jal	),
	.dec_jalr				(minidec_jalr	),
	.dec_bxx					(minidec_bxx	),
	.dec_bjp_imm			(minidec_bjp_imm	),
	.dec_jalr_rs1_indx	(minidec_jalr_rs1_indx),
	
	//由bpu输出至fetch
	.bpu_wait				(bpu_wait		),
	.pred_taken				(prdt_taken		),
	.op1						(pred_op1		),
	.op2						(pred_op2		),
	
	//bpu中jalr所需的寄存器
	.rf2bpu_x1				(rf2bpu_x1		),
	.rf2bpu_rs1				(rf2bpu_rs1		)，
	
	.clk						(clk           ),
	.rst_n					(rst_n			)
	
);







//常数--很迷
assign ifu_rsp_need_replay = 1'b0;
wire ifu_rsp_need_replay;
assign ifetch_replay_req = 1'b0;
wire ifetch_replay_req;
assign pipe_flush_ack = 1'b1;







	
//pc流
////pc顺序自增
wire [2:0] pc_incr_offset = minidec_if32 ? 3'd4 : 3'd2;//判断是32位还是16位,32位偏移量为4，16位偏移量为2


////跳转
wire bjp_req = minidec_ifj & prdt_taken;//是否采取跳转寻址pc

////复位
wire ifu_reset_req = reset_req_r;

////加法器的两个输入，加法器输出最终的跳转结果
wire [`PC_Size-1:0] pc_op1=    bjp_req            ? pred_op1 ://跳转指令
                               ifu_reset_req      ? pc_rtvec ://复位
                                                    pc_r     ;//顺序取指
																	 
wire [`PC_Size-1:0] pc_op2=	 bjp_req 			  ? pred_op2 :
                               ifu_reset_req      ? `PC_Size'b0 :
                                                    pc_incr_offset ;

////计算预计的下一个pc
wire [`PC_Size-1:0] pc_nxt_pred;
wire [`PC_Size-1:0] pc_nxt;
assign pc_nxt_pred = pc_op1 + pc_op2;

////下一个pc
assign pc_nxt = pipe_flush_req ? {pipe_flush_pc[`PC_Size-1:1],1'b0} ://ex产生流水线冲刷，使用ex送来的新pc值
                 dly_pipe_flush_req ? {pc_r[`PC_Size-1:1],1'b0} ://产生控制冒险，需要暂停一个时钟周期
                 {pc_nxt_pre[`PC_Size-1:1],1'b0};//顺序取址

////pc寄存器更新
//////存当前周期的pc
wire [`PC_Size-1:0] ifu_pc_nxt = pc_r;//准备写入的pc
wire [`PC_Size-1:0] ifu_pc_r;//当前reg里的pc
sirv_gnrl_dfflr #(`PC_Size) ifu_pc_dfflr (ir_pc_vld_set, ifu_pc_nxt,  ifu_pc_r, clk, rst_n);					  
														//该信号在ir中
//////真正的pc，存下一周期的pc
wire [`PC_Size-1:0] pc_r;//当前pc
wire pc_ena = ifu_req_hsked | pipe_flush_hsked;
sirv_gnrl_dfflr #(`PC_Size) pc_dfflr (pc_ena, pc_nxt, pc_r, clk, rst_n);

////ir寄存器更新
wire [`IR_Size-1:0] ifu_ir_r;//ir寄存器当前输出
wire minidec_if32;//来自minidec，表明是否为32位指令
wire ir_hi_ena = ir_valid_set & minidec_if32;//使能 //ir_valid_set在与exu传输ir部分
wire ir_lo_ena = ir_valid_set;
sirv_gnrl_dfflr #(`IR_Size/2) ifu_hi_ir_dfflr (ir_hi_ena, ifu_ir_nxt[31:16], ifu_ir_r[31:16], clk, rst_n);
sirv_gnrl_dfflr #(`IR_Size/2) ifu_lo_ir_dfflr (ir_lo_ena, ifu_ir_nxt[15: 0], ifu_ir_r[15: 0], clk, rst_n);
    //分高低字节存储，以实现16/32兼容










	 
//icb总线通讯


////pc_fetch到ifu，取IR
//////cmd通道																	 
wire ifu_new_req = (~bpu_wait) & (~ifu_halt_req) & (~reset_flag_r) & (~ifu_rsp_need_replay);	
      //是否产生新的pc bpu_wait:因jalr指令使用除x0和x1以外的寄存器需要等待一个周期
		//ifu_halt_req 暂停信号
		//reset_flag_r 是否准许来自top的复位信号																 
wire ifu_req_valid_pre = ifu_new_req | ifu_reset_req | pipe_flush_req_real | ifetch_replay_req;																	 
		//已准备好pc可以向从设备发起读写指令
		
wire out_flag_clr;																	 
wire out_flag_r;																	 
wire new_req_condi = (~out_flag_r) | out_flag_clr;//达成向从设备发起读取指令的条件

assign ifu_no_outs   = (~out_flag_r) | ifu_rsp_valid;//rsq
assign ifu_req_valid = ifu_req_valid_pre & new_req_condi;//表明可以向从设备发起读写指令
wire ifu_req_hsked  = (ifu_req_valid & ifu_req_ready) ;//cmd握手成功

      //握手成功发数据
assign ifu_req_pc    = pc_nxt;//下一个pc
assign ifu_req_seq = (~pipe_flush_req_real) & (~ifu_reset_req) & (~ifetch_replay_req) & (~bjp_req);
        //判断是否为顺序自增
assign ifu_req_seq_rv32 = minidec_if32;//标明是16位还是32位
assign ifu_req_last_pc = pc_r;//自增前的pc

//////rsq通道
wire ifu_rsp2ir_ready = (pipe_flush_req_real) ? 1'b1 : (ifu_ir_i_ready & ifu_req_ready & (~bpu_wait));
assign ifu_rsp_ready = ifu_rsp2ir_ready;//准备好接收从设备发来的读写反馈信号，也表明IR已经准备好
wire ifu_rsp_hsked  = (ifu_rsp_valid & ifu_rsp_ready) ;//握手成功

wire [`IR_Size-1:0] ifu_ir_nxt = ifu_rsp_instr;
   //传输用pc取得的指令给ir寄存器

	
////ifetch的IR到exu
//////cmd通道
////////ir_valid信号
wire ir_valid_r;//表明已准备好向exu发送IR
wire ir_valid_clr;//清除信号，当exu收到ir后，即ifu_ir_o_hsked==1，或者pip flush发生
wire ir_valid_nxt;
wire ir_valid_ena;
wire ir_valid_set;
assign ir_valid_set  = ifu_rsp_hsked & (~pipe_flush_req_real) & (~ifu_rsp_need_replay);
								//ifu_rsp_hsked：表明按照pc取完指令
assign ir_valid_clr  = ifu_ir_o_hsked | (pipe_flush_hsked & ir_valid_r);
assign ir_valid_ena  = ir_valid_set  | ir_valid_clr;//写使能，ir_valid_set：表明以取到IR达到发送IR的条件
assign ir_valid_nxt  = ir_valid_set  | (~ir_valid_clr);//下一个信号值
sirv_gnrl_dfflr #(1) ir_valid_dfflr (ir_valid_ena, ir_valid_nxt, ir_valid_r, clk, rst_n);

/////////本次通信需要传输的各种信号
   //ifu_o_buserr 
	wire ifu_err_r;//在用pc取IR时，总线通讯产生的错误码
	wire ifu_err_nxt = ifu_rsp_err;
	sirv_gnrl_dfflr #(1) ifu_err_dfflr(ir_valid_set, ifu_err_nxt, ifu_err_r, clk, rst_n);
	
	//ifu_o_rs1/2_indx
	wire [`RFIDX_WIDTH-1:0] ir_rs1idx_r;
	wire [`RFIDX_WIDTH-1:0] ir_rs2idx_r;//以下部分mini的信号还未设置
	wire ir_rs1idx_ena = (minidec_fpu & ir_valid_set & minidec_fpu_rs1en & (~minidec_fpu_rs1fpu)) | ((~minidec_fpu) & ir_valid_set & minidec_rs1en) | bpu2rf_rs1_ena;
	wire ir_rs2idx_ena = (minidec_fpu & ir_valid_set & minidec_fpu_rs2en & (~minidec_fpu_rs2fpu)) | ((~minidec_fpu) & ir_valid_set & minidec_rs2en);
	wire [`RFIDX_WIDTH-1:0] ir_rs1idx_nxt = minidec_fpu ? minidec_fpu_rs1idx : minidec_rs1idx;
	wire [`RFIDX_WIDTH-1:0] ir_rs2idx_nxt = minidec_fpu ? minidec_fpu_rs2idx : minidec_rs2idx;
	sirv_gnrl_dfflr #(`RFIDX_WIDTH) ir_rs1idx_dfflr (ir_rs1idx_ena, ir_rs1idx_nxt, ir_rs1idx_r, clk, rst_n);
	sirv_gnrl_dfflr #(`RFIDX_WIDTH) ir_rs2idx_dfflr (ir_rs2idx_ena, ir_rs2idx_nxt, ir_rs2idx_r, clk, rst_n);
	
	//ifu_o_prdt_taken
	wire prdt_taken;  
	wire ifu_prdt_taken_r;
	sirv_gnrl_dfflr #(1) ifu_prdt_taken_dfflr (ir_valid_set, prdt_taken, ifu_prdt_taken_r, clk, rst_n);	
	
	//ifu_o_muldiv_b2b
   wire ifu_muldiv_b2b_nxt;
   wire ifu_muldiv_b2b_r;
   sirv_gnrl_dfflr #(1) ir_muldiv_b2b_dfflr (ir_valid_set, ifu_muldiv_b2b_nxt, ifu_muldiv_b2b_r, clk, rst_n);	
   assign ifu_muldiv_b2b_nxt = //部分mini的信号未实现
      (
        | ( minidec_div  & dec2ifu_rem)
        | ( minidec_rem  & dec2ifu_div)
        | ( minidec_divu & dec2ifu_remu)
        | ( minidec_remu & dec2ifu_divu)
      )
      & (ir_rs1idx_r == ir_rs1idx_nxt)
      & (ir_rs2idx_r == ir_rs2idx_nxt)
      & (~(ir_rs1idx_r == ir_rdidx))
      & (~(ir_rs2idx_r == ir_rdidx))
      ;
		
	//ifu_o_pc_vld
	wire ir_pc_vld_set;
   wire ir_pc_vld_clr;
   wire ir_pc_vld_ena;//ifu_ir_i_ready还需研究
   wire ir_pc_vld_r;//pc_newpend_r当有新的pc存入pc寄存器中，该量会置1
	assign ir_pc_vld_set = pc_newpend_r & ifu_ir_i_ready & (~pipe_flush_req_real) & (~ifu_rsp_need_replay);
	assign ir_pc_vld_clr = ir_valid_clr;
	assign ir_pc_vld_ena = ir_pc_vld_set | ir_pc_vld_clr;
   assign ir_pc_vld_nxt = ir_pc_vld_set | (~ir_pc_vld_clr);
	sirv_gnrl_dfflr #(1) ir_pc_vld_dfflr (ir_pc_vld_ena, ir_pc_vld_nxt, ir_pc_vld_r, clk, rst_n);
	
/////////握手-传输
assign ifu_o_valid  = ir_valid_r;
wire ifu_ir_o_hsked = (ifu_o_valid & ifu_o_ready) ;//握手成功
  //传输数据
assign ifu_o_ir  = ifu_ir_r;//传输IR
assign ifu_o_pc  = ifu_pc_r;//传输PC，这个pc是前一个周期的
assign ifu_o_misalgn = 1'b0;//需要定义的一个控制信号，但是手册说从未发送过，故为常数0
assign ifu_o_buserr  = ifu_err_r;//取IR时候的错误码
assign ifu_o_rs1_indx = ir_rs1idx_r;//这里为啥需要提前传一下，还需要研究，没弄明白，手册说是mask需要看fpu指令详细
assign ifu_o_rs2_indx = ir_rs2idx_r;
assign ifu_o_prdt_taken = ifu_prdt_taken_r;//来自bpu，表明是否采用pc的预测值
assign ifu_o_muldiv_b2b = ifu_muldiv_b2b_r;//没弄明白
assign ifu_o_pc_vld = ir_pc_vld_r;//没弄明白


////ex到ifu，pipe_flush
assign pipe_flush_ack = 1'b1;
wire pipe_flush_hsked = pipe_flush_req & pipe_flush_ack;//握手信号，表明ifu准备好接收数据
	//若ifu未准备好，则延迟一个周期？
	wire dly_flush_set;//当pc未准备好更新pc，且pipflush到达则该信号置1
   wire dly_flush_clr;
   wire dly_flush_ena;
   wire dly_flush_nxt;
	wire dly_flush_r;
	assign dly_flush_set = pipe_flush_req & (~ifu_req_hsked);//ifu_req_hsked表示pc是否准备好更新
	assign dly_flush_clr = dly_flush_r & ifu_req_hsked;
   assign dly_flush_ena = dly_flush_set | dly_flush_clr;
   assign dly_flush_nxt = dly_flush_set | (~dly_flush_clr);
	sirv_gnrl_dfflr #(1) dly_flush_dfflr (dly_flush_ena, dly_flush_nxt, dly_flush_r, clk, rst_n);
   wire dly_pipe_flush_req = dly_flush_r;//体现在pc_next中，使得pc保持不变，达到延迟一个周期的效果
   wire pipe_flush_req_real = pipe_flush_req | dly_pipe_flush_req;//？															 
	//传来pipe_flush_pc，在pc_next中


	
//复位信号
wire reset_flag_r;
sirv_gnrl_dffrs #(1) reset_flag_dffrs (1'b0, reset_flag_r, clk, rst_n);//同步rst_n
wire reset_req_r;
wire reset_req_set = (~reset_req_r) & reset_flag_r;
wire reset_req_clr = reset_req_r & ifu_req_hsked;
wire reset_req_ena = reset_req_set | reset_req_clr;
wire reset_req_nxt = reset_req_set | (~reset_req_clr);
sirv_gnrl_dfflr #(1) reset_req_dfflr (reset_req_ena, reset_req_nxt, reset_req_r, clk, rst_n);
wire ifu_reset_req = reset_req_r;	
	
	
	
	
//停止信号，此寄存器方法也为了减少信号翻转，减少功耗
wire halt_ack_set;//寄存器同步必须的信号
wire halt_ack_clr;
wire halt_ack_ena;
wire halt_ack_r;//当前信号
wire halt_ack_nxt;//下个周期的信号

wire ifu_no_outs;//表明没有新的对ift2icb的读写信号		  //ifu_rsp_valid 为1表示还未产生新的对ift2icb的读写命令
assign ifu_no_outs   = (~out_flag_r) | ifu_rsp_valid;//out_flag_r 当该设备与ift2icb的cmd握手成功后置1
assign halt_ack_set = ifu_halt_req & (~halt_ack_r) & ifu_no_outs;
assign halt_ack_clr = halt_ack_r & (~ifu_halt_req);
assign halt_ack_ena = halt_ack_set | halt_ack_clr;
assign halt_ack_nxt = halt_ack_set | (~halt_ack_clr);
sirv_gnrl_dfflr #(1) halt_ack_dfflr (halt_ack_ena, halt_ack_nxt, halt_ack_r, clk, rst_n);

assign ifu_halt_ack = halt_ack_r;//回传停止确认信号


endmodule
