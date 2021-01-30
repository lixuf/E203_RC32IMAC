`include "gen_defines.v"
//该模块规则性较强，理解了一两个寄存器即可理解整个模块的书写规则和方式
//功能：类似于mips架构的cp0协处理器，主要用于保存cpu的各种状态，控制运行模式和异常中断等的控制
//实现：1.理解寄存器的一般使用方法-以常用的dfflr为例，其包括写使能端，输入端和输出端，
//										  一般写使能端会由输入的寄存器下标和输入的写信号共同控制，
//										  一般输入端为下一时钟沿到来时要更新的值，由外界信号决定，
//										  一般输出端会连接到输出的多路选择器，一部分也会直接输出。
//		2. 阅读作者手册的附录B，该附录包含了所需寄存器的具体介绍，需从中抽象出每个寄存器的更新时机，规则和方式
//			以及所更新的数据，分别对应使能端和输入端的逻辑设计。另外需要注意，有的寄存器仅可读，则可不用寄存器以减少面积和功耗。
//			该芯片的寄存器设计严格遵循RISC-V的架构手册，由于面向嵌入式，因此仅有机器模式，从而无需实现其他模式需
//  		要的寄存器。并且在此基础上作者还自定义了4个寄存器，其中0xBFF在附录B中有详细描述，但0xBFE,0xBFD和0xBF0
//			无描述，另外0x7B0,0x7B1,0x7B2和0x7A0也无描述。
//			
module ex_csr(
  //内核模式，这里仅仅用m(机器)模式，其他全置为0
  output u_mode,
  output s_mode,
  output h_mode,
  output m_mode,
  
 

  	
  //csr读取相关
  input csr_ena,//csr使能，用于实现门控信号，仅在需要时修改寄存器，减少功耗
  input csr_wr_en,//写使能
  input csr_rd_en,//读使能
  input [12-1:0] csr_idx,//需要读取的寄存器编号
  output [`E203_XLEN-1:0] read_csr_dat,//读到的数据-输出
  input  [`E203_XLEN-1:0] wbck_csr_dat,//待写入的数据
  output [`E203_XLEN-1:0] wr_csr_nxt,//将待写入的数据输出
  output csr_access_ilgl,//存取异常信号，但这里规定不会产生异常，读地址法非则返回0，写地址非法的不做任何改动
 
 
  //0xB00 0xB80
  input  clk_aon,//这两个寄存器需要用特殊的时钟--一直保持高电平
  
  //0x300
  output eai_xs_off,//xs 一直为0
  output status_mie_r,//mie 全局中断使能
  input cmt_status_ena,//mpie mie 表示发生异常使得mpie更新为当前mie
  input cmt_mret_ena,//mpie mie  表示mret指令发生  mret-推出异常指令
  
  //0xBFF
  output tm_stop,//表示停止时间计数器
  
  //0xBFE
  output core_cgstop,//停止cpu内核的门控时钟
  output tcm_cgstop,//停止tcm的门控时钟
  
  //0xBFD
  output itcm_nohold,//表示itcm是否有holdup特性
  
  //0xBF0
  output mdv_nob2b,//表示乘除是否有back2back特性
  
  //0xF14
  input  [`E203_HART_ID_W-1:0] core_mhartid,//hart寄存器编号
  
  //0x344 反应中断等待状态
  input  ext_irq_r,//外部中断
  input  sft_irq_r,//软件中断
  input  tmr_irq_r,//计时器中断
 
  //0x304 类似中断屏蔽寄存器，表示对应中断类型使能
  output mtie_r,//计时器中断
  output msie_r,//软件中断
  output meie_r,//外部中断
  
  //0x7B0//未标注
  input [`E203_XLEN-1:0] dcsr_r，
  output wr_dcsr_ena,//debug控制和状态
  
  //0x7B1
  input [`E203_PC_SIZE-1:0] dpc_r，
  output wr_dpc_ena,//debug pc
  output[`E203_PC_SIZE-1:0]  csr_dpc_r,//当前debug的pc用于debug的暂停周期保持pc
  
  //0x7B2
  input [`E203_XLEN-1:0] dscratch_r,
  output wr_dscratch_ena,//debug 开始标志
  
  //0x343
  input [`E203_ADDR_SIZE-1:0] cmt_badaddr,//保存异常时的环境信息
  input cmt_badaddr_ena,
  
  //0x341
  input [`E203_PC_SIZE-1:0] cmt_epc,//保存进入异常之前的pc值
  input cmt_epc_ena,
  output[`E203_PC_SIZE-1:0]  csr_epc_r,//输出当前存储的异常时保存的pc用于退出异常
  
  //0x342
  input [`E203_XLEN-1:0] cmt_cause,//保存进入异常的出错原因
  input cmt_cause_ena,					//高1位为中断域，低31位为异常编号
  
  //0xB02 0xB82
  input cmt_instret_ena,//退休指令计数器的开关
							//退休即执行过的指令，该计数器用于记录执行过多少指令

  //0x305
  output[`E203_XLEN-1:0] csr_mtvec_r,//异常的入口地址	 
  
  //其他
  input  dbg_mode,//表示进入debug模式
  input  dbg_stopcycle,//表示进入debug的停止周期
  input  clk,
  input  rst_n
 
 );



