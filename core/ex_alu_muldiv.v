`include "gen_defines.v"
module ex_alu_muldiv(

);

//alu总控的输入信号
  //握手
  wire muldiv_i_hsked = muldiv_i_valid & muldiv_i_ready;
  //数据
    //信息总线
    wire i_mul    = muldiv_i_info[`E203_DECINFO_MULDIV_MUL   ];//有符号，低32位写回
    wire i_mulh   = muldiv_i_info[`E203_DECINFO_MULDIV_MULH  ];//有符号，高32位写回
    wire i_mulhsu = muldiv_i_info[`E203_DECINFO_MULDIV_MULHSU];//rs1和rs2分别被当作有/无符号数，高32位写回
    wire i_mulhu  = muldiv_i_info[`E203_DECINFO_MULDIV_MULHU ];//无符号乘法，高32位写回
    wire i_div    = muldiv_i_info[`E203_DECINFO_MULDIV_DIV   ];//有符号除法
    wire i_divu   = muldiv_i_info[`E203_DECINFO_MULDIV_DIVU  ];//无符号除法
    wire i_rem    = muldiv_i_info[`E203_DECINFO_MULDIV_REM   ];//有符号，32位余数写回
    wire i_remu   = muldiv_i_info[`E203_DECINFO_MULDIV_REMU  ];//无符号，32位余数写回//b2b写回条件之一
    wire i_b2b    = muldiv_i_info[`E203_DECINFO_MULDIV_B2B   ] & (~flushed_r) & (~mdv_nob2b);
	 //其他数据直接出现运算中
  
  
  
  
//输出写回单元
  //握手
  wire muldiv_o_hsked = muldiv_o_valid & muldiv_o_ready;
  //写回
  wire back2back_seq = i_b2b;//？？
  wire special_cases;
  wire muldiv_i_valid_nb2b = muldiv_i_valid & (~back2back_seq) & (~special_cases);



