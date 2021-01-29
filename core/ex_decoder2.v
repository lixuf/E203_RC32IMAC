`include "gen_defines.v"

//该模块虽所需代码冗长，但逻辑清晰
//功能: 1.解码ifu传来的IR，划分为对应的功能段
//      2. 根据功能段生成控制信号
//		  3. 根据功能段产生信号，并复用同一条信息总线传输
//		  3. 判断IR是否非法
//		  4. 为ifu回传跳转有关的信号，用于静态预测跳转方向以及控制和数据冒险(jalr)的处理
//实现: 1. 熟悉该cpu支持的指令(RISC-V的RV32IMAC)，指令的具体信息可在作者提供的手册的附录A找到。
			  //RV32IMAC解释：32架构相关，IMAC为支持指令子集的缩写   
			  //		32-32位地址空间，通用寄存器宽度32位                              
			  //		I-支持32个通用整数寄存器，基本指令集
			  //		M-支持整数乘法和除法指令
			  //		A-支持原子操作
			  //		C-支持编码长度为16位的压缩指令，以提高代码密度
			  //指令的具体信息要着重关注以下几点：
			  //		1.是否有立即数和立即数的位置和位数
			  //		2.读写寄存器索引的位置
			  //		3.偏移指令的shmat的位置和位数
			  // 		4.指令的op和func字段，用于译码的主要功能段
			  //		5.有别于基础指令集的功能段
			  //		6.有固定值的字段
//		  2. 将op和func提取出来，每种参与译码的状态单独作为一个wire变量以节省门的数量
//		  3. 利用op和func初步译码，在利用指令的其他位置进一步译码
//		  4. imm部分：
					//1.先根据imm所处的位置和即将对imm做的操作，将所有指令的imm分一个大类
					//2.根据译出的指令控制信号选择相应的imm
//		  5. 寄存器部分：
					//1.根据指令格式将寄存器索引提取出来，32位较为简单，因为寄存器位置相对固定
					//	  ，但是16位压缩指令就比较麻烦。
					//2.根据译出的指令控制信号选择是否使用rs1，rs2和rd(给rs1,rs2和rd使能置位)
//		  6. 信息总线部分：
					//1.该部分主要是为了复用信息总线，解决信号线过多的问题
					//2.除了imm和寄存器相关信号，其他均用信息总线传输
					//3.module中的mul和jal等信号均是输出至ifu级的，alu运算控制信号均来自信息总线
					//4.将指令划分为几大块，每个块放在一起生成控制信号并传输
//		  7. 非法指令的判断：
					//1.根据指令中有固定值的字段和译码出的控制信号进行判断
//		  8. 其他需注意的点：
					//1.j型指令需要向ifu级传送imm部分
					//2.jalr指令所使用的寄存器索引也需要回传ifu级

module ex_decoder(//除作为指令译码器，还担负大部分控制单元的任务
//来自ifu级
input [`IR_Size-1:0] i_instr,
input [`PC_Size-1:0] i_pc,//当前指令对应的pc
input  i_prdt_taken,//表明当前跳转指令的预测地址被接受
input  i_misalgn,//表明当前指令遭遇了取指非对齐异常              
input  i_buserr,//表明当前取指访存错误，来自存储器的错误码               
input  i_muldiv_b2b,//乘除的特殊情况 back2back
input  dbg_mode,//？？？

//来自ifu级，直接输出给其他模块的信号，与i_意义一样
output [`PC_Size-1:0] dec_pc,
output dec_misalgn,
output dec_buserr,