//表示内核所处模式，由于面向嵌入式，为了简化，因此仅仅支持m_mode(机器模式)
wire [1:0] priv_mode = u_mode ? 2'b00 : 
                       s_mode ? 2'b01 :
                       h_mode ? 2'b10 : 
                       m_mode ? 2'b11 : 
                                2'b11 ;
assign u_mode = 1'b0;
assign s_mode = 1'b0;
assign h_mode = 1'b0;
assign m_mode = 1'b1;




//访存控制信号
assign csr_access_ilgl = 1'b0;//对于csr访问不会产生异常
wire wbck_csr_wen = csr_wr_en & csr_ena & (~csr_access_ilgl);//写
wire read_csr_ena = csr_rd_en & csr_ena & (~csr_access_ilgl);//读，该信号如果不需要扩展csr则不需要
       //门控信号，仅在需要读写时触发，以减少功耗
assign wr_csr_nxt = wbck_csr_dat;//将写入数据输出



//csr寄存器
////0x300 机器模式状态寄存器
     //控制信号
wire sel_mstatus = (csr_idx == 12'h300);//该寄存器的选择信号
wire rd_mstatus = sel_mstatus & csr_rd_en;//表示读该寄存器
wire wr_mstatus = sel_mstatus & csr_wr_en;//表示写该寄存器
wire [`E203_XLEN-1:0] csr_mstatus = status_r;//输出端口
	  //寄存器主体部分
wire [`E203_XLEN-1:0] status_r;
assign status_r[31]    = status_sd_r;//SD
assign status_r[30:23] = 8'b0;//保留 
assign status_r[22:17] = 6'b0;// TSR--MPRV
assign status_r[16:15] = status_xs_r;// XS
assign status_r[14:13] = status_fs_r;// FS
assign status_r[12:11] = 2'b11;// MPP 
assign status_r[10:9]  = 2'b0;//保留  
assign status_r[8]     = 1'b0;// SPP
assign status_r[7]     = status_mpie_r;// MPIE
assign status_r[6]     = 1'b0;//保留  
assign status_r[5]     = 1'b0;// SPIE 
assign status_r[4]     = 1'b0;// UPIE 
assign status_r[3]     = status_mie_r;// MIE
assign status_r[2]     = 1'b0;//保留  
assign status_r[1]     = 1'b0;// SIE 
assign status_r[0]     = 1'b0;// UIE 
	  //寄存器中的各个信号
	    //MPIE
		 wire status_mpie_r;
		 wire status_mpie_ena  = 
        (wr_mstatus & wbck_csr_wen) |
        cmt_mret_ena |
        cmt_status_ena;
		 wire status_mpie_nxt    = 
		  cmt_status_ena ? status_mie_r :
		  cmt_mret_ena  ? 1'b1 : 
		  (wr_mstatus & wbck_csr_wen) ? wbck_csr_dat[7] : 
		  status_mpie_r ; 
       sirv_gnrl_dfflr #(1) status_mpie_dfflr (status_mpie_ena, status_mpie_nxt, status_mpie_r, clk, rst_n);
		 //MIE
		 wire status_mie_ena  = status_mpie_ena; 
		 wire status_mie_nxt  = cmt_status_ena ? 1'b0 :
										cmt_mret_ena ? status_mpie_r :
										(wr_mstatus & wbck_csr_wen) ? wbck_csr_dat[3] : 
										 status_mie_r;											//status_mie_r直接输出
		 sirv_gnrl_dfflr #(1) status_mie_dfflr (status_mie_ena, status_mie_nxt, status_mie_r, clk, rst_n);
		 //SD 仅可读
		 wire status_sd_r = (status_fs_r == 2'b11) | (status_xs_r == 2'b11);
		 //XS 仅可读 不存在EAI协处理器 因此XS为00
		 wire [1:0] status_xs_r;
		 assign status_xs_r = 2'b0;
		 assign eai_xs_off = 1'b0; 
		 //FS 仅可读 不存在浮点运算单元 因此FS为00
		 wire [1:0] status_fs_r;
		 assign status_fs_r = 2'b0; 

		 
////0x304 机器模式中断使能寄存器
wire sel_mie = (csr_idx == 12'h304);//该寄存器的选择信号
wire rd_mie = sel_mie & csr_rd_en;//写使能
wire wr_mie = sel_mie & csr_wr_en;//读使能
wire mie_ena = wr_mie & wbck_csr_wen;//门控信号，写		 
wire [`E203_XLEN-1:0] mie_r;//当前寄存器的输出
wire [`E203_XLEN-1:0] mie_nxt;//下个时钟待写入寄存器的信号
sirv_gnrl_dfflr #(`E203_XLEN) mie_dfflr (mie_ena, mie_nxt, mie_r, clk, rst_n);//0x304寄存器
	//给mie_nxt赋值
	assign mie_nxt[31:12] = 20'b0;
	assign mie_nxt[11] = wbck_csr_dat[11];//meie
	assign mie_nxt[10:8] = 3'b0;
	assign mie_nxt[ 7] = wbck_csr_dat[ 7];//mtie
	assign mie_nxt[6:4] = 3'b0;
	assign mie_nxt[ 3] = wbck_csr_dat[ 3];//msie
	assign mie_nxt[2:0] = 3'b0;		 
	//输出部分
	wire [`E203_XLEN-1:0] csr_mie = mie_r;
	assign meie_r = csr_mie[11];
	assign mtie_r = csr_mie[ 7];
	assign msie_r = csr_mie[ 3];
	
	
	
////0x344 机器模式中断等待寄存器 me/t/sip	
wire sel_mip = (csr_idx == 12'h344);//该寄存器的选择信号
wire rd_mip = sel_mip & csr_rd_en;//读使能
wire meip_r;//mxip仅可读
wire msip_r;
wire mtip_r;
sirv_gnrl_dffr #(1) meip_dffr (ext_irq_r, meip_r, clk, rst_n);//0x344寄存器
sirv_gnrl_dffr #(1) msip_dffr (sft_irq_r, msip_r, clk, rst_n);
sirv_gnrl_dffr #(1) mtip_dffr (tmr_irq_r, mtip_r, clk, rst_n);		 
	//输出部分
	wire [`E203_XLEN-1:0] ip_r;
	assign ip_r[31:12] = 20'b0;
	assign ip_r[11] = meip_r;
	assign ip_r[10:8] = 3'b0;
	assign ip_r[ 7] = mtip_r;
	assign ip_r[6:4] = 3'b0;
	assign ip_r[ 3] = msip_r;
	assign ip_r[2:0] = 3'b0;
	wire [`E203_XLEN-1:0] csr_mip = ip_r;
	
	
	
////0x305 机器模式异常入口基地址寄存器
wire sel_mtvec = (csr_idx == 12'h305);//寄存器选择信号
wire rd_mtvec = csr_rd_en & sel_mtvec;//读使能
wire wr_mtvec = sel_mtvec & csr_wr_en;//写使能
wire mtvec_ena = (wr_mtvec & wbck_csr_wen);//门控信号，写
wire [`E203_XLEN-1:0] mtvec_r;//寄存器当前输出
wire [`E203_XLEN-1:0] mtvec_nxt = wbck_csr_dat;//下一个时钟待写入的
sirv_gnrl_dfflr #(`E203_XLEN) mtvec_dfflr (mtvec_ena, mtvec_nxt, mtvec_r, clk, rst_n);//0x305寄存器
	//输出部分
	wire [`E203_XLEN-1:0] csr_mtvec = mtvec_r;
	assign csr_mtvec_r = csr_mtvec;
	
	
	
////0x340 机器模式擦写寄存器
wire sel_mscratch = (csr_idx == 12'h340);//寄存器选择信号
wire rd_mscratch = sel_mscratch & csr_rd_en;//读使能
wire wr_mscratch = sel_mscratch & csr_wr_en;//写使能
wire mscratch_ena = (wr_mscratch & wbck_csr_wen);//门控信号，写
wire [`E203_XLEN-1:0] mscratch_r;//当前输出
wire [`E203_XLEN-1:0] mscratch_nxt = wbck_csr_dat;//待写入
sirv_gnrl_dfflr #(`E203_XLEN) mscratch_dfflr (mscratch_ena, mscratch_nxt, mscratch_r, clk, rst_n);//0x340寄存器
	//输出部分
	wire [`E203_XLEN-1:0] csr_mscratch = mscratch_r;
	

	
	
	
////B00/B80/B02/B82所需状态信号
wire cy_stop;//周期计数器停止信号
wire ir_stop;//退休指令停止信号
wire stop_cycle_in_dbg = dbg_stopcycle & dbg_mode;//表明debug中的停止周期
								//debug停止周期指示信号//debug模式

assign cy_stop = counterstop_r[0];//来自0xBFF寄存器
assign ir_stop = counterstop_r[2];
////0xB00 周期计数器的低32位
wire sel_mcycle    = (csr_idx == 12'hB00);//寄存器选择信号
wire rd_mcycle     = csr_rd_en & sel_mcycle   ;
wire wr_mcycle     = csr_wr_en & sel_mcycle   ;
wire mcycle_wr_ena    = (wr_mcycle    & wbck_csr_wen);
wire [`E203_XLEN-1:0] mcycle_r   ;
wire mcycle_ena    = mcycle_wr_ena    | 
                     ((~cy_stop) & (~stop_cycle_in_dbg) & (1'b1));
wire [`E203_XLEN-1:0] mcycle_nxt    = mcycle_wr_ena    ? wbck_csr_dat : (mcycle_r    + 1'b1);	
sirv_gnrl_dfflr #(`E203_XLEN) mcycle_dfflr (mcycle_ena, mcycle_nxt, mcycle_r   , clk_aon, rst_n);
wire [`E203_XLEN-1:0] csr_mcycle    = mcycle_r;
	
////0xB80 周期计数器的高32位
wire sel_mcycleh   = (csr_idx == 12'hB80);//寄存器选择信号
wire rd_mcycleh    = csr_rd_en & sel_mcycleh  ;
wire wr_mcycleh    = csr_wr_en & sel_mcycleh  ;
wire mcycleh_wr_ena   = (wr_mcycleh   & wbck_csr_wen);
wire [`E203_XLEN-1:0] mcycleh_r  ;
wire mcycleh_ena   = mcycleh_wr_ena   | 
                     ((~cy_stop) & (~stop_cycle_in_dbg) & ((mcycle_r == (~(`E203_XLEN'b0)))));						
wire [`E203_XLEN-1:0] mcycleh_nxt   = mcycleh_wr_ena   ? wbck_csr_dat : (mcycleh_r   + 1'b1);
sirv_gnrl_dfflr #(`E203_XLEN) mcycleh_dfflr (mcycleh_ena, mcycleh_nxt, mcycleh_r  , clk_aon, rst_n);
wire [`E203_XLEN-1:0] csr_mcycleh   = mcycleh_r;

////0xB02 退休指令计数器的低32位
wire sel_minstret  = (csr_idx == 12'hB02);//寄存器选择信号
wire rd_minstret   = csr_rd_en & sel_minstret ;
wire wr_minstret   = csr_wr_en & sel_minstret ;
wire minstret_wr_ena  = (wr_minstret  & wbck_csr_wen);
wire [`E203_XLEN-1:0] minstret_r ;
wire minstret_ena  = minstret_wr_ena  |
                     ((~ir_stop) & (~stop_cycle_in_dbg) & (cmt_instret_ena));
wire [`E203_XLEN-1:0] minstret_nxt  = minstret_wr_ena  ? wbck_csr_dat : (minstret_r  + 1'b1);
sirv_gnrl_dfflr #(`E203_XLEN) minstret_dfflr (minstret_ena, minstret_nxt, minstret_r , clk, rst_n);
wire [`E203_XLEN-1:0] csr_minstret  = minstret_r;

////0xB82 退休指令计数器的高32位
wire sel_minstreth = (csr_idx == 12'hB82);//寄存器选择信号
wire rd_minstreth  = csr_rd_en & sel_minstreth;
wire wr_minstreth  = csr_wr_en & sel_minstreth;
wire minstreth_wr_ena = (wr_minstreth & wbck_csr_wen);
wire [`E203_XLEN-1:0] minstreth_r;
wire minstreth_ena = minstreth_wr_ena |
                     ((~ir_stop) & (~stop_cycle_in_dbg) & ((cmt_instret_ena & (minstret_r == (~(`E203_XLEN'b0))))));
wire [`E203_XLEN-1:0] minstreth_nxt = minstreth_wr_ena ? wbck_csr_dat : (minstreth_r + 1'b1);
sirv_gnrl_dfflr #(`E203_XLEN) minstreth_dfflr (minstreth_ena, minstreth_nxt, minstreth_r, clk, rst_n);							
wire [`E203_XLEN-1:0] csr_minstreth = minstreth_r;	
					
////0xBFF 	自定义寄存器用于停止mtime, mcycle, mcycleh,minstret,minstreth对应的计数器
wire sel_counterstop = (csr_idx == 12'hBFF);//寄存器选择信号
wire rd_counterstop  = csr_rd_en & sel_counterstop;
wire wr_counterstop  = csr_wr_en & sel_counterstop;
wire counterstop_wr_ena = (wr_counterstop & wbck_csr_wen);
wire [`E203_XLEN-1:0] minstreth_nxt = minstreth_wr_ena ? wbck_csr_dat : (minstreth_r + 1'b1);
wire [`E203_XLEN-1:0] counterstop_r;
wire counterstop_ena = counterstop_wr_ena;
wire [`E203_XLEN-1:0] counterstop_nxt = {29'b0,wbck_csr_dat[2:0]};
sirv_gnrl_dfflr #(`E203_XLEN) counterstop_dfflr (counterstop_ena, counterstop_nxt, counterstop_r, clk, rst_n);
wire [`E203_XLEN-1:0] csr_counterstop = counterstop_r;
assign tm_stop = counterstop_r[1];

////0xBFE  自定义寄存器用于关闭为debug设计的cpu逻辑
wire sel_mcgstop = (csr_idx == 12'hBFE);//寄存器选择信号
wire rd_mcgstop       = csr_rd_en & sel_mcgstop;
wire wr_mcgstop       = csr_wr_en & sel_mcgstop     ;
wire mcgstop_wr_ena      = (wr_mcgstop      & wbck_csr_wen);
wire [`E203_XLEN-1:0] mcgstop_r;
wire mcgstop_ena = mcgstop_wr_ena;
wire [`E203_XLEN-1:0] mcgstop_nxt = {30'b0,wbck_csr_dat[1:0]};
sirv_gnrl_dfflr #(`E203_XLEN) mcgstop_dfflr (mcgstop_ena, mcgstop_nxt, mcgstop_r, clk, rst_n);
wire [`E203_XLEN-1:0] csr_mcgstop = mcgstop_r;
assign core_cgstop = mcgstop_r[0];// Stop Core clock gating
assign tcm_cgstop = mcgstop_r[1];// Stop TCM  clock gating

////0xBFD	自定义寄存器用于关闭itcm的holdup特性
wire sel_itcmnohold = (csr_idx == 12'hBFD);//寄存器选择信号
wire rd_itcmnohold   = csr_rd_en & sel_itcmnohold;
wire wr_itcmnohold   = csr_wr_en & sel_itcmnohold ;
wire itcmnohold_wr_ena  = (wr_itcmnohold  & wbck_csr_wen);
wire [`E203_XLEN-1:0] itcmnohold_r;
wire itcmnohold_ena = itcmnohold_wr_ena;
wire [`E203_XLEN-1:0] itcmnohold_nxt = {31'b0,wbck_csr_dat[0]};
sirv_gnrl_dfflr #(`E203_XLEN) itcmnohold_dfflr (itcmnohold_ena, itcmnohold_nxt, itcmnohold_r, clk, rst_n);

wire [`E203_XLEN-1:0] csr_itcmnohold  = itcmnohold_r;
assign itcm_nohold = itcmnohold_r[0];

////0xBF0	自定义关闭乘除法的back2back特性
wire sel_mdvnob2b = (csr_idx == 12'hBF0);//寄存器选择信号
wire rd_mdvnob2b   = csr_rd_en & sel_mdvnob2b;
wire wr_mdvnob2b   = csr_wr_en & sel_mdvnob2b ;
wire mdvnob2b_wr_ena  = (wr_mdvnob2b  & wbck_csr_wen);
wire [`E203_XLEN-1:0] mdvnob2b_r;
wire mdvnob2b_ena = mdvnob2b_wr_ena;
wire [`E203_XLEN-1:0] mdvnob2b_nxt = {31'b0,wbck_csr_dat[0]};
sirv_gnrl_dfflr #(`E203_XLEN) mdvnob2b_dfflr (mdvnob2b_ena, mdvnob2b_nxt, mdvnob2b_r, clk, rst_n);
wire [`E203_XLEN-1:0] csr_mdvnob2b  = mdvnob2b_r;
assign mdv_nob2b = mdvnob2b_r[0];











////0x341 机器模式异常pc寄存器
wire sel_mepc = (csr_idx == 12'h341);
wire rd_mepc = sel_mepc & csr_rd_en;
wire wr_mepc = sel_mepc & csr_wr_en;
wire epc_ena = (wr_mepc & wbck_csr_wen) | cmt_epc_ena;
wire [`E203_PC_SIZE-1:0] epc_r;
wire [`E203_PC_SIZE-1:0] epc_nxt;
assign epc_nxt[`E203_PC_SIZE-1:1] = cmt_epc_ena ? cmt_epc[`E203_PC_SIZE-1:1] : wbck_csr_dat[`E203_PC_SIZE-1:1];
assign epc_nxt[0] = 1'b0;				//cmt_epc_ena表示是否发生异常 //cmt_epc是发生异常时的pc //wbck_csr_dat 外部传来需要写入的数据
sirv_gnrl_dfflr #(`E203_PC_SIZE) epc_dfflr (epc_ena, epc_nxt, epc_r, clk, rst_n);
wire [`E203_XLEN-1:0] csr_mepc;
wire dummy_0;//占位，无意义
assign {dummy_0,csr_mepc} = {{`E203_XLEN+1-`E203_PC_SIZE{1'b0}},epc_r};
assign csr_epc_r = csr_mepc;





////0x342机器模式异常原因寄存器
wire sel_mcause = (csr_idx == 12'h342);
wire rd_mcause = sel_mcause & csr_rd_en;
wire wr_mcause = sel_mcause & csr_wr_en;
wire cause_ena = (wr_mcause & wbck_csr_wen) | cmt_cause_ena;
wire [`E203_XLEN-1:0] cause_r;
wire [`E203_XLEN-1:0] cause_nxt;
assign cause_nxt[31]  = cmt_cause_ena ? cmt_cause[31] : wbck_csr_dat[31];
assign cause_nxt[30:4] = 27'b0;
assign cause_nxt[3:0] = cmt_cause_ena ? cmt_cause[3:0] : wbck_csr_dat[3:0];
sirv_gnrl_dfflr #(`E203_XLEN) cause_dfflr (cause_ena, cause_nxt, cause_r, clk, rst_n);
wire [`E203_XLEN-1:0] csr_mcause = cause_r;



////0x343 机器模式异常值寄存器
wire sel_mbadaddr = (csr_idx == 12'h343);
wire rd_mbadaddr = sel_mbadaddr & csr_rd_en;
wire wr_mbadaddr = sel_mbadaddr & csr_wr_en;
wire cmt_trap_badaddr_ena = cmt_badaddr_ena;
wire badaddr_ena = (wr_mbadaddr & wbck_csr_wen) | cmt_trap_badaddr_ena;
wire [`E203_ADDR_SIZE-1:0] badaddr_r;
wire [`E203_ADDR_SIZE-1:0] badaddr_nxt;
assign badaddr_nxt = cmt_trap_badaddr_ena ? cmt_badaddr : wbck_csr_dat[`E203_ADDR_SIZE-1:0];
sirv_gnrl_dfflr #(`E203_ADDR_SIZE) badaddr_dfflr (badaddr_ena, badaddr_nxt, badaddr_r, clk, rst_n);
wire [`E203_XLEN-1:0] csr_mbadaddr;
wire dummy_1;
assign {dummy_1,csr_mbadaddr} = {{`E203_XLEN+1-`E203_ADDR_SIZE{1'b0}},badaddr_r};









////0x301	机器模式指令集架构寄存器 仅可读
wire sel_misa = (csr_idx == 12'h301);
wire rd_misa = sel_misa & csr_rd_en;
wire [`E203_XLEN-1:0] csr_misa = {
    2'b1
   ,4'b0 
   ,1'b0 
   ,1'b0 
   ,1'b0 
   ,1'b0
   ,1'b0 
   ,1'b0 
   ,1'b0 
   ,1'b0 
   ,1'b0 
   ,1'b0 
   ,1'b0 
   ,1'b0
   ,1'b0
   ,1'b1 
   ,1'b0 
   ,1'b0
   ,1'b0 
   ,1'b1 
   ,1'b0 
   ,1'b0 
   ,1'b0         
   ,1'b0 
   ,1'b0 
   ,1'b1 
   ,1'b0 
   ,1'b1 
                           };
									

									
									
////各种机器信息
//////0xF11 	机器模式供应商编号寄存器
wire rd_mvendorid = csr_rd_en & (csr_idx == 12'hF11);
wire [`E203_XLEN-1:0] csr_mvendorid = `E203_XLEN'h536;
//////0xF12 机器模式架构编号寄存器
wire rd_marchid   = csr_rd_en & (csr_idx == 12'hF12);
wire [`E203_XLEN-1:0] csr_marchid = `E203_XLEN'hE203;
//////0xF13 机器模式硬件实现编号寄存器
wire rd_mimpid    = csr_rd_en & (csr_idx == 12'hF13);
wire [`E203_XLEN-1:0] csr_mimpid = `E203_XLEN'h1;
//////0xF14 hart编号寄存器
wire rd_mhartid   = csr_rd_en & (csr_idx == 12'hF14);
wire [`E203_XLEN-1:0] csr_mhartid = {{`E203_XLEN-`E203_HART_ID_W{1'b0}},core_mhartid};


////debug相关
//////0x7B0 debug控制和状态寄存器
wire sel_dcsr = (csr_idx == 12'h7b0);
wire rd_dcsr = dbg_mode & csr_rd_en & sel_dcsr    ;
assign wr_dcsr_ena = dbg_mode & csr_wr_en & sel_dcsr    ;
wire [`E203_XLEN-1:0] csr_dcsr = dcsr_r 
//////0x7B1 debug pc
wire sel_dpc = (csr_idx == 12'h7b1);
wire rd_dpc = dbg_mode & csr_rd_en & sel_dpc     ;
assign wr_dpc_ena = dbg_mode & csr_wr_en & sel_dpc     ;
wire [`E203_XLEN-1:0] csr_dpc = dpc_r     ;
assign csr_dpc_r = dpc_r;
//////0x7B2 debug 开始寄存器
wire sel_dscratch = (csr_idx == 12'h7b2);
wire rd_dscratch = dbg_mode & csr_rd_en & sel_dscratch;
assign wr_dscratch_ena = dbg_mode & csr_wr_en & sel_dscratch;
wire [`E203_XLEN-1:0] csr_dscratch = dscratch_r;




//输出 并行多路选择器
assign read_csr_dat = `E203_XLEN'b0 
               | ({`E203_XLEN{rd_mstatus  }} & csr_mstatus  )
               | ({`E203_XLEN{rd_mie      }} & csr_mie      )
               | ({`E203_XLEN{rd_mtvec    }} & csr_mtvec    )
               | ({`E203_XLEN{rd_mepc     }} & csr_mepc     )
               | ({`E203_XLEN{rd_mscratch }} & csr_mscratch )
               | ({`E203_XLEN{rd_mcause   }} & csr_mcause   )
               | ({`E203_XLEN{rd_mbadaddr }} & csr_mbadaddr )
               | ({`E203_XLEN{rd_mip      }} & csr_mip      )
               | ({`E203_XLEN{rd_misa     }} & csr_misa      )
               | ({`E203_XLEN{rd_mvendorid}} & csr_mvendorid)
               | ({`E203_XLEN{rd_marchid  }} & csr_marchid  )
               | ({`E203_XLEN{rd_mimpid   }} & csr_mimpid   )
               | ({`E203_XLEN{rd_mhartid  }} & csr_mhartid  )
               | ({`E203_XLEN{rd_mcycle   }} & csr_mcycle   )
               | ({`E203_XLEN{rd_mcycleh  }} & csr_mcycleh  )
               | ({`E203_XLEN{rd_minstret }} & csr_minstret )
               | ({`E203_XLEN{rd_minstreth}} & csr_minstreth)
               | ({`E203_XLEN{rd_counterstop}} & csr_counterstop)
               | ({`E203_XLEN{rd_mcgstop}} & csr_mcgstop)
               | ({`E203_XLEN{rd_itcmnohold}} & csr_itcmnohold)
               | ({`E203_XLEN{rd_mdvnob2b}} & csr_mdvnob2b)
               | ({`E203_XLEN{rd_dcsr     }} & csr_dcsr    )
               | ({`E203_XLEN{rd_dpc      }} & csr_dpc     )
               | ({`E203_XLEN{rd_dscratch }} & csr_dscratch)
               ;
					
endmodule