//运算控制-乘除先设计操作数控制逻辑，在统一用一个与公共数据通路连接的电路进行运算，由周期控制

  //操作数符号扩展  //muldiv_i_rsx，操作数x，来自alu总控  //生成操作数符号
  wire mul_rs1_sign = (i_mulhu)            ? 1'b0 : muldiv_i_rs1[`E203_XLEN-1];
  wire mul_rs2_sign = (i_mulhsu | i_mulhu) ? 1'b0 : muldiv_i_rs2[`E203_XLEN-1];
       //拼接操作数符号和32位操作数，所有无符号运算均当作有符号正数运算
  wire [32:0] mul_op1 = {mul_rs1_sign, muldiv_i_rs1};
  wire [32:0] mul_op2 = {mul_rs2_sign, muldiv_i_rs2}; 
  
  
  //判断是乘法还是除法
  wire i_op_mul = i_mul | i_mulh | i_mulhsu | i_mulhu;
  wire i_op_div = i_div | i_divu | i_rem    | i_remu;
  
 
  //统一的状态机，5个状态，输入数据-执行指令-若为除法，检查是否需要商和余数的矫正
  //							 -商矫正-余数矫正
  localparam MULDIV_STATE_WIDTH = 3;//状态位宽度   
    //5个状态
	 localparam MULDIV_STATE_0TH = 3'd0;
	 localparam MULDIV_STATE_EXEC = 3'd1;
	 localparam MULDIV_STATE_REMD_CHCK = 3'd2;
	 localparam MULDIV_STATE_QUOT_CORR = 3'd3;
	 localparam MULDIV_STATE_REMD_CORR = 3'd4;
    //控制状态的寄存器
	 wire [MULDIV_STATE_WIDTH-1:0] muldiv_state_nxt;//下一个状态
    wire [MULDIV_STATE_WIDTH-1:0] muldiv_state_r;//当前状态
    wire muldiv_state_ena;//状态转移使能
	 assign muldiv_state_ena = state_0th_exit_ena//任意使能即可跳转 
                          | state_exec_exit_ena  
                          | state_remd_chck_exit_ena  
                          | state_quot_corr_exit_ena  
                          | state_remd_corr_exit_ena; 
	 assign muldiv_state_nxt = 
              ({MULDIV_STATE_WIDTH{state_0th_exit_ena      }} & state_0th_nxt      )
            | ({MULDIV_STATE_WIDTH{state_exec_exit_ena     }} & state_exec_nxt     )
            | ({MULDIV_STATE_WIDTH{state_remd_chck_exit_ena}} & state_remd_chck_nxt)
            | ({MULDIV_STATE_WIDTH{state_quot_corr_exit_ena}} & state_quot_corr_nxt)
            | ({MULDIV_STATE_WIDTH{state_remd_corr_exit_ena}} & state_remd_corr_nxt)
              ;
    sirv_gnrl_dfflr #(MULDIV_STATE_WIDTH) muldiv_state_dfflr (muldiv_state_ena, muldiv_state_nxt, muldiv_state_r, clk, rst_n);
	 //状态转移
	   //0
		wire muldiv_sta_is_0th = (muldiv_state_r == MULDIV_STATE_0TH );//判断当前状态是否为0
		wire [MULDIV_STATE_WIDTH-1:0] state_0th_nxt;//下一个状态
		wire state_0th_exit_ena;//退出该状态的使能
		  //转移到状态1   //b2b表示写回，写回则无需转移直接写回
		  assign state_0th_exit_ena = muldiv_sta_is_0th & muldiv_i_valid_nb2b & (~flush_pulse);//转移条件
		  assign state_0th_nxt = MULDIV_STATE_EXEC;		  
		//1
		wire muldiv_sta_is_exec = (muldiv_state_r == MULDIV_STATE_EXEC );//判断当前状态是否为1
		wire [MULDIV_STATE_WIDTH-1:0] state_exec_nxt;//下一个状态
		wire state_exec_exit_ena;//退出该状态的使能
		  //转移到状态2，仅除法用转移至3，乘法转移到1执行b2b
		  wire div_need_corrct;//表示除法是否需要矫正 
		  wire mul_exec_last_cycle;//因为除法和乘法为多周期，最后一个周期才可转移
		  wire div_exec_last_cycle;//xxx_exec_last_cycle表示是否为执行的最后一个周期
		  wire exec_last_cycle;//是否为运算的最后一个周期
		  //assign exec_last_cycle = i_op_mul ? mul_exec_last_cycle : div_exec_last_cycle;
		  assign state_exec_exit_ena =  muldiv_sta_is_exec 
												  & (( exec_last_cycle 
										        & (i_op_div ? 1'b1 : muldiv_o_hsked))
						                    | flush_pulse);
		  assign state_exec_nxt = //流水线冲刷-跳到0
							          (//除法-跳到2，检查是否需要矫正  //乘法-跳到0
										 flush_pulse ? MULDIV_STATE_0TH :
										 i_op_div ? MULDIV_STATE_REMD_CHCK : MULDIV_STATE_0TH
							          );

		  
		//2
		wire muldiv_sta_is_remd_chck = (muldiv_state_r == MULDIV_STATE_REMD_CHCK );//判断当前状态是否为2
		wire [MULDIV_STATE_WIDTH-1:0] state_remd_chck_nxt;//下一个状态
		wire state_remd_chck_exit_ena;//退出该状态的使能
		  //转移到状态3
		  assign state_remd_chck_exit_ena = (muldiv_sta_is_remd_chck //当不需要矫正且输出握手后才能跳到0
														 & ((div_need_corrct ? 1'b1 : muldiv_o_hsked) 
														 | flush_pulse )) ;
		  assign state_remd_chck_nxt = flush_pulse ? MULDIV_STATE_0TH ://当需要矫正时跳转至3，否则去0
												  div_need_corrct ? MULDIV_STATE_QUOT_CORR
												  : MULDIV_STATE_0TH;
		//3
		wire muldiv_sta_is_quot_corr = (muldiv_state_r == MULDIV_STATE_QUOT_CORR );//判断当前状态是否为3
		wire [MULDIV_STATE_WIDTH-1:0] state_quot_corr_nxt;//下一个状态
		wire state_quot_corr_exit_ena;//退出该状态的使能
		  //转移到状态4
		  assign state_quot_corr_exit_ena = (muldiv_sta_is_quot_corr & (flush_pulse | 1'b1));//矫正好后即可跳转
        assign state_quot_corr_nxt  = flush_pulse ? MULDIV_STATE_0TH : MULDIV_STATE_REMD_CORR;
		//4
		wire muldiv_sta_is_remd_corr = (muldiv_state_r == MULDIV_STATE_REMD_CORR );//判断当前状态是否为4
		wire [MULDIV_STATE_WIDTH-1:0] state_remd_corr_nxt;//下一个状态
		wire state_remd_corr_exit_ena;//退出该状态的使能
		  //跳转到状态0
        assign state_remd_corr_exit_ena = (muldiv_sta_is_remd_corr & (flush_pulse | muldiv_o_hsked));
        assign state_remd_corr_nxt = flush_pulse ? MULDIV_STATE_0TH : MULDIV_STATE_0TH;//矫正好后且输出握手即可跳转		  
    
	 
	 //运算周期控制
      //周期控制参数
      localparam EXEC_CNT_W  = 6;//标识参数为6位宽
      localparam EXEC_CNT_1  = 6'd1 ;//进入执行状态时已完成符号扩展，故已经完成一个周期
      localparam EXEC_CNT_16 = 6'd16;//运算需要16个周期-乘，这里表示17个周期，其中第一个周期在0状态完成
      localparam EXEC_CNT_32 = 6'd32;//运算需要32个周期-除，还需要3个周期用于矫正
												 //这里表示33个周期，其中第一个周期在0状态完成
												 //故进入执行周期从新计数的时候应从EXEC_CNT_1开始计数
		//周期计数器
		wire state_exec_enter_ena = muldiv_state_ena & (muldiv_state_nxt == MULDIV_STATE_EXEC);//表示即将进入指令执行状态
		wire[EXEC_CNT_W-1:0] exec_cnt_r;//当前周期数
      wire exec_cnt_set = state_exec_enter_ena;//当进入执行状态时即使能计数寄存器，表示初始化寄存器
      wire exec_cnt_inc = muldiv_sta_is_exec & (~exec_last_cycle);//当前状态为执行状态且不是最后一个周期即使能计数寄存器
      wire exec_cnt_ena = exec_cnt_inc | exec_cnt_set;      //用EXEC_CNT_1初始化寄存器，因为0状态的符号扩展为第一个周期
      wire[EXEC_CNT_W-1:0] exec_cnt_nxt = exec_cnt_set ? EXEC_CNT_1 : (exec_cnt_r + 1'b1);//寄存器的下一个状态
      sirv_gnrl_dfflr #(EXEC_CNT_W) exec_cnt_dfflr (exec_cnt_ena, exec_cnt_nxt, exec_cnt_r, clk, rst_n);
		//周期状态判断
		wire cycle_0th  = muldiv_sta_is_0th;//muldiv_sta_is_0th代表0状态
      wire cycle_16th = (exec_cnt_r == EXEC_CNT_16);//计数器到16，乘的最后一个周期
      wire cycle_32nd = (exec_cnt_r == EXEC_CNT_32);//计数器到32，除的最后一个周期
      assign mul_exec_last_cycle = cycle_16th;
      assign div_exec_last_cycle = cycle_32nd;
      assign exec_last_cycle = i_op_mul ? mul_exec_last_cycle : div_exec_last_cycle;
		                      //i_op_mul表明是否为乘法，选择最终周期信号
    
	 
	 //基4的booth乘法-booth_code为3位，每次计算完算术右移2位，无符号有符号统一为33位，故需要17个周期
	   //|hi 33位|lo 33位| part_prdt_sft1_r 1位|==p空间，part_prdt_sft1_r存储最后的一位
	   wire part_prdt_sft1_r;//当前
		wire part_prdt_sft1_nxt = cycle_0th ? muldiv_i_rs1[1] : part_prdt_lo_r[1];//下一位，每次lo更新的时候，lo的倒数第2位为p空间倒数第3位
		sirv_gnrl_dfflr #(1) part_prdt_sft1_dfflr (part_prdt_lo_ena, part_prdt_sft1_nxt, part_prdt_sft1_r, clk, rst_n);
		//存储中间和结果的寄存器
	   wire [32:0] part_prdt_hi_r;//高33位-当前
	   wire [32:0] part_prdt_lo_r;//低33位-当前
	   wire [32:0] part_prdt_hi_nxt;//高33位-下一个
	   wire [32:0] part_prdt_lo_nxt;//低33位-下一个
		  //更新使能，数据的更新在最后，乘除在一起更新
		  wire mul_exe_cnt_set = exec_cnt_set & i_op_mul;
		  wire mul_exe_cnt_inc = exec_cnt_inc & i_op_mul; 
		  wire part_prdt_hi_ena = mul_exe_cnt_set | mul_exe_cnt_inc | state_exec_exit_ena;
		  wire part_prdt_lo_ena = part_prdt_hi_ena;
        //用从公共数据通路传回来的结果更新	
		  assign part_prdt_hi_nxt = mul_exe_alu_res[34:2];
        assign part_prdt_lo_nxt = {
		                             mul_exe_alu_res[1:0],
											  (cycle_0th ? {mul_rs1_sign,muldiv_i_rs1[31:2]} : part_prdt_lo_r[32:2])
											 }; 
		//BOOTH运算
      wire [2:0] booth_code = cycle_0th  ? {muldiv_i_rs1[1:0],1'b0}//booth_code用于决定中间结果的加减
                            : cycle_16th ? {mul_rs1_sign,part_prdt_lo_r[0],part_prdt_sft1_r}
                            : {part_prdt_lo_r[1:0],part_prdt_sft1_r};
		wire booth_sel_zero = (booth_code == 3'b000) | (booth_code == 3'b111);
      wire booth_sel_two  = (booth_code == 3'b011) | (booth_code == 3'b100);
      wire booth_sel_one  = (~booth_sel_zero) & (~booth_sel_two);
      wire booth_sel_sub  = booth_code[2];//最高位为1则减法，反之则加
            //booth_code运算规则：设被乘数为A
				//000 +0    111 -0
				//001 +A    110 -A
				//010 +A    101 -A
				//011 +2A   100 -2A
		//生成送至公共数据通路进行运算的数据
        //加 or 减		
		  wire mul_exe_alu_add = (~booth_sel_sub);
        wire mul_exe_alu_sub = booth_sel_sub;
		  //两个操作数  每个操作数是35位的，结果res也是35位，直接更新时候舍去后两位达到右移的效果
		  wire [`E203_MULDIV_ADDER_WIDTH-1:0] mul_exe_alu_op2 = 
				({`E203_MULDIV_ADDER_WIDTH{booth_sel_zero}} & `E203_MULDIV_ADDER_WIDTH'b0) 
			 | ({`E203_MULDIV_ADDER_WIDTH{booth_sel_one }} & {mul_rs2_sign,mul_rs2_sign,mul_rs2_sign,muldiv_i_rs2}) 
			 | ({`E203_MULDIV_ADDER_WIDTH{booth_sel_two }} & {mul_rs2_sign,mul_rs2_sign,muldiv_i_rs2,1'b0}) 
				;
        wire [`E203_MULDIV_ADDER_WIDTH-1:0] mul_exe_alu_op1 =
			 cycle_0th ? `E203_MULDIV_ADDER_WIDTH'b0 : {part_prdt_hi_r[32],part_prdt_hi_r[32],part_prdt_hi_r};  
		  //从公共运算通路传回来的结果
		  wire [`E203_MULDIV_ADDER_WIDTH-1:0] mul_exe_alu_res = muldiv_req_alu_res;	
		//运算结果
		wire[`E203_XLEN-1:0] mul_res = i_mul ? part_prdt_lo_r[32:1] : mul_exe_alu_res[31:0];
		 
	 //除法-采用普通的加减交替法
	 wire [32:0] part_remd_r;//余数
    wire [32:0] part_quot_r;//商   //若为无符号运算，操作数的符号默认为正，因此有符号无符号运算统一
    wire div_rs1_sign = (i_divu | i_remu) ? 1'b0 : muldiv_i_rs1[`E203_XLEN-1];//操作数1的符号
    wire div_rs2_sign = (i_divu | i_remu) ? 1'b0 : muldiv_i_rs2[`E203_XLEN-1];//操作数2的符号
    wire [65:0] dividend = {{33{div_rs1_sign}}, div_rs1_sign, muldiv_i_rs1};//部分余数/被除数寄存器
    wire [33:0] divisor  = {div_rs2_sign, div_rs2_sign, muldiv_i_rs2};//除数
    wire quot_0cycl = (dividend[65] ^ divisor[33]) ? 1'b0 : 1'b1;//部分余数/被除数寄存器的最后一位，控制加减，同加异减
    wire [66:0] dividend_lsft1 = {dividend[65:0],quot_0cycl};//左移一位

	


//操作公共数据通路运算
  //特殊情况-仅除法有
  assign special_cases = div_special_cases;
  wire[`E203_XLEN-1:0] special_res = div_special_res;



//流水线冲刷信号
wire flushed_r;
wire flushed_set = flush_pulse;//寄存器置位，由流水线冲刷发生时则置位
wire flushed_clr = muldiv_o_hsked & (~flush_pulse);//当无流水线冲刷发生且将要输出，则清零
wire flushed_ena = flushed_set | flushed_clr;
wire flushed_nxt = flushed_set | (~flushed_clr);
sirv_gnrl_dfflr #(1) flushed_dfflr (flushed_ena, flushed_nxt, flushed_r, clk, rst_n);



