`include "gen_defines.v"

module if_bpu(//还未处理冲突//使用静态预测，每次均向后跳转
input [`PC_Size-1:0] in_PC,
input clk,
input rst_n,
input  dec_i_valid,//表示解码器的输入有效

//来自minidec
input dec_jal,
input dec_jalr,
input dec_bxx,
input [`XLEN-1:0] dec_bjp_imm,
input [`RFIDX_WIDTH-1:0] dec_jalr_rs1_indx,

//jalr所需的寄存器
output bpu2rf_rs1_ena,//rs1使能表述要读该信号指示的寄存器
input [`XLEN-1:0] rf2bpu_x1,//从regfile直接引过来的寄存器，方便jalr调用
input [`XLEN-1:0] rf2bpu_rs1,//需要延迟一个周期，用来读该寄存器


//输出到加法器
output [`PC_Size-1:0] op1,
output [`PC_Size-1:0] op2,

//输出控制信号
output bpu_wait,//冲突需等待一个时钟周期，可能发生在jalr
output pred_taken//预测为是否需要跳转

//？？？
input  oitf_empty,
input  ir_empty,
input  ir_rs1en,
input  jalr_rs1idx_cam_irrdidx,

//?? 去fetch的连接信号中看
input  ir_valid_clr,
  
);


//判断是否跳转
assign pred_taken=(	dec_jal	|	dec_jalr	|	(	dec_bxx	&	dec_bjp_imm[`XLEN-1]	));
							//jal和jalr直接跳转  bxx需要判断imm符号位

//判断jalr所用的寄存器
wire dec_jalr_rs1x0 =( dec_jalr_rs1_indx == `RFIDX_WIDTH'b0 );
wire dec_jalr_rs1x1 =( dec_jalr_rs1_indx == `RFIDX_WIDTH'b1 );
wire dec_jalr_rs1xn =( ~dec_jalr_rs1x0 ) & ( ~dec_jalr_rs1x1 );


//判断x1以及xn是否存在数据冒险或者控制冒险
wire jalr_rs1x1_dep = dec_i_valid & dec_jalr & dec_jalr_rs1x1 & ((~oitf_empty) | (jalr_rs1idx_cam_irrdidx));
wire jalr_rs1xn_dep = dec_i_valid & dec_jalr & dec_jalr_rs1xn & ((~oitf_empty) | (~ir_empty));
		//特殊情况？ 可视为无依赖
wire jalr_rs1xn_dep_ir_clr = (jalr_rs1xn_dep & oitf_empty & (~ir_empty)) & (ir_valid_clr | (~ir_rs1en));  
 
//是否要读rs1指示的寄存器，同步
wire rs1xn_rdrf_r;
wire rs1xn_rdrf_set = (~rs1xn_rdrf_r) & dec_i_valid & dec_jalr & dec_jalr_rs1xn & ((~jalr_rs1xn_dep) | jalr_rs1xn_dep_ir_clr);
wire rs1xn_rdrf_clr = rs1xn_rdrf_r;
wire rs1xn_rdrf_ena = rs1xn_rdrf_set |   rs1xn_rdrf_clr;
wire rs1xn_rdrf_nxt = rs1xn_rdrf_set | (~rs1xn_rdrf_clr);

sirv_gnrl_dfflr #(1) rs1xn_rdrf_dfflrs(rs1xn_rdrf_ena, rs1xn_rdrf_nxt, rs1xn_rdrf_r, clk, rst_n);
  
assign bpu2rf_rs1_ena = rs1xn_rdrf_set;


//jalr的冒险无法解决则等待
assign bpu_wait = jalr_rs1x1_dep | jalr_rs1xn_dep | rs1xn_rdrf_set;


//加法器部分
////op1 需要if-else判断是哪个指令
assign op1=	(dec_bxx|dec_jal) ? in_PC[`PC_Szie-1:0]//bxx和jal只需要pc即可
			:  (dec_jalr&dec_jalr_rs1x0) ? `PC_Size'b0//jalr的需要寄存器的值作为基址，0号寄存器
			:	(dec_jalr&dec_jalr_rs1x1) ? rf2bpu_x1[`PC_Size-1:0]//1号寄存器
			:	rf2bpu_rs1[`PC_Size-1:0];//其他编号的寄存器

////op2固定输入，无需判断
assign op2= dec_bjp_imm[`PC_Size-1:0];

endmodule
