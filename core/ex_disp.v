//该模块为派遣单元，主要将所需信息送至alu和oitf
//也为WFI，Fence和FenceI指令的重要执行单元，完成指令派遣阻塞操作
//本cpu无fpu模块，因此oitf的实现会比较简单
//功能：1. 将信息送至ALU或OITF
//		 2. 判断指令是否为WFI，Fence和FenceI，是则阻塞
//		 3. 处理oitf表项的资源冲突，若有长指令发生但无oitf表现则阻塞
//     4. 处理oitf表项的数据冲突，有冲突则阻塞
//实现：1. 将解码器送来的信号与ALU和OITF的信号线对应连接
//		 2. 连接好握手信号，握手信号均来自解码器，由alu和oitf自己判断是否握手成功，派遣单元仅为桥梁
//		 3. 处理好其他特殊情况，如WFI,Fence,FenceI,冲突和访问crs
`include "gen_defines.v"

module ex_disp(
//连接至ALU的接口
  //icb通讯握手信号
  output disp_o_alu_valid,//发送至alu，请求读写信号
  input  disp_o_alu_ready,//来自alu，请求读写准许信号

  input  disp_o_alu_longpipe,//???
  //操作数
  output [`E203_XLEN-1:0] disp_o_alu_rs1,
  output [`E203_XLEN-1:0] disp_o_alu_rs2,
  //指令的其他信息
  output disp_o_alu_rdwen,//表示该指令是否写回结果寄存器
  output [`E203_RFIDX_WIDTH-1:0] disp_o_alu_rdidx,//表明该指令写回的结果寄存器索引
  output [`E203_DECINFO_WIDTH-1:0]  disp_o_alu_info,//指令的信息  
  output [`E203_XLEN-1:0] disp_o_alu_imm,//该指令的立即数字段
  output [`E203_PC_SIZE-1:0] disp_o_alu_pc,//该指令的pc
  output [`E203_ITAG_WIDTH-1:0] disp_o_alu_itag,//???
  output disp_o_alu_misalgn,//该指令取指时发生了非对齐错误
  output disp_o_alu_buserr ,//该指令取值时发生了存储器访问错误
  output disp_o_alu_ilegl  ,//该指令是一条非法指令
  