//产生的控制信号
output dec_ilegl,//表明该指令非法
output dec_rv32,//表明该指令是否为32位
  
  
//寄存器信息
////对寄存器的操作信号
output dec_rs1x0,//rs1是x0
output dec_rs2x0,//rs2是x0
output dec_rs1en,//rs1读使能
output dec_rs2en,//rs2读使能
output dec_rdwen,//操作数结果写使能
////指示操作的寄存器编号
output [`E203_RFIDX_WIDTH-1:0] dec_rs1idx,//rs1操作的寄存索引
output [`E203_RFIDX_WIDTH-1:0] dec_rs2idx,//rs2操作的寄存器索引
output [`E203_RFIDX_WIDTH-1:0] dec_rdidx,//结果回写的寄存器索引
////该指令的其他字段信息
output [`E203_DECINFO_WIDTH-1:0] dec_info,//该指令的其他信息，打包为总写格式
output [`E203_XLEN-1:0] dec_imm,//该指令使用的；立即数字段


//mini_decoder，若输入输出接口改变记得更新mini_decoder
////输出至bpu,均为跳转相关
output dec_rv32,
output dec_ifj,
output dec_jal,
output dec_jalr,
output dec_bxx,
output [`RFIDX_WIDTH-1:0] dec_jalr_rs1idx,//jalr用到的寄存器索引
output [`XLEN-1:0] dec_bjp_imm,//跳转指令的立即数，表明跳转地址


//输出至bpu
output dec_mulhsu,
output dec_mul   ,
output dec_div   ,
output dec_rem   ,
output dec_divu  ,
output dec_remu  ,

);

//将IR分为各功能字段

wire [31:0] rv32_instr		=i_instr;
wire [15:0] rv16_instr		=i_instr[15:0];

wire [6:0] opcode		=i_instr[6:0];

////32位

wire [4:0]  rv32_rd     = rv32_instr[11:7];
wire [2:0]  rv32_func3  = rv32_instr[14:12];
wire [4:0]  rv32_rs1    = rv32_instr[19:15];
wire [4:0]  rv32_rs2    = rv32_instr[24:20];
wire [6:0]  rv32_func7  = rv32_instr[31:25];

////16位

wire [4:0]  rv16_rd     = rv32_rd;
wire [4:0]  rv16_rs1    = rv16_rd; 
wire [4:0]  rv16_rs2    = rv32_instr[6:2];

wire [4:0]  rv16_rdd    = {2'b01,rv32_instr[4:2]};
wire [4:0]  rv16_rss1   = {2'b01,rv32_instr[9:7]};
wire [4:0]  rv16_rss2   = rv16_rdd;

wire [2:0]  rv16_func3  = rv32_instr[15:13];

//将各个涉及控制的信号的组合表示出来,以节省门
////opcode

wire opcode_1_0_00  =(opcode[1:0] == 2'b00);
wire opcode_1_0_01  =(opcode[1:0] == 2'b01);
wire opcode_1_0_10  =(opcode[1:0] == 2'b10);
wire opcode_1_0_11  =(opcode[1:0] == 2'b11);
wire opcode_4_2_000 =(opcode[4:2] == 3'b000);
wire opcode_4_2_001 =(opcode[4:2] == 3'b001);
wire opcode_4_2_010 =(opcode[4:2] == 3'b010);
wire opcode_4_2_011 =(opcode[4:2] == 3'b011);
wire opcode_4_2_100 =(opcode[4:2] == 3'b100);
wire opcode_4_2_101 =(opcode[4:2] == 3'b101);
wire opcode_4_2_110 =(opcode[4:2] == 3'b110);
wire opcode_4_2_111 =(opcode[4:2] == 3'b111);
wire opcode_6_5_00  =(opcode[6:5] == 2'b00);
wire opcode_6_5_01  =(opcode[6:5] == 2'b01);
wire opcode_6_5_10  =(opcode[6:5] == 2'b10);
wire opcode_6_5_11  =(opcode[6:5] == 2'b11);

////func
//////func3
////////32位

wire rv32_func3_000 = (rv32_func3 == 3'b000);
wire rv32_func3_001 = (rv32_func3 == 3'b001);
wire rv32_func3_010 = (rv32_func3 == 3'b010);
wire rv32_func3_011 = (rv32_func3 == 3'b011);
wire rv32_func3_100 = (rv32_func3 == 3'b100);
wire rv32_func3_101 = (rv32_func3 == 3'b101);
wire rv32_func3_110 = (rv32_func3 == 3'b110);
wire rv32_func3_111 = (rv32_func3 == 3'b111);

////////16位

wire rv16_func3_000 = (rv16_func3 == 3'b000);
wire rv16_func3_001 = (rv16_func3 == 3'b001);
wire rv16_func3_010 = (rv16_func3 == 3'b010);
wire rv16_func3_011 = (rv16_func3 == 3'b011);
wire rv16_func3_100 = (rv16_func3 == 3'b100);
wire rv16_func3_101 = (rv16_func3 == 3'b101);
wire rv16_func3_110 = (rv16_func3 == 3'b110);
wire rv16_func3_111 = (rv16_func3 == 3'b111);

//////func7

wire rv32_func7_0000000 = (rv32_func7 == 7'b0000000);
wire rv32_func7_0100000 = (rv32_func7 == 7'b0100000);
wire rv32_func7_0000001 = (rv32_func7 == 7'b0000001);
wire rv32_func7_0000101 = (rv32_func7 == 7'b0000101);
wire rv32_func7_0001001 = (rv32_func7 == 7'b0001001);
wire rv32_func7_0001101 = (rv32_func7 == 7'b0001101);
wire rv32_func7_0010101 = (rv32_func7 == 7'b0010101);
wire rv32_func7_0100001 = (rv32_func7 == 7'b0100001);
wire rv32_func7_0010001 = (rv32_func7 == 7'b0010001);
wire rv32_func7_0101101 = (rv32_func7 == 7'b0101101);
wire rv32_func7_1111111 = (rv32_func7 == 7'b1111111);
wire rv32_func7_0000100 = (rv32_func7 == 7'b0000100); 
wire rv32_func7_0001000 = (rv32_func7 == 7'b0001000); 
wire rv32_func7_0001100 = (rv32_func7 == 7'b0001100); 
wire rv32_func7_0101100 = (rv32_func7 == 7'b0101100); 
wire rv32_func7_0010000 = (rv32_func7 == 7'b0010000); 
wire rv32_func7_0010100 = (rv32_func7 == 7'b0010100); 
wire rv32_func7_1100000 = (rv32_func7 == 7'b1100000); 
wire rv32_func7_1110000 = (rv32_func7 == 7'b1110000); 
wire rv32_func7_1010000 = (rv32_func7 == 7'b1010000); 
wire rv32_func7_1101000 = (rv32_func7 == 7'b1101000); 
wire rv32_func7_1111000 = (rv32_func7 == 7'b1111000); 
wire rv32_func7_1010001 = (rv32_func7 == 7'b1010001);  
wire rv32_func7_1110001 = (rv32_func7 == 7'b1110001);  
wire rv32_func7_1100001 = (rv32_func7 == 7'b1100001);  
wire rv32_func7_1101001 = (rv32_func7 == 7'b1101001);  

////寄存器
//////16位
wire rv16_rs1_x0 = (rv16_rs1 == 5'b00000);
wire rv16_rs2_x0 = (rv16_rs2 == 5'b00000);
wire rv16_rd_x0  = (rv16_rd  == 5'b00000);
wire rv16_rd_x2  = (rv16_rd  == 5'b00010);
//////32位
wire rv32_rs1_x0 = (rv32_rs1 == 5'b00000);
wire rv32_rs2_x0 = (rv32_rs2 == 5'b00000);
wire rv32_rs2_x1 = (rv32_rs2 == 5'b00001);
wire rv32_rd_x0  = (rv32_rd  == 5'b00000);
wire rv32_rd_x2  = (rv32_rd  == 5'b00010);
wire rv32_rs1_x31 = (rv32_rs1 == 5'b11111);
wire rv32_rs2_x31 = (rv32_rs2 == 5'b11111);
wire rv32_rd_x31  = (rv32_rd  == 5'b11111);







//控制信号
////大类控制信号
//////32位

wire rv32_load     = opcode_6_5_00 & opcode_4_2_000 & opcode_1_0_11; 
wire rv32_store    = opcode_6_5_01 & opcode_4_2_000 & opcode_1_0_11; 
wire rv32_madd     = opcode_6_5_10 & opcode_4_2_000 & opcode_1_0_11; 
wire rv32_branch   = opcode_6_5_11 & opcode_4_2_000 & opcode_1_0_11; 

wire rv32_load_fp  = opcode_6_5_00 & opcode_4_2_001 & opcode_1_0_11; 
wire rv32_store_fp = opcode_6_5_01 & opcode_4_2_001 & opcode_1_0_11; 
wire rv32_msub     = opcode_6_5_10 & opcode_4_2_001 & opcode_1_0_11; 
wire rv32_jalr     = opcode_6_5_11 & opcode_4_2_001 & opcode_1_0_11; 

wire rv32_custom0  = opcode_6_5_00 & opcode_4_2_010 & opcode_1_0_11; 
wire rv32_custom1  = opcode_6_5_01 & opcode_4_2_010 & opcode_1_0_11; 
wire rv32_nmsub    = opcode_6_5_10 & opcode_4_2_010 & opcode_1_0_11; 
wire rv32_resved0  = opcode_6_5_11 & opcode_4_2_010 & opcode_1_0_11; 


wire rv32_miscmem  = opcode_6_5_00 & opcode_4_2_011 & opcode_1_0_11;
wire rv32_amo      = opcode_6_5_01 & opcode_4_2_011 & opcode_1_0_11;  
wire rv32_nmadd    = opcode_6_5_10 & opcode_4_2_011 & opcode_1_0_11; 
wire rv32_jal      = opcode_6_5_11 & opcode_4_2_011 & opcode_1_0_11; 

wire rv32_op_imm   = opcode_6_5_00 & opcode_4_2_100 & opcode_1_0_11; 
wire rv32_op       = opcode_6_5_01 & opcode_4_2_100 & opcode_1_0_11; 
wire rv32_op_fp    = opcode_6_5_10 & opcode_4_2_100 & opcode_1_0_11; 
wire rv32_system   = opcode_6_5_11 & opcode_4_2_100 & opcode_1_0_11; 

wire rv32_auipc    = opcode_6_5_00 & opcode_4_2_101 & opcode_1_0_11; 
wire rv32_lui      = opcode_6_5_01 & opcode_4_2_101 & opcode_1_0_11; 
wire rv32_resved1  = opcode_6_5_10 & opcode_4_2_101 & opcode_1_0_11; 
wire rv32_resved2  = opcode_6_5_11 & opcode_4_2_101 & opcode_1_0_11; 

wire rv32_op_imm_32= opcode_6_5_00 & opcode_4_2_110 & opcode_1_0_11; 
wire rv32_op_32    = opcode_6_5_01 & opcode_4_2_110 & opcode_1_0_11; 
wire rv32_custom2  = opcode_6_5_10 & opcode_4_2_110 & opcode_1_0_11; 
wire rv32_custom3  = opcode_6_5_11 & opcode_4_2_110 & opcode_1_0_11;  

//////16位  

wire rv16_addi         = opcode_1_0_01 & rv16_func3_000;
wire rv16_jal          = opcode_1_0_01 & rv16_func3_001;
wire rv16_li           = opcode_1_0_01 & rv16_func3_010;
wire rv16_lui_addi16sp = opcode_1_0_01 & rv16_func3_011;
wire rv16_miscalu      = opcode_1_0_01 & rv16_func3_100;
wire rv16_j            = opcode_1_0_01 & rv16_func3_101;
wire rv16_beqz         = opcode_1_0_01 & rv16_func3_110;
wire rv16_bnez         = opcode_1_0_01 & rv16_func3_111;


wire rv16_slli         = opcode_1_0_10 & rv16_func3_000;
wire rv16_lwsp         = opcode_1_0_10 & rv16_func3_010;
wire rv16_jalr_mv_add  = opcode_1_0_10 & rv16_func3_100;
wire rv16_swsp         = opcode_1_0_10 & rv16_func3_110;


								 

						


						
////小类控制信号
//////32位
    //branch
wire rv32_beq      = rv32_branch & rv32_func3_000;
wire rv32_bne      = rv32_branch & rv32_func3_001;
wire rv32_blt      = rv32_branch & rv32_func3_100;
wire rv32_bgt      = rv32_branch & rv32_func3_101;
wire rv32_bltu     = rv32_branch & rv32_func3_110;
wire rv32_bgtu     = rv32_branch & rv32_func3_111;
    //系统调用
wire rv32_ecall    = rv32_system & rv32_func3_000 & (rv32_instr[31:20] == 12'b0000_0000_0000);
wire rv32_ebreak   = rv32_system & rv32_func3_000 & (rv32_instr[31:20] == 12'b0000_0000_0001);
wire rv32_mret     = rv32_system & rv32_func3_000 & (rv32_instr[31:20] == 12'b0011_0000_0010);
wire rv32_dret     = rv32_system & rv32_func3_000 & (rv32_instr[31:20] == 12'b0111_1011_0010);
wire rv32_wfi      = rv32_system & rv32_func3_000 & (rv32_instr[31:20] == 12'b0001_0000_0101);

wire rv32_csrrw    = rv32_system & rv32_func3_001; 
wire rv32_csrrs    = rv32_system & rv32_func3_010; 
wire rv32_csrrc    = rv32_system & rv32_func3_011; 
wire rv32_csrrwi   = rv32_system & rv32_func3_101; 
wire rv32_csrrsi   = rv32_system & rv32_func3_110; 
wire rv32_csrrci   = rv32_system & rv32_func3_111; 
wire rv32_dret_ilgl = rv32_dret & (~dbg_mode);
wire rv32_ecall_ebreak_ret_wfi = rv32_system & rv32_func3_000;
wire rv32_csr          = rv32_system & (~rv32_func3_000);
	 //j型指令
assign dec_jal     = rv32_jal    | rv16_jal  | rv16_j;
assign dec_jalr    = rv32_jalr   | rv16_jalr | rv16_jr;
assign dec_bxx     = rv32_branch | rv16_beqz | rv16_bnez;
assign dec_bjp     = dec_jal | dec_jalr | dec_bxx;
wire rv32_fence  ;
wire rv32_fence_i;
wire rv32_fence_fencei;
wire bjp_op = dec_bjp | rv32_mret | (rv32_dret & (~rv32_dret_ilgl)) | rv32_fence_fencei;//表明是否位j型指令
	 //需要alu的指令
wire rv32_addi     = rv32_op_imm & rv32_func3_000;
wire rv32_slti     = rv32_op_imm & rv32_func3_010;
wire rv32_sltiu    = rv32_op_imm & rv32_func3_011;
wire rv32_xori     = rv32_op_imm & rv32_func3_100;
wire rv32_ori      = rv32_op_imm & rv32_func3_110;
wire rv32_andi     = rv32_op_imm & rv32_func3_111;

wire rv32_slli     = rv32_op_imm & rv32_func3_001 & (rv32_instr[31:26] == 6'b000000);
wire rv32_srli     = rv32_op_imm & rv32_func3_101 & (rv32_instr[31:26] == 6'b000000);
wire rv32_srai     = rv32_op_imm & rv32_func3_101 & (rv32_instr[31:26] == 6'b010000);

wire rv32_add      = rv32_op     & rv32_func3_000 & rv32_func7_0000000;
wire rv32_sub      = rv32_op     & rv32_func3_000 & rv32_func7_0100000;
wire rv32_sll      = rv32_op     & rv32_func3_001 & rv32_func7_0000000;
wire rv32_slt      = rv32_op     & rv32_func3_010 & rv32_func7_0000000;
wire rv32_sltu     = rv32_op     & rv32_func3_011 & rv32_func7_0000000;
wire rv32_xor      = rv32_op     & rv32_func3_100 & rv32_func7_0000000;
wire rv32_srl      = rv32_op     & rv32_func3_101 & rv32_func7_0000000;
wire rv32_sra      = rv32_op     & rv32_func3_101 & rv32_func7_0100000;
wire rv32_or       = rv32_op     & rv32_func3_110 & rv32_func7_0000000;
wire rv32_and      = rv32_op     & rv32_func3_111 & rv32_func7_0000000;

wire rv32_nop      = rv32_addi & rv32_rs1_x0 & rv32_rd_x0 & (~(|rv32_instr[31:20]));
wire ecall_ebreak = rv32_ecall | rv32_ebreak | rv16_ebreak;

wire alu_op = (~rv32_sxxi_shamt_ilgl) & (~rv16_sxxi_shamt_ilgl)//aluop 控制alu的运算
              & (~rv16_li_lui_ilgl) & (~rv16_addi4spn_ilgl) & (~rv16_addi16sp_ilgl) & 
              ( rv32_op_imm 
              | rv32_op & (~rv32_func7_0000001) 
              | rv32_auipc
              | rv32_lui
              | rv16_addi4spn
              | rv16_addi         
              | rv16_lui_addi16sp 
              | rv16_li | rv16_mv
              | rv16_slli         
              | rv16_miscalu  
              | rv16_add
              | rv16_nop | rv32_nop
              | rv32_wfi
              | ecall_ebreak)
              ;

	 //存储器指令
assign rv32_fence    = rv32_miscmem & rv32_func3_000;
assign rv32_fence_i  = rv32_miscmem & rv32_func3_001;
assign rv32_fence_fencei  = rv32_miscmem;
	 //乘除法指令
wire rv32_mul      = rv32_op     & rv32_func3_000 & rv32_func7_0000001;
wire rv32_mulh     = rv32_op     & rv32_func3_001 & rv32_func7_0000001;
wire rv32_mulhsu   = rv32_op     & rv32_func3_010 & rv32_func7_0000001;
wire rv32_mulhu    = rv32_op     & rv32_func3_011 & rv32_func7_0000001;
wire rv32_div      = rv32_op     & rv32_func3_100 & rv32_func7_0000001;
wire rv32_divu     = rv32_op     & rv32_func3_101 & rv32_func7_0000001;
wire rv32_rem      = rv32_op     & rv32_func3_110 & rv32_func7_0000001;
wire rv32_remu     = rv32_op     & rv32_func3_111 & rv32_func7_0000001;	 
wire muldiv_op = rv32_op & rv32_func7_0000001;

assign dec_mulhsu = rv32_mulh | rv32_mulhsu | rv32_mulhu;
assign dec_mul    = rv32_mul;
assign dec_div    = rv32_div ;
assign dec_divu   = rv32_divu;
assign dec_rem    = rv32_rem;
assign dec_remu   = rv32_rem
	//存储器存取指令
wire rv32_lb       = rv32_load   & rv32_func3_000;
wire rv32_lh       = rv32_load   & rv32_func3_001;
wire rv32_lw       = rv32_load   & rv32_func3_010;
wire rv32_lbu      = rv32_load   & rv32_func3_100;
wire rv32_lhu      = rv32_load   & rv32_func3_101;

wire rv32_sb       = rv32_store  & rv32_func3_000;
wire rv32_sh       = rv32_store  & rv32_func3_001;
wire rv32_sw       = rv32_store  & rv32_func3_010;
	//原子操作
wire rv32_lr_w      = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b00010);
wire rv32_sc_w      = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b00011);
wire rv32_amoswap_w = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b00001);
wire rv32_amoadd_w  = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b00000);
wire rv32_amoxor_w  = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b00100);
wire rv32_amoand_w  = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b01100);
wire rv32_amoor_w   = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b01000);
wire rv32_amomin_w  = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b10000);
wire rv32_amomax_w  = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b10100);
wire rv32_amominu_w = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b11000);
wire rv32_amomaxu_w = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b11100);
wire   amoldst_op = rv32_amo | rv32_load | rv32_store | rv16_lw | rv16_sw | (rv16_lwsp & (~rv16_lwsp_ilgl)) | rv16_swsp;
wire [1:0] lsu_info_size  = rv32 ? rv32_func3[1:0] : 2'b10;
wire       lsu_info_usign = rv32? rv32_func3[2] : 1'b0;
//////16位
	//没有浮点数运算，均置0
   wire rv16_flw          = 1'b0;
   wire rv16_fld          = 1'b0;
   wire rv16_fsw          = 1'b0;
   wire rv16_fsd          = 1'b0;
   wire rv16_fldsp        = 1'b0;
   wire rv16_flwsp        = 1'b0;
   wire rv16_fsdsp        = 1'b0;
   wire rv16_fswsp        = 1'b0;


wire rv16_nop          = rv16_addi  
                         & (~i_instr[12]) & (rv16_rd_x0) & (rv16_rs2_x0);

wire rv16_srli         = rv16_miscalu  & (i_instr[11:10] == 2'b00);
wire rv16_srai         = rv16_miscalu  & (i_instr[11:10] == 2'b01);
wire rv16_andi         = rv16_miscalu  & (i_instr[11:10] == 2'b10);

wire rv16_addi16sp     = rv16_lui_addi16sp & rv32_rd_x2;
wire rv16_lui          = rv16_lui_addi16sp & (~rv32_rd_x0) & (~rv32_rd_x2);


wire rv16_subxororand  = rv16_miscalu  & (rv16_instr[12:10] == 3'b011);
wire rv16_sub          = rv16_subxororand & (rv16_instr[6:5] == 2'b00);
wire rv16_xor          = rv16_subxororand & (rv16_instr[6:5] == 2'b01);
wire rv16_or           = rv16_subxororand & (rv16_instr[6:5] == 2'b10);
wire rv16_and          = rv16_subxororand & (rv16_instr[6:5] == 2'b11);

wire rv16_jr           = rv16_jalr_mv_add 
                         & (~rv16_instr[12]) & (~rv16_rs1_x0) & (rv16_rs2_x0);
wire rv16_mv           = rv16_jalr_mv_add 
                         & (~rv16_instr[12]) & (~rv16_rd_x0) & (~rv16_rs2_x0);
wire rv16_ebreak       = rv16_jalr_mv_add 
                         & (rv16_instr[12]) & (rv16_rd_x0) & (rv16_rs2_x0);
wire rv16_jalr         = rv16_jalr_mv_add 
                         & (rv16_instr[12]) & (~rv16_rs1_x0) & (rv16_rs2_x0);
wire rv16_add          = rv16_jalr_mv_add 
                         & (rv16_instr[12]) & (~rv16_rd_x0) & (~rv16_rs2_x0);
						 
						 
////信息总线						 
		//跳转相关
wire [`E203_DECINFO_BJP_WIDTH-1:0] bjp_info_bus;
assign bjp_info_bus[`E203_DECINFO_GRP    ]    = `E203_DECINFO_GRP_BJP;
assign bjp_info_bus[`E203_DECINFO_RV32   ]    = rv32;
assign bjp_info_bus[`E203_DECINFO_BJP_JUMP ]  = dec_jal | dec_jalr;
assign bjp_info_bus[`E203_DECINFO_BJP_BPRDT]  = i_prdt_taken;
assign bjp_info_bus[`E203_DECINFO_BJP_BEQ  ]  = rv32_beq | rv16_beqz;
assign bjp_info_bus[`E203_DECINFO_BJP_BNE  ]  = rv32_bne | rv16_bnez;
assign bjp_info_bus[`E203_DECINFO_BJP_BLT  ]  = rv32_blt; 
assign bjp_info_bus[`E203_DECINFO_BJP_BGT  ]  = rv32_bgt ;
assign bjp_info_bus[`E203_DECINFO_BJP_BLTU ]  = rv32_bltu;
assign bjp_info_bus[`E203_DECINFO_BJP_BGTU ]  = rv32_bgtu;
assign bjp_info_bus[`E203_DECINFO_BJP_BXX  ]  = dec_bxx;
assign bjp_info_bus[`E203_DECINFO_BJP_MRET ]  = rv32_mret;
assign bjp_info_bus[`E203_DECINFO_BJP_DRET ]  = rv32_dret;
assign bjp_info_bus[`E203_DECINFO_BJP_FENCE ]  = rv32_fence;
assign bjp_info_bus[`E203_DECINFO_BJP_FENCEI]  = rv32_fence_i;	 		
	   //alu操作
wire need_imm;//在后面的imm专栏中
wire [`E203_DECINFO_ALU_WIDTH-1:0] alu_info_bus;
assign alu_info_bus[`E203_DECINFO_GRP    ]    = `E203_DECINFO_GRP_ALU;
assign alu_info_bus[`E203_DECINFO_RV32   ]    = rv32;
assign alu_info_bus[`E203_DECINFO_ALU_ADD]    = rv32_add  | rv32_addi | rv32_auipc |
                                                  rv16_addi4spn | rv16_addi | rv16_addi16sp | rv16_add |

                                                  rv16_li | rv16_mv;
assign alu_info_bus[`E203_DECINFO_ALU_SUB]    = rv32_sub  | rv16_sub;      
assign alu_info_bus[`E203_DECINFO_ALU_SLT]    = rv32_slt  | rv32_slti;     
assign alu_info_bus[`E203_DECINFO_ALU_SLTU]   = rv32_sltu | rv32_sltiu;  
assign alu_info_bus[`E203_DECINFO_ALU_XOR]    = rv32_xor  | rv32_xori | rv16_xor;    
assign alu_info_bus[`E203_DECINFO_ALU_SLL]    = rv32_sll  | rv32_slli | rv16_slli;   
assign alu_info_bus[`E203_DECINFO_ALU_SRL]    = rv32_srl  | rv32_srli | rv16_srli;
assign alu_info_bus[`E203_DECINFO_ALU_SRA]    = rv32_sra  | rv32_srai | rv16_srai;   
assign alu_info_bus[`E203_DECINFO_ALU_OR ]    = rv32_or   | rv32_ori  | rv16_or;     
assign alu_info_bus[`E203_DECINFO_ALU_AND]    = rv32_and  | rv32_andi | rv16_andi | rv16_and;
assign alu_info_bus[`E203_DECINFO_ALU_LUI]    = rv32_lui  | rv16_lui; 
assign alu_info_bus[`E203_DECINFO_ALU_OP2IMM] = need_imm; 
assign alu_info_bus[`E203_DECINFO_ALU_OP1PC ] = rv32_auipc;
assign alu_info_bus[`E203_DECINFO_ALU_NOP ]   = rv16_nop | rv32_nop;
assign alu_info_bus[`E203_DECINFO_ALU_ECAL ]  = rv32_ecall; 
assign alu_info_bus[`E203_DECINFO_ALU_EBRK ]  = rv32_ebreak | rv16_ebreak;
assign alu_info_bus[`E203_DECINFO_ALU_WFI  ]  = rv32_wfi;		
		//alu中的	状态寄存器 csr
wire csr_op = rv32_csr;
wire [`E203_DECINFO_CSR_WIDTH-1:0] csr_info_bus;
assign csr_info_bus[`E203_DECINFO_GRP    ]    = `E203_DECINFO_GRP_CSR;
assign csr_info_bus[`E203_DECINFO_RV32   ]    = rv32;
assign csr_info_bus[`E203_DECINFO_CSR_CSRRW ] = rv32_csrrw | rv32_csrrwi; 
assign csr_info_bus[`E203_DECINFO_CSR_CSRRS ] = rv32_csrrs | rv32_csrrsi;
assign csr_info_bus[`E203_DECINFO_CSR_CSRRC ] = rv32_csrrc | rv32_csrrci;
assign csr_info_bus[`E203_DECINFO_CSR_RS1IMM] = rv32_csrrwi | rv32_csrrsi | rv32_csrrci;
assign csr_info_bus[`E203_DECINFO_CSR_ZIMMM ] = rv32_rs1;
assign csr_info_bus[`E203_DECINFO_CSR_RS1IS0] = rv32_rs1_x0;
assign csr_info_bus[`E203_DECINFO_CSR_CSRIDX] = rv32_instr[31:20];	 		
		//乘除法
wire [`E203_DECINFO_MULDIV_WIDTH-1:0] muldiv_info_bus;
assign muldiv_info_bus[`E203_DECINFO_GRP          ] = `E203_DECINFO_GRP_MULDIV;
assign muldiv_info_bus[`E203_DECINFO_RV32         ] = rv32        ;
assign muldiv_info_bus[`E203_DECINFO_MULDIV_MUL   ] = rv32_mul    ;   
assign muldiv_info_bus[`E203_DECINFO_MULDIV_MULH  ] = rv32_mulh   ;
assign muldiv_info_bus[`E203_DECINFO_MULDIV_MULHSU] = rv32_mulhsu ;
assign muldiv_info_bus[`E203_DECINFO_MULDIV_MULHU ] = rv32_mulhu  ;
assign muldiv_info_bus[`E203_DECINFO_MULDIV_DIV   ] = rv32_div    ;
assign muldiv_info_bus[`E203_DECINFO_MULDIV_DIVU  ] = rv32_divu   ;
assign muldiv_info_bus[`E203_DECINFO_MULDIV_REM   ] = rv32_rem    ;
assign muldiv_info_bus[`E203_DECINFO_MULDIV_REMU  ] = rv32_remu   ;
assign muldiv_info_bus[`E203_DECINFO_MULDIV_B2B   ] = i_muldiv_b2b;		
		//原子操作
wire [`E203_DECINFO_AGU_WIDTH-1:0] agu_info_bus;
assign agu_info_bus[`E203_DECINFO_GRP    ] = `E203_DECINFO_GRP_AGU;
assign agu_info_bus[`E203_DECINFO_RV32   ] = rv32;
assign agu_info_bus[`E203_DECINFO_AGU_LOAD   ] = rv32_load  | rv32_lr_w | rv16_lw | rv16_lwsp;
assign agu_info_bus[`E203_DECINFO_AGU_STORE  ] = rv32_store | rv32_sc_w | rv16_sw | rv16_swsp;
assign agu_info_bus[`E203_DECINFO_AGU_SIZE   ] = lsu_info_size;
assign agu_info_bus[`E203_DECINFO_AGU_USIGN  ] = lsu_info_usign;
assign agu_info_bus[`E203_DECINFO_AGU_EXCL   ] = rv32_lr_w | rv32_sc_w;
assign agu_info_bus[`E203_DECINFO_AGU_AMO    ] = rv32_amo & (~(rv32_lr_w | rv32_sc_w));// We seperated the EXCL out of AMO in LSU handling
assign agu_info_bus[`E203_DECINFO_AGU_AMOSWAP] = rv32_amoswap_w;
assign agu_info_bus[`E203_DECINFO_AGU_AMOADD ] = rv32_amoadd_w ;
assign agu_info_bus[`E203_DECINFO_AGU_AMOAND ] = rv32_amoand_w ;
assign agu_info_bus[`E203_DECINFO_AGU_AMOOR  ] = rv32_amoor_w ;
assign agu_info_bus[`E203_DECINFO_AGU_AMOXOR ] = rv32_amoxor_w  ;
assign agu_info_bus[`E203_DECINFO_AGU_AMOMAX ] = rv32_amomax_w ;
assign agu_info_bus[`E203_DECINFO_AGU_AMOMIN ] = rv32_amomin_w ;
assign agu_info_bus[`E203_DECINFO_AGU_AMOMAXU] = rv32_amomaxu_w;
assign agu_info_bus[`E203_DECINFO_AGU_AMOMINU] = rv32_amominu_w;
assign agu_info_bus[`E203_DECINFO_AGU_OP2IMM ] = need_imm; 
	//总
assign dec_info = //选择输出的信息总线
              ({`E203_DECINFO_WIDTH{alu_op}}     & {{`E203_DECINFO_WIDTH-`E203_DECINFO_ALU_WIDTH{1'b0}},alu_info_bus})
            | ({`E203_DECINFO_WIDTH{amoldst_op}} & {{`E203_DECINFO_WIDTH-`E203_DECINFO_AGU_WIDTH{1'b0}},agu_info_bus})
            | ({`E203_DECINFO_WIDTH{bjp_op}}     & {{`E203_DECINFO_WIDTH-`E203_DECINFO_BJP_WIDTH{1'b0}},bjp_info_bus})
            | ({`E203_DECINFO_WIDTH{csr_op}}     & {{`E203_DECINFO_WIDTH-`E203_DECINFO_CSR_WIDTH{1'b0}},csr_info_bus})
            | ({`E203_DECINFO_WIDTH{muldiv_op}}  & {{`E203_DECINFO_WIDTH-`E203_DECINFO_CSR_WIDTH{1'b0}},muldiv_info_bus})
              ;
		
						 
						 
						 
//imm相关								 
////各种基类imm
//////32位
wire [31:0]  rv32_j_imm = {
                               {11{rv32_instr[31]}} 
                              , rv32_instr[31] 
                              , rv32_instr[19:12] 
                              , rv32_instr[20] 
                              , rv32_instr[30:21]
                              , 1'b0
                              };

wire [31:0]  rv32_i_imm = { 
                               {20{rv32_instr[31]}} 
                              , rv32_instr[31:20]
                             };

wire [31:0]  rv32_s_imm = {
                               {20{rv32_instr[31]}} 
                              , rv32_instr[31:25] 
                              , rv32_instr[11:7]
                             };


wire [31:0]  rv32_b_imm = {
                               {19{rv32_instr[31]}} 
                              , rv32_instr[31] 
                              , rv32_instr[7] 
                              , rv32_instr[30:25] 
                              , rv32_instr[11:8]
                              , 1'b0
                              };

wire [31:0]  rv32_u_imm = {rv32_instr[31:12],12'b0};
wire [31:0]  rv32_jalr_imm = rv32_i_imm;
wire [31:0]  rv32_jal_imm = rv32_j_imm;
wire [31:0]  rv32_bxx_imm = rv32_b_imm;
wire [31:0]  rv32_load_fp_imm  = rv32_i_imm;
wire [31:0]  rv32_store_fp_imm = rv32_s_imm;
//////16位
wire [31:0]  rv16_cis_imm ={
                          24'b0
                        , rv16_instr[3:2]
                        , rv16_instr[12]
                        , rv16_instr[6:4]
                        , 2'b0
                         };
wire [31:0]  rv16_cis_d_imm ={
                          23'b0
                        , rv16_instr[4:2]
                        , rv16_instr[12]
                        , rv16_instr[6:5]
                        , 3'b0
                         };

wire [31:0]  rv16_cili_imm ={
                          {26{rv16_instr[12]}}
                        , rv16_instr[12]
                        , rv16_instr[6:2]
                         };
wire [31:0]  rv16_cilui_imm ={
                          {14{rv16_instr[12]}}
                        , rv16_instr[12]
                        , rv16_instr[6:2]
                        , 12'b0
                         };
wire [31:0]  rv16_ci16sp_imm ={
                          {22{rv16_instr[12]}}
                        , rv16_instr[12]
                        , rv16_instr[4]
                        , rv16_instr[3]
                        , rv16_instr[5]
                        , rv16_instr[2]
                        , rv16_instr[6]
                        , 4'b0
                         };
wire [31:0]  rv16_css_imm ={
                          24'b0
                        , rv16_instr[8:7]
                        , rv16_instr[12:9]
                        , 2'b0
                         };
wire [31:0]  rv16_css_d_imm ={
                          23'b0
                        , rv16_instr[9:7]
                        , rv16_instr[12:10]
                        , 3'b0
                         };
wire [31:0]  rv16_ciw_imm ={
                          22'b0
                        , rv16_instr[10:7]
                        , rv16_instr[12]
                        , rv16_instr[11]
                        , rv16_instr[5]
                        , rv16_instr[6]
                        , 2'b0
                         };
wire [31:0]  rv16_cl_imm ={
                          25'b0
                        , rv16_instr[5]
                        , rv16_instr[12]
                        , rv16_instr[11]
                        , rv16_instr[10]
                        , rv16_instr[6]
                        , 2'b0
                         };
wire [31:0]  rv16_cl_d_imm ={
                          24'b0
                        , rv16_instr[6]
                        , rv16_instr[5]
                        , rv16_instr[12]
                        , rv16_instr[11]
                        , rv16_instr[10]
                        , 3'b0
                         };
wire [31:0]  rv16_cs_imm ={
                          25'b0
                        , rv16_instr[5]
                        , rv16_instr[12]
                        , rv16_instr[11]
                        , rv16_instr[10]
                        , rv16_instr[6]
                        , 2'b0
                         };
wire [31:0]  rv16_cs_d_imm ={
                          24'b0
                        , rv16_instr[6]
                        , rv16_instr[5]
                        , rv16_instr[12]
                        , rv16_instr[11]
                        , rv16_instr[10]
                        , 3'b0
                         };
wire [31:0]  rv16_cb_imm ={
                          {23{rv16_instr[12]}}
                        , rv16_instr[12]
                        , rv16_instr[6:5]
                        , rv16_instr[2]
                        , rv16_instr[11:10]
                        , rv16_instr[4:3]
                        , 1'b0
                         };
wire [31:0]  rv16_cj_imm ={
                          {20{rv16_instr[12]}}
                        , rv16_instr[12]
                        , rv16_instr[8]
                        , rv16_instr[10:9]
                        , rv16_instr[6]
                        , rv16_instr[7]
                        , rv16_instr[2]
                        , rv16_instr[11]
                        , rv16_instr[5:3]
                        , 1'b0
                         };		 
wire [31:0]  rv16_jjal_imm = rv16_cj_imm;
wire [31:0]  rv16_jrjalr_imm = 32'b0;
wire [31:0]  rv32_load_fp_imm  = rv32_i_imm;
wire [31:0]  rv32_store_fp_imm = rv32_s_imm;

////imm控制信号
//////总类型
assign need_imm = rv32 ? rv32_need_imm : rv16_need_imm; 
assign dec_imm = rv32 ? rv32_imm : rv16_imm;
assign dec_bjp_imm = 
                     ({32{rv16_jal | rv16_j     }} & rv16_jjal_imm)
                   | ({32{rv16_jalr_mv_add      }} & rv16_jrjalr_imm)
                   | ({32{rv16_beqz | rv16_bnez }} & rv16_bxx_imm)
                   | ({32{rv32_jal              }} & rv32_jal_imm)
                   | ({32{rv32_jalr             }} & rv32_jalr_imm)
                   | ({32{rv32_branch           }} & rv32_bxx_imm)
                   ;						
//////32位
    //由控制信号决定选择哪个格式的imm
wire [31:0]  rv32_imm = 
                     ({32{rv32_imm_sel_i}} & rv32_i_imm)
                   | ({32{rv32_imm_sel_s}} & rv32_s_imm)
                   | ({32{rv32_imm_sel_b}} & rv32_b_imm)
                   | ({32{rv32_imm_sel_u}} & rv32_u_imm)
                   | ({32{rv32_imm_sel_j}} & rv32_j_imm)
                   ;
    //imm控制信号，表明使用哪个格式的imm
wire rv32_imm_sel_i = rv32_op_imm | rv32_jalr | rv32_load;
wire rv32_imm_sel_jalr = rv32_jalr; 
wire rv32_imm_sel_u = rv32_lui | rv32_auipc;
wire rv32_imm_sel_j = rv32_jal;
wire rv32_imm_sel_jal = rv32_jal;
wire rv32_imm_sel_b = rv32_branch;
wire rv32_imm_sel_bxx = rv32_branch;
wire rv32_imm_sel_s = rv32_store;
wire  rv32_need_imm = 
                     rv32_imm_sel_i
                   | rv32_imm_sel_s
                   | rv32_imm_sel_b
                   | rv32_imm_sel_u
                   | rv32_imm_sel_j
                   ;						
						
//////16位						
	//由控制信号决定选择哪个格式的imm
wire [31:0]  rv16_imm = 
                     ({32{rv16_imm_sel_cis   }} & rv16_cis_imm)
                   | ({32{rv16_imm_sel_cili  }} & rv16_cili_imm)
                   | ({32{rv16_imm_sel_cilui }} & rv16_cilui_imm)
                   | ({32{rv16_imm_sel_ci16sp}} & rv16_ci16sp_imm)
                   | ({32{rv16_imm_sel_css   }} & rv16_css_imm)
                   | ({32{rv16_imm_sel_ciw   }} & rv16_ciw_imm)
                   | ({32{rv16_imm_sel_cl    }} & rv16_cl_imm)
                   | ({32{rv16_imm_sel_cs    }} & rv16_cs_imm)
                   | ({32{rv16_imm_sel_cb    }} & rv16_cb_imm)
                   | ({32{rv16_imm_sel_cj    }} & rv16_cj_imm)
                   ;	
	
	//imm控制信号，表明使用哪个格式的imm
wire rv16_imm_sel_cis = rv16_lwsp;						
wire rv16_imm_sel_cili = rv16_li | rv16_addi | rv16_slli
                   | rv16_srai | rv16_srli | rv16_andi;						
wire rv16_imm_sel_cilui = rv16_lui;						
wire rv16_imm_sel_ci16sp = rv16_addi16sp;						
wire rv16_imm_sel_css = rv16_swsp;
wire rv16_imm_sel_ciw = rv16_addi4spn;
wire rv16_imm_sel_cl = rv16_lw;
wire rv16_imm_sel_cs = rv16_sw;
wire rv16_imm_sel_cb = rv16_beqz | rv16_bnez;
wire rv16_imm_sel_cj = rv16_j | rv16_jal;
wire rv16_need_imm = 
                     rv16_imm_sel_cis   
                   | rv16_imm_sel_cili  
                   | rv16_imm_sel_cilui 
                   | rv16_imm_sel_ci16sp
                   | rv16_imm_sel_css   
                   | rv16_imm_sel_ciw   
                   | rv16_imm_sel_cl    
                   | rv16_imm_sel_cs    
                   | rv16_imm_sel_cb    
                   | rv16_imm_sel_cj    
                   ;



						 
//寄存器相关
////总控
assign dec_rs1idx = rv32 ? rv32_rs1[`E203_RFIDX_WIDTH-1:0] : rv16_rs1idx;
assign dec_rs2idx = rv32 ? rv32_rs2[`E203_RFIDX_WIDTH-1:0] : rv16_rs2idx;
assign dec_rdidx  = rv32 ? rv32_rd [`E203_RFIDX_WIDTH-1:0] : rv16_rdidx ;


assign dec_rs1en = rv32 ? rv32_need_rs1 : (rv16_rs1en & (~(rv16_rs1idx == `E203_RFIDX_WIDTH'b0))); 
assign dec_rs2en = rv32 ? rv32_need_rs2 : (rv16_rs2en & (~(rv16_rs2idx == `E203_RFIDX_WIDTH'b0)));
assign dec_rdwen = rv32 ? rv32_need_rd  : (rv16_rden  & (~(rv16_rdidx  == `E203_RFIDX_WIDTH'b0)));

assign dec_rs1x0 = (dec_rs1idx == `E203_RFIDX_WIDTH'b0);
assign dec_rs2x0 = (dec_rs2idx == `E203_RFIDX_WIDTH'b0);

assign dec_jalr_rs1idx = rv32 ? rv32_rs1[`E203_RFIDX_WIDTH-1:0] : rv16_rs1[`E203_RFIDX_WIDTH-1:0]; 

////32位
wire rv32_need_rd = 
                      (~rv32_rd_x0) & (
                    (
                      (~rv32_branch) & (~rv32_store)
                    & (~rv32_fence_fencei)
                    & (~rv32_ecall_ebreak_ret_wfi) 
                    )
                   );
wire rv32_need_rs1 =
                      (~rv32_rs1_x0) & (
                    (
                      (~rv32_lui)
                    & (~rv32_auipc)
                    & (~rv32_jal)
                    & (~rv32_fence_fencei)
                    & (~rv32_ecall_ebreak_ret_wfi)
                    & (~rv32_csrrwi)
                    & (~rv32_csrrsi)
                    & (~rv32_csrrci)
                    )
                  );
wire rv32_need_rs2 = (~rv32_rs2_x0) & (
                (
                 (rv32_branch)
               | (rv32_store)
               | (rv32_op)
               | (rv32_amo & (~rv32_lr_w))
                 )
                 );	
////16位，很复杂，不同指令寄存器索引位置有很大差异
  //将16位指令根据寄存器索引在指令中的位置划分为8组
  wire rv16_format_cr  = rv16_jalr_mv_add;
  wire rv16_format_ci  = rv16_lwsp | rv16_flwsp | rv16_fldsp | rv16_li | rv16_lui_addi16sp | rv16_addi | rv16_slli; 
  wire rv16_format_css = rv16_swsp | rv16_fswsp | rv16_fsdsp; 
  wire rv16_format_ciw = rv16_addi4spn; 
  wire rv16_format_cl  = rv16_lw | rv16_flw | rv16_fld; 
  wire rv16_format_cs  = rv16_sw | rv16_fsw | rv16_fsd | rv16_subxororand; 
  wire rv16_format_cb  = rv16_beqz | rv16_bnez | rv16_srli | rv16_srai | rv16_andi; 
  wire rv16_format_cj  = rv16_j | rv16_jal; 	
  //将以上8组挨个分析
      //CR
		wire rv16_need_cr_rs1   = rv16_format_cr & 1'b1;
	   wire rv16_need_cr_rs2   = rv16_format_cr & 1'b1;
	   wire rv16_need_cr_rd    = rv16_format_cr & 1'b1;
	   wire [`E203_RFIDX_WIDTH-1:0] rv16_cr_rs1 = rv16_mv ? `E203_RFIDX_WIDTH'd0 : rv16_rs1[`E203_RFIDX_WIDTH-1:0];
	   wire [`E203_RFIDX_WIDTH-1:0] rv16_cr_rs2 = rv16_rs2[`E203_RFIDX_WIDTH-1:0];
	   wire [`E203_RFIDX_WIDTH-1:0] rv16_cr_rd  = (rv16_jalr | rv16_jr)? 
						  {{`E203_RFIDX_WIDTH-1{1'b0}},rv16_instr[12]} : rv16_rd[`E203_RFIDX_WIDTH-1:0];
							 
		//CI
		wire rv16_need_ci_rs1   = rv16_format_ci & 1'b1;
	   wire rv16_need_ci_rs2   = rv16_format_ci & 1'b0;
	   wire rv16_need_ci_rd    = rv16_format_ci & 1'b1;
	   wire [`E203_RFIDX_WIDTH-1:0] rv16_ci_rs1 = (rv16_lwsp | rv16_flwsp | rv16_fldsp) ? `E203_RFIDX_WIDTH'd2 :
											 (rv16_li | rv16_lui) ? `E203_RFIDX_WIDTH'd0 : rv16_rs1[`E203_RFIDX_WIDTH-1:0];
	   wire [`E203_RFIDX_WIDTH-1:0] rv16_ci_rs2 = `E203_RFIDX_WIDTH'd0;
	   wire [`E203_RFIDX_WIDTH-1:0] rv16_ci_rd  = rv16_rd[`E203_RFIDX_WIDTH-1:0];
		//CSS					 
		wire rv16_need_css_rs1  = rv16_format_css & 1'b1;
		wire rv16_need_css_rs2  = rv16_format_css & 1'b1;
		wire rv16_need_css_rd   = rv16_format_css & 1'b0;
		wire [`E203_RFIDX_WIDTH-1:0] rv16_css_rs1 = `E203_RFIDX_WIDTH'd2;
		wire [`E203_RFIDX_WIDTH-1:0] rv16_css_rs2 = rv16_rs2[`E203_RFIDX_WIDTH-1:0];
		wire [`E203_RFIDX_WIDTH-1:0] rv16_css_rd  = `E203_RFIDX_WIDTH'd0;					 
		//CIW				 
		wire rv16_need_ciw_rss1 = rv16_format_ciw & 1'b1;
		wire rv16_need_ciw_rss2 = rv16_format_ciw & 1'b0;
		wire rv16_need_ciw_rdd  = rv16_format_ciw & 1'b1;
		wire [`E203_RFIDX_WIDTH-1:0] rv16_ciw_rss1  = `E203_RFIDX_WIDTH'd2;
		wire [`E203_RFIDX_WIDTH-1:0] rv16_ciw_rss2  = `E203_RFIDX_WIDTH'd0;
		wire [`E203_RFIDX_WIDTH-1:0] rv16_ciw_rdd  = rv16_rdd[`E203_RFIDX_WIDTH-1:0];				 
		//CL				 
		wire rv16_need_cl_rss1  = rv16_format_cl & 1'b1;
		wire rv16_need_cl_rss2  = rv16_format_cl & 1'b0;
		wire rv16_need_cl_rdd   = rv16_format_cl & 1'b1;
		wire [`E203_RFIDX_WIDTH-1:0] rv16_cl_rss1 = rv16_rss1[`E203_RFIDX_WIDTH-1:0];
		wire [`E203_RFIDX_WIDTH-1:0] rv16_cl_rss2 = `E203_RFIDX_WIDTH'd0;
		wire [`E203_RFIDX_WIDTH-1:0] rv16_cl_rdd  = rv16_rdd[`E203_RFIDX_WIDTH-1:0];
		//CS
		wire rv16_need_cs_rss1  = rv16_format_cs & 1'b1;
		wire rv16_need_cs_rss2  = rv16_format_cs & 1'b1;
		wire rv16_need_cs_rdd   = rv16_format_cs & rv16_subxororand;
		wire [`E203_RFIDX_WIDTH-1:0] rv16_cs_rss1 = rv16_rss1[`E203_RFIDX_WIDTH-1:0];
		wire [`E203_RFIDX_WIDTH-1:0] rv16_cs_rss2 = rv16_rss2[`E203_RFIDX_WIDTH-1:0];
		wire [`E203_RFIDX_WIDTH-1:0] rv16_cs_rdd  = rv16_rss1[`E203_RFIDX_WIDTH-1:0];
		//CB
		wire rv16_need_cb_rss1  = rv16_format_cb & 1'b1;
		wire rv16_need_cb_rss2  = rv16_format_cb & (rv16_beqz | rv16_bnez);
		wire rv16_need_cb_rdd   = rv16_format_cb & (~(rv16_beqz | rv16_bnez));
		wire [`E203_RFIDX_WIDTH-1:0] rv16_cb_rss1 = rv16_rss1[`E203_RFIDX_WIDTH-1:0];
		wire [`E203_RFIDX_WIDTH-1:0] rv16_cb_rss2 = `E203_RFIDX_WIDTH'd0;
		wire [`E203_RFIDX_WIDTH-1:0] rv16_cb_rdd  = rv16_rss1[`E203_RFIDX_WIDTH-1:0];
		//CJ
		wire rv16_need_cj_rss1  = rv16_format_cj & 1'b0;
		wire rv16_need_cj_rss2  = rv16_format_cj & 1'b0;
		wire rv16_need_cj_rdd   = rv16_format_cj & 1'b1;
		wire [`E203_RFIDX_WIDTH-1:0] rv16_cj_rss1 = `E203_RFIDX_WIDTH'd0;
		wire [`E203_RFIDX_WIDTH-1:0] rv16_cj_rss2 = `E203_RFIDX_WIDTH'd0;
		wire [`E203_RFIDX_WIDTH-1:0] rv16_cj_rdd  = rv16_j ? `E203_RFIDX_WIDTH'd0 : `E203_RFIDX_WIDTH'd1;
	//综合起来，最终输出所需索引
	wire rv16_need_rs1 = rv16_need_cr_rs1 | rv16_need_ci_rs1 | rv16_need_css_rs1;
   wire rv16_need_rs2 = rv16_need_cr_rs2 | rv16_need_ci_rs2 | rv16_need_css_rs2;
   wire rv16_need_rd  = rv16_need_cr_rd  | rv16_need_ci_rd  | rv16_need_css_rd;

   wire rv16_need_rss1 = rv16_need_ciw_rss1|rv16_need_cl_rss1|rv16_need_cs_rss1|rv16_need_cb_rss1|rv16_need_cj_rss1;
   wire rv16_need_rss2 = rv16_need_ciw_rss2|rv16_need_cl_rss2|rv16_need_cs_rss2|rv16_need_cb_rss2|rv16_need_cj_rss2;
   wire rv16_need_rdd  = rv16_need_ciw_rdd |rv16_need_cl_rdd |rv16_need_cs_rdd |rv16_need_cb_rdd |rv16_need_cj_rdd ;

   wire rv16_rs1en = (rv16_need_rs1 | rv16_need_rss1);
   wire rv16_rs2en = (rv16_need_rs2 | rv16_need_rss2);
   wire rv16_rden  = (rv16_need_rd  | rv16_need_rdd );

   wire [`E203_RFIDX_WIDTH-1:0] rv16_rs1idx;
   wire [`E203_RFIDX_WIDTH-1:0] rv16_rs2idx;
   wire [`E203_RFIDX_WIDTH-1:0] rv16_rdidx ;
	assign rv16_rs1idx = //rs1所需寄存器索引
         ({`E203_RFIDX_WIDTH{rv16_need_cr_rs1 }} & rv16_cr_rs1)
       | ({`E203_RFIDX_WIDTH{rv16_need_ci_rs1 }} & rv16_ci_rs1)
       | ({`E203_RFIDX_WIDTH{rv16_need_css_rs1}} & rv16_css_rs1)
       | ({`E203_RFIDX_WIDTH{rv16_need_ciw_rss1}} & rv16_ciw_rss1)
       | ({`E203_RFIDX_WIDTH{rv16_need_cl_rss1}}  & rv16_cl_rss1)
       | ({`E203_RFIDX_WIDTH{rv16_need_cs_rss1}}  & rv16_cs_rss1)
       | ({`E203_RFIDX_WIDTH{rv16_need_cb_rss1}}  & rv16_cb_rss1)
       | ({`E203_RFIDX_WIDTH{rv16_need_cj_rss1}}  & rv16_cj_rss1)
       ;

  assign rv16_rs2idx = //rs2所需寄存器索引
         ({`E203_RFIDX_WIDTH{rv16_need_cr_rs2 }} & rv16_cr_rs2)
       | ({`E203_RFIDX_WIDTH{rv16_need_ci_rs2 }} & rv16_ci_rs2)
       | ({`E203_RFIDX_WIDTH{rv16_need_css_rs2}} & rv16_css_rs2)
       | ({`E203_RFIDX_WIDTH{rv16_need_ciw_rss2}} & rv16_ciw_rss2)
       | ({`E203_RFIDX_WIDTH{rv16_need_cl_rss2}}  & rv16_cl_rss2)
       | ({`E203_RFIDX_WIDTH{rv16_need_cs_rss2}}  & rv16_cs_rss2)
       | ({`E203_RFIDX_WIDTH{rv16_need_cb_rss2}}  & rv16_cb_rss2)
       | ({`E203_RFIDX_WIDTH{rv16_need_cj_rss2}}  & rv16_cj_rss2)
       ;

  assign rv16_rdidx = //回写所需寄存器索引
         ({`E203_RFIDX_WIDTH{rv16_need_cr_rd }} & rv16_cr_rd)
       | ({`E203_RFIDX_WIDTH{rv16_need_ci_rd }} & rv16_ci_rd)
       | ({`E203_RFIDX_WIDTH{rv16_need_css_rd}} & rv16_css_rd)
       | ({`E203_RFIDX_WIDTH{rv16_need_ciw_rdd}} & rv16_ciw_rdd)
       | ({`E203_RFIDX_WIDTH{rv16_need_cl_rdd}}  & rv16_cl_rdd)
       | ({`E203_RFIDX_WIDTH{rv16_need_cs_rdd}}  & rv16_cs_rdd)
       | ({`E203_RFIDX_WIDTH{rv16_need_cb_rdd}}  & rv16_cb_rdd)
       | ({`E203_RFIDX_WIDTH{rv16_need_cj_rdd}}  & rv16_cj_rdd)
       ;
		
		
		
		
		
		
		
		
		
		
//其他输出信号
wire rv32 = (~(i_instr[4:2] == 3'b111)) & opcode_1_0_11;
assign dec_rv32 = rv32;////判断位数,并输出
assign dec_pc  = i_pc
assign dec_misalgn = i_misalgn;//来自ifu级，表明取值产生非对齐异常
assign dec_buserr  = i_buserr ;//来自ifu级的错误码，表明取指令错误
assign dec_ilegl = //当前指令为非法指令
            (rv_all0s1s_ilgl) 
          | (rv_index_ilgl) 
          | (rv16_addi16sp_ilgl)
          | (rv16_addi4spn_ilgl)
          | (rv16_li_lui_ilgl)
          | (rv16_sxxi_shamt_ilgl)
          | (rv32_sxxi_shamt_ilgl)
          | (rv32_dret_ilgl)
          | (rv16_lwsp_ilgl)
          | (~legl_ops);
		//分别判断各种类型指令是否符合还是非法
        //32位
		wire rv32_sxxi_shamt_legl = (rv32_instr[25] == 1'b0); //对于sxxi型指令，第26位必须为0，否则非法
		wire rv32_sxxi_shamt_ilgl =  (rv32_slli | rv32_srli | rv32_srai) & (~rv32_sxxi_shamt_legl);

		wire rv32_all0s_ilgl  = rv32_func7_0000000 
                        & rv32_rs2_x0 
                        & rv32_rs1_x0 
                        & rv32_func3_000 
                        & rv32_rd_x0 
                        & opcode_6_5_00 
                        & opcode_4_2_000 
                        & (opcode[1:0] == 2'b00); 
		wire rv32_all1s_ilgl  = rv32_func7_1111111 
                        & rv32_rs2_x31 
                        & rv32_rs1_x31 
                        & rv32_func3_111 
                        & rv32_rd_x31 
                        & opcode_6_5_11 
                        & opcode_4_2_111 
                        & (opcode[1:0] == 2'b11); 
		  //16位
		wire rv16_all0s_ilgl  = rv16_func3_000 
                        & rv32_func3_000 
                        & rv32_rd_x0     
                        & opcode_6_5_00 
                        & opcode_4_2_000 
                        & (opcode[1:0] == 2'b00); 						
		wire rv16_all1s_ilgl  = rv16_func3_111
                        & rv32_func3_111 
                        & rv32_rd_x31 
                        & opcode_6_5_11 
                        & opcode_4_2_111 
                        & (opcode[1:0] == 2'b11);
		wire rv16_lwsp_ilgl    = rv16_lwsp & rv16_rd_x0;
		wire rv16_sxxi_shamt_legl = 
							  rv16_instr_12_is0 
							& (~(rv16_instr_6_2_is0s)) 
							  ;
							  

		wire rv16_li_ilgl = rv16_li & (rv16_rd_x0);
		 
		wire rv16_lui_ilgl = rv16_lui & (rv16_rd_x0 | rv16_rd_x2 | (rv16_instr_6_2_is0s & rv16_instr_12_is0));

		wire rv16_li_lui_ilgl = rv16_li_ilgl | rv16_lui_ilgl;

		wire rv16_addi4spn_ilgl = rv16_addi4spn & (rv16_instr_12_is0 & rv16_rd_x0 & opcode_6_5_00);
		wire rv16_addi16sp_ilgl = rv16_addi16sp & rv16_instr_12_is0 & rv16_instr_6_2_is0s; 
		
		wire i_instr_12_is0   = (i_instr[12] == 1'b0);//判断给定位是否全0
		wire i_instr_6_2_is0s = (i_instr[6:2] == 5'b0);//判断给定位是否全0
		wire rv16_sxxi_shamt_ilgl =  (rv16_slli | rv16_srli | rv16_srai) & (~rv16_sxxi_shamt_legl);
  
		  //公共
		wire rv_all0s1s_ilgl = rv32 ?  (rv32_all0s_ilgl | rv32_all1s_ilgl)
                              :  (rv16_all0s_ilgl | rv16_all1s_ilgl);
						
		wire rv_index_ilgl;//表明取得的寄存器索引是否错误
      assign rv_index_ilgl = 1'b0;//手册说从未发生，其他数量的(非32个寄存器)才会发生
		wire legl_ops = //合法的操作
              alu_op
            | amoldst_op
            | bjp_op
            | csr_op
            | muldiv_op
            ;
endmodule