//连接解码器的接口
  //icb通讯握手信号
  input  disp_i_valid,//来自解码器的读写请求信号
  output disp_i_ready,//输出至解码器的读写请求准许信号

  //各种信息，等待派遣
  input  disp_i_rs1en,//oitf，操作数1使能
  input  disp_i_rs2en,//oitf，操作数2使能
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rs1idx,//仅用于oitf，生成操作数
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rs2idx,//仅用于oitf，生成操作数
  //用于生成操作数1
	  input  disp_i_rs1x0,
	  input  [`E203_XLEN-1:0] disp_i_rs1,
  //用于生成操作数2  
	  input  disp_i_rs2x0,
	  input  [`E203_XLEN-1:0] disp_i_rs2,
  input  disp_i_rdwen,//表示该指令是否写回结果寄存器
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rdidx,//表明该指令写回的结果寄存器索引
  input  [`E203_DECINFO_WIDTH-1:0]  disp_i_info,//信息总线  
  input  [`E203_XLEN-1:0] disp_i_imm,//该指令的立即数字段
  input  [`E203_PC_SIZE-1:0] disp_i_pc,//该指令的pc
  input  disp_i_misalgn,//该指令取指时发生了非对齐错误
  input  disp_i_buserr ,//该指令取值时发生了存储器访问错误
  input  disp_i_ilegl  ,//该指令是一条非法指令

//连接oitf的接口
  input  oitfrd_match_disprs1,//派遣指令操作数1和oitf任一表现中的结果寄存器相同
  input  oitfrd_match_disprs2,//派遣指令操作数2和oitf任一表现中的结果寄存器相同
  input  oitfrd_match_disprs3,//派遣指令操作数3和oitf任一表现中的结果寄存器相同
  input  oitfrd_match_disprd,//派遣指令结果操作数和oitf任一表现中的结果寄存器相同
  input  [`E203_ITAG_WIDTH-1:0] disp_oitf_ptr ,//与alu有关？？？

  output disp_oitf_ena,//表明是否分配oitf
  input  disp_oitf_ready,//表明oitf表项有空位

  output disp_oitf_rs1en ,//操作数1的使能
  output disp_oitf_rs2en ,//操作数2的使能
  output disp_oitf_rs3en ,//操作数3的使能，由于不支持fpu故操作数3使能永远为0
  output disp_oitf_rdwen ,//表示该指令是否写回结果寄存器

  output [`E203_RFIDX_WIDTH-1:0] disp_oitf_rs1idx,//操作数1的索引
  output [`E203_RFIDX_WIDTH-1:0] disp_oitf_rs2idx,//操作数2的索引
  output [`E203_RFIDX_WIDTH-1:0] disp_oitf_rs3idx,//操作数3的索引
  output [`E203_RFIDX_WIDTH-1:0] disp_oitf_rdidx ,//表明该指令写回的结果寄存器索引

  output [`E203_PC_SIZE-1:0] disp_oitf_pc ,//该指令的pc

  
//WFI为等待中断指令，该cpu指定为睡眠等待指令，需要停止工作并睡眠  
input  wfi_halt_exu_req,//WFI请求信号
output wfi_halt_exu_ack,//wfi准许信号

input  oitf_empty,//表明oitf为空
input  amo_wait, //原子操作

  
input  clk,
input  rst_n
  
);
//派遣条件信号--当不符合条件时，派遣点会被阻塞
wire disp_condition = 
                 (disp_csr ? oitf_empty : 1'b1)
               & (disp_fence_fencei ? oitf_empty : 1'b1)
               & (~wfi_halt_exu_req)   
               & (~dep)   
               & (disp_alu_longp_prdt ? disp_oitf_ready : 1'b1);
		//disp_csr 表明是否访问crs，若访问需等待oitf为空(oitf_empty)，oitf为空代表长指令执行完毕
		//disp_fence_fencei 表明是否有Fence和FenceI指令发生，若发生需要等待oitf为空即长指令执行完毕，因为Fence
		//                  和FenceI分别为屏障和同步指令，目的是将前面以及执行的指令执行完，即写入存储器在使后面
		//                  的指令执行，后者还会冲刷掉流水线
		//wfi_halt_exu_req 表明是否由WFI指令发生，WFI为等待中断指令，该cpu指定为睡眠等待指令，需要停止工作并睡眠
		//dep 表示是否发生数据冲突，发生则阻塞
		//disp_alu_longp_prdt 表明是否有长指令发生
		//     disp_oitf_ready 表明oitf是否有空，因为派遣长指令时需要分配oitf表项，无资源时必须等待

		
		
		

//来自解码器，输入被派遣至alu和oitf(长指令)
    //握手
assign disp_i_ready     = disp_condition & disp_i_ready_pos;//输出至解码器，表明准许读写，来自alu
																			   //读写请求信号直接接入alu
	 //传输的信号
//全部在向oitf和alu的输出中，直接派遣过去



		
//至ALU，该模块相当于桥梁，握手信号均来自译码器
    //握手
wire   disp_i_ready_pos = disp_o_alu_ready;//从alu输入的读写准许信号，会与其他信号逻辑运算后直接送回解码器

wire disp_i_valid_pos; 
assign disp_i_valid_pos = disp_condition & disp_i_valid;//解码器送来的读写请求信号
assign disp_o_alu_valid = disp_i_valid_pos;//向alu输出的读写请求信号，由解码器送来
	//以下均来自解码器
	 //其他信息，在module中有说明
assign disp_o_alu_rdwen = disp_i_rdwen;
assign disp_o_alu_rdidx = disp_i_rdidx;
assign disp_o_alu_info  = disp_i_info; 
assign disp_o_alu_imm  = disp_i_imm;
assign disp_o_alu_pc   = disp_i_pc;
assign disp_o_alu_itag = disp_oitf_ptr;
assign disp_o_alu_misalgn= disp_i_misalgn;
assign disp_o_alu_buserr = disp_i_buserr ;
assign disp_o_alu_ilegl  = disp_i_ilegl  ;
	 //操作数
wire [`E203_XLEN-1:0] disp_i_rs1_msked = disp_i_rs1 & {`E203_XLEN{~disp_i_rs1x0}};
wire [`E203_XLEN-1:0] disp_i_rs2_msked = disp_i_rs2 & {`E203_XLEN{~disp_i_rs2x0}};
assign disp_o_alu_rs1   = disp_i_rs1_msked;
assign disp_o_alu_rs2   = disp_i_rs2_msked;




//连接oitf
assign disp_oitf_ena = disp_o_alu_valid & disp_o_alu_ready & disp_alu_longp_real;//表明是否分配oitf
assign disp_oitf_rs1en  =disp_i_rs1en;
assign disp_oitf_rs2en  =disp_i_rs2en;
assign disp_oitf_rs3en  =1'b0;
assign disp_oitf_rdwen  =disp_i_rdwen;
assign disp_oitf_rs1idx =disp_i_rs1idx;
assign disp_oitf_rs2idx =disp_i_rs2idx;
assign disp_oitf_rs3idx =`E203_RFIDX_WIDTH'b0;
assign disp_oitf_rdidx  =disp_i_rdidx;
assign disp_oitf_pc  = disp_i_pc;



//其他控制信号
////表明是否为WFI指令
assign wfi_halt_exu_ack = oitf_empty & (~amo_wait);//当oitf为空(长指令执行完毕)和无原子操作时为1
////表明是否访问crs
wire [`E203_DECINFO_GRP_WIDTH-1:0] disp_i_info_grp  = disp_i_info [`E203_DECINFO_GRP];
wire disp_csr = (disp_i_info_grp == `E203_DECINFO_GRP_CSR);
////表明是否为Fence和FenceI指令
wire disp_fence_fencei   = (disp_i_info_grp == `E203_DECINFO_GRP_BJP) & 
                           ( disp_i_info [`E203_DECINFO_BJP_FENCE] | 
									disp_i_info [`E203_DECINFO_BJP_FENCEI]);
////表明是否有长指令发生
wire disp_alu_longp_prdt = (disp_i_info_grp == `E203_DECINFO_GRP_AGU);
////来自alu，进一步分发为长指令？？？
wire disp_alu_longp_real = disp_o_alu_longpipe;
////数据冒险
wire dep = raw_dep | waw_dep;
  //RAW
  wire raw_dep =  ((oitfrd_match_disprs1) |
                   (oitfrd_match_disprs2) |
                   (oitfrd_match_disprs3)); 
  //WAW
  wire waw_dep = (oitfrd_match_disprd); 
endmodule
