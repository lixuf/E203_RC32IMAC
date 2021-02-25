//该模块为ALU的公共数据通路，实现时应将该模块划分为多个单元，每个单元的格式比较统一，了解格式和功能即可实现
//功能：1. 受alu的各个控制单元控制，接受alu各个控制单元传来的输入数据，运算后，写回给各个
//			  控制单元
//	    2. alu的控制单元包括：ALU普通运算单元：逻辑运算，加减法和移位
//			(输入输出按此划分)	访存地址生成(AGU)：load，store，和A扩展指令的地址生成
//						         多周期乘除法器：乘法和除法
//									分支预测解析(BJP)：Branch和Jump的结果解析
//								   CSR读写控制直接控制CSR与该模块无关
//		 3. 运算通路包括： 移位-将右移转化为左移
//								加法器-除了加减法和乘除法过程中的加减法还处理比较大小操作
//								逻辑运算-除了逻辑运算还处理比较是否相等运算
//							   比较大小，比较是否相等，乘除法过程中的加减法和minmax已经在上面得出结果，因此需单写输入输出部分
//		 4. 为AGU和MDV设置共享的66位寄存器，高低33位是分开存储的
//实现：1. 输入输出格式：控制控制信号更新的门控信号-输入
// 						  所需操作数-输入
//                     结果-输出
//							  各种控制信号-输入
//		 2. 运算通路格式：操作数预处理-仅移位和加法器需要
//                     门控信号的控制门
//						     输入
//							  输出
//		 3. 最终结果： 门控信号&输出信号 按照and-or的写法即可
//     4. 与各个alu控制模块的连线
//     5. MDV和AGU的共享66位寄存器，按照标准格式写即可：使能，next，r
//注意：1.该模块大量使用门控信号的方式减少功耗
//     2. 加法器为了统一乘除法的加减运算设置为35bit，因此其他操作数需要符号扩展至35bit
//     3. 右移通过逆置的方式转化为左移
//		 4. 逻辑运算中仅仅异或使用了门控信号的方式，或和且过于轻量就没有用
//     5. 比较是否相等由异或运算而不是加法器是为了加速和减少功耗，异或更快
`include "gen_defines.v"
module ex_alu_dpath(
//普通alu运算
  input  alu_req_alu,//控制信号更新的门控信号
  
  input  [`E203_XLEN-1:0] alu_req_alu_op1,//该类操作的操作数1
  input  [`E203_XLEN-1:0] alu_req_alu_op2,//该类操作的操作数2
  output [`E203_XLEN-1:0] alu_req_alu_res,//结果

  //各种控制信号
  input  alu_req_alu_add ,
  input  alu_req_alu_sub ,
  input  alu_req_alu_xor ,
  input  alu_req_alu_sll ,
  input  alu_req_alu_srl ,
  input  alu_req_alu_sra ,
  input  alu_req_alu_or  ,
  input  alu_req_alu_and ,
  input  alu_req_alu_slt ,
  input  alu_req_alu_sltu,
  input  alu_req_alu_lui ,


//BJP
  input  bjp_req_alu,//控制信号更新的门控信号
  
  input  [`E203_XLEN-1:0] bjp_req_alu_op1,//该类操作的操作数1
  input  [`E203_XLEN-1:0] bjp_req_alu_op2,//该类操作的操作数2
  output bjp_req_alu_cmp_res,//结果-跳转
  output [`E203_XLEN-1:0] bjp_req_alu_add_res,//结果-目标地址
  
  //各种控制信号
  input  bjp_req_alu_cmp_eq ,
  input  bjp_req_alu_cmp_ne ,
  input  bjp_req_alu_cmp_lt ,
  input  bjp_req_alu_cmp_gt ,
  input  bjp_req_alu_cmp_ltu,
  input  bjp_req_alu_cmp_gtu,
  input  bjp_req_alu_add,


//AGU访存地址生成
  input  agu_req_alu,//控制信号更新的门控信号
  
  input  [`E203_XLEN-1:0] agu_req_alu_op1,//该类操作的操作数1
  input  [`E203_XLEN-1:0] agu_req_alu_op2,//该类操作的操作数2
  output [`E203_XLEN-1:0] agu_req_alu_res,//结果
  
  //各种控制信号
  input  agu_req_alu_swap,
  input  agu_req_alu_add ,
  input  agu_req_alu_and ,
  input  agu_req_alu_or  ,
  input  agu_req_alu_xor ,
  input  agu_req_alu_max ,
  input  agu_req_alu_min ,
  input  agu_req_alu_maxu,
  input  agu_req_alu_minu,

  
  //共享数据缓存器
  input  agu_sbf_0_ena,
  input  [`E203_XLEN-1:0] agu_sbf_0_nxt,
  output [`E203_XLEN-1:0] agu_sbf_0_r,
  input  agu_sbf_1_ena,
  input  [`E203_XLEN-1:0] agu_sbf_1_nxt,
  output [`E203_XLEN-1:0] agu_sbf_1_r,



//乘除法
  input  muldiv_req_alu,//控制信号更新的门控信号
  
  input  [`E203_ALU_ADDER_WIDTH-1:0] muldiv_req_alu_op1,//该类操作的操作数1
  input  [`E203_ALU_ADDER_WIDTH-1:0] muldiv_req_alu_op2,//该类操作的操作数2
  output [`E203_ALU_ADDER_WIDTH-1:0] muldiv_req_alu_res,//结果
  
  //各种控制信号
  input muldiv_req_alu_add ,
  input muldiv_req_alu_sub ,
	
  //共享数据缓存器
  input  muldiv_sbf_0_ena,
  input  [33-1:0] muldiv_sbf_0_nxt,
  output [33-1:0] muldiv_sbf_0_r,
  input  muldiv_sbf_1_ena,
  input  [33-1:0] muldiv_sbf_1_nxt,
  output [33-1:0] muldiv_sbf_1_r,


  input  clk,
  input  rst_n
);

//操作数
	//来自 alu的各种运算控制器-乘除法的操作数直接出现在加法器中
	wire [`E203_XLEN-1:0] mux_op1;
	wire [`E203_XLEN-1:0] mux_op2;
	//除了移位运算以外的操作数
	wire [`E203_XLEN-1:0] misc_op1 = mux_op1[`E203_XLEN-1:0];
	wire [`E203_XLEN-1:0] misc_op2 = mux_op2[`E203_XLEN-1:0];
	//移位运算操作数
	wire [`E203_XLEN-1:0] shifter_op1 = alu_req_alu_op1[`E203_XLEN-1:0];
	wire [`E203_XLEN-1:0] shifter_op2 = alu_req_alu_op2[`E203_XLEN-1:0];
	
//输出控制信号  
wire op_max;//最大值  
wire op_min ;//最小值 
wire op_maxu;//无符号—最大值
wire op_minu;//无符号-最小值
wire op_add;//加
wire op_sub;//减
wire op_addsub = op_add | op_sub;//是否加减-开启加减法运算模块 
wire op_or;//或
wire op_xor;//异或
wire op_and;//与
wire op_sll;//逻辑左移
wire op_srl;//逻辑右移
wire op_sra;//算术右移
wire op_slt;//有符号比较置位
wire op_sltu;//无符号比较置位
wire op_mvop2;//lui指令
wire op_cmp_eq ;//比较-相等
wire op_cmp_ne ;//比较-不等
wire op_cmp_lt ;//比较-小于
wire op_cmp_gt ;//比较-大于
wire op_cmp_ltu;//无符号-小于
wire op_cmp_gtu;//无符号-大于
wire cmp_res;//比较结果

//共享数据缓冲器,两个寄存器
	//寄存器本体
	wire sbf_0_ena;
	wire [33-1:0] sbf_0_nxt;
	wire [33-1:0] sbf_0_r;
	sirv_gnrl_dffl #(33) sbf_0_dffl (sbf_0_ena, sbf_0_nxt, sbf_0_r, clk);
	wire sbf_1_ena;
	wire [33-1:0] sbf_1_nxt;
	wire [33-1:0] sbf_1_r;
	sirv_gnrl_dffl #(33) sbf_1_dffl (sbf_1_ena, sbf_1_nxt, sbf_1_r, clk);
	//使能信号
	assign muldiv_req_alu_res  = adder_res;//控制使能信号来自AGU还是MDV
	assign sbf_0_ena = muldiv_req_alu ? muldiv_sbf_0_ena : agu_sbf_0_ena;
	assign sbf_1_ena = muldiv_req_alu ? muldiv_sbf_1_ena : agu_sbf_1_ena;
	//待输入寄存器的信号
	assign sbf_0_nxt = muldiv_req_alu ? muldiv_sbf_0_nxt : {1'b0,agu_sbf_0_nxt};
	assign sbf_1_nxt = muldiv_req_alu ? muldiv_sbf_1_nxt : {1'b0,agu_sbf_1_nxt};
	//寄存器当前的信号
	////输出至AGU
	assign agu_sbf_0_r = sbf_0_r[`E203_XLEN-1:0];
	assign agu_sbf_1_r = sbf_1_r[`E203_XLEN-1:0];
	////输出至MDV
	assign muldiv_sbf_0_r = sbf_0_r;
	assign muldiv_sbf_1_r = sbf_1_r;




//移位运算
	//操作数预处理
	assign shifter_in1 = {`E203_XLEN{op_shift}} &//把右移转化为左移
				  (
						(op_sra | op_srl) ? //当为右移操作时候，将操作数1逆置
						  {
		 shifter_op1[00],shifter_op1[01],shifter_op1[02],shifter_op1[03],
		 shifter_op1[04],shifter_op1[05],shifter_op1[06],shifter_op1[07],
		 shifter_op1[08],shifter_op1[09],shifter_op1[10],shifter_op1[11],
		 shifter_op1[12],shifter_op1[13],shifter_op1[14],shifter_op1[15],
		 shifter_op1[16],shifter_op1[17],shifter_op1[18],shifter_op1[19],
		 shifter_op1[20],shifter_op1[21],shifter_op1[22],shifter_op1[23],
		 shifter_op1[24],shifter_op1[25],shifter_op1[26],shifter_op1[27],
		 shifter_op1[28],shifter_op1[29],shifter_op1[30],shifter_op1[31]
							} : shifter_op1//若为左移则不变
				  );
	//门控信号的控制门
	wire op_shift = op_sra | op_sll | op_srl;//表明该运算为移位运算	
	//输入
	wire [`E203_XLEN-1:0] shifter_in1;//待移位的数据
	wire [5-1:0] shifter_in2;//表明移几位
	assign shifter_in2 = {5{op_shift}} & shifter_op2[4:0];//当op_shift==1时in2才有值，为移动的位数
	//输出
	wire [`E203_XLEN-1:0] sll_res = shifter_res;//逻辑左移结果
	wire [`E203_XLEN-1:0] srl_res =  
						  {
		 shifter_res[00],shifter_res[01],shifter_res[02],shifter_res[03],
		 shifter_res[04],shifter_res[05],shifter_res[06],shifter_res[07],
		 shifter_res[08],shifter_res[09],shifter_res[10],shifter_res[11],
		 shifter_res[12],shifter_res[13],shifter_res[14],shifter_res[15],
		 shifter_res[16],shifter_res[17],shifter_res[18],shifter_res[19],
		 shifter_res[20],shifter_res[21],shifter_res[22],shifter_res[23],
		 shifter_res[24],shifter_res[25],shifter_res[26],shifter_res[27],
		 shifter_res[28],shifter_res[29],shifter_res[30],shifter_res[31]
						  };//逻辑右移结果-只需将结果逆置
	wire [`E203_XLEN-1:0] eff_mask = (~(`E203_XLEN'b0)) >> shifter_in2;//算术右移的mask，将移动的位置全置为0，在补上符号位
	wire [`E203_XLEN-1:0] sra_res = //移动的位置全置为0    //补上符号位
											(srl_res & eff_mask) | ({32{shifter_op1[31]}} & (~eff_mask));//算术右移结果
	wire [`E203_XLEN-1:0] shifter_res;
	assign shifter_res = (shifter_in1 << shifter_in2);//最终结果



										
										
//加法器-处理加减和比较操作，这里alu宽度为35bit，因为乘除法需要35bit，因此其他运算需要扩展至35bit
	//操作数预处理-普通加减法和乘除法的操作数来源不同，并且普通加减法需要扩展到35bit
	wire op_unsigned = op_sltu | op_cmp_ltu | op_cmp_gtu | op_maxu | op_minu;//表明是否为无符号运算
	wire [`E203_ALU_ADDER_WIDTH-1:0] misc_adder_op1 =//非乘除的操作数1-扩展到35bit
			{{`E203_ALU_ADDER_WIDTH-`E203_XLEN{(~op_unsigned) & misc_op1[`E203_XLEN-1]}},misc_op1};
	wire [`E203_ALU_ADDER_WIDTH-1:0] misc_adder_op2 =//非乘除的操作数2-扩展到35bit
			{{`E203_ALU_ADDER_WIDTH-`E203_XLEN{(~op_unsigned) & misc_op2[`E203_XLEN-1]}},misc_op2};
	wire [`E203_ALU_ADDER_WIDTH-1:0] adder_op1 = //选择操作数是否来自乘除法器
			muldiv_req_alu ? muldiv_req_alu_op1 :
			misc_adder_op1;
	wire [`E203_ALU_ADDER_WIDTH-1:0] adder_op2 = //选择操作数是否来自乘除法器
			muldiv_req_alu ? muldiv_req_alu_op2 :
			misc_adder_op2

	//门控信号的控制门
	wire adder_add;
	wire adder_sub;
	assign adder_add =//乘除法器加法请求和普通加法 需要alu执行加法
			muldiv_req_alu ? muldiv_req_alu_add :
			op_add; 
	assign adder_sub =//乘除法器减法请求，普通减法请求，比较运算和maxmin运算 需要alu减法
			muldiv_req_alu ? muldiv_req_alu_sub :
						(           
						(op_sub) 
					 | (op_cmp_lt | op_cmp_gt | 
						 op_cmp_ltu | op_cmp_gtu |
						 op_max | op_maxu |
						 op_min | op_minu |
						 op_slt | op_sltu 
						));
	wire adder_addsub = adder_add | adder_sub;//表明准许输入信号-门控信号
	
	//输入
	wire [`E203_ALU_ADDER_WIDTH-1:0] adder_in1;//操作数1
	assign adder_in1 = {`E203_ALU_ADDER_WIDTH{adder_addsub}} & (adder_op1);
	wire [`E203_ALU_ADDER_WIDTH-1:0] adder_in2;//操作数2
	assign adder_in2 = {`E203_ALU_ADDER_WIDTH{adder_addsub}} & (adder_sub ? (~adder_op2) : adder_op2);
	wire adder_cin;//若为减法，将操作数2求补＋1的那个1
	assign adder_cin = adder_addsub & adder_sub;//当加法器执行减法操作时候，该变量置1，将减法转化为加法
	
	//输出
	wire [`E203_ALU_ADDER_WIDTH-1:0] adder_res;
	assign adder_res = adder_in1 + adder_in2 + adder_cin;//加减法统一为加法
	
//异或-用于处理异或和判断是否相等，还包括与和或，但是与或无需门控，直接运算输出
	//门控信号的控制门
	wire xorer_op =//当异或或者判断是否相等时候准许信号输入-门控信号
						op_xor
					 | (op_cmp_eq | op_cmp_ne); 
	//输入
	wire [`E203_XLEN-1:0] xorer_in1;//操作数1
	assign xorer_in1 = {`E203_XLEN{xorer_op}} & misc_op1;//`E203_XLEN{xorer_op}这个是逻辑门
	wire [`E203_XLEN-1:0] xorer_in2;//操作数2             //当该模块不开启的时候防止信号多次改变
	assign xorer_in2 = {`E203_XLEN{xorer_op}} & misc_op2;//增加功耗，门控信号，有效减少功耗

	//输出
	wire [`E203_XLEN-1:0] xorer_res = xorer_in1 ^ xorer_in2;//异或
	wire [`E203_XLEN-1:0] orer_res  = misc_op1 | misc_op2;//与
	wire [`E203_XLEN-1:0] ander_res = misc_op1 & misc_op2;//或
	
//B型比较-比大小来自加法器，是否相等来自异或
	//输入
	wire neq  = (|xorer_res);//来自异或-判是否相等
	wire op1_gt_op2  = (~adder_res[`E203_XLEN]);//来自加法器-比大小
	//输出
	wire cmp_res_ne  = (op_cmp_ne  & neq);//相等
	wire cmp_res_eq  = op_cmp_eq  & (~neq);//不相等
	wire cmp_res_lt  = op_cmp_lt  & adder_res[`E203_XLEN];//有符号-小于
	wire cmp_res_ltu = op_cmp_ltu & adder_res[`E203_XLEN];//无符号-小于
	wire cmp_res_gt  = op_cmp_gt  & op1_gt_op2;//有符号-大于
	wire cmp_res_gtu = op_cmp_gtu & op1_gt_op2;//无符号-大于
	assign cmp_res = cmp_res_eq//最终输出结果 
						  | cmp_res_ne 
						  | cmp_res_lt 
						  | cmp_res_gt  
						  | cmp_res_ltu 
						  | cmp_res_gtu; 
						  
//mvop2-lui指令-直接输出即可，op2就是立即数，在之前为了统一立即数已经扩展过了
wire [`E203_XLEN-1:0] mvop2_res = misc_op2;

//小于则置位
	//门控信号的控制门
	wire op_slttu = (op_slt | op_sltu);//表明是小于则置为操作
	//输入
	wire slttu_cmp_lt = op_slttu & adder_res[`E203_XLEN];//来自加法器
	//输出
	wire [`E203_XLEN-1:0] slttu_res = 
						slttu_cmp_lt ?
						`E203_XLEN'b1 : `E203_XLEN'b0;
						
//max，min指令
  //(op_max | op_maxu) (op_min | op_minu)门控信号的控制门
  //输入-来自加法器 op1_gt_op2出现在B型比较中，加法器结果的符号位
  wire maxmin_sel_op1 =  ((op_max | op_maxu) &   op1_gt_op2) //控制输出最大/小值
                      |  ((op_min | op_minu) & (~op1_gt_op2));
  //输出
  wire [`E203_XLEN-1:0] maxmin_res  = maxmin_sel_op1 ? misc_op1 : misc_op2; 

//最终结果 
wire [`E203_XLEN-1:0] alu_dpath_res = //格式 逻辑控制门&结果res
        ({`E203_XLEN{op_or       }} & orer_res )//逻辑控制门为长度与结果等长的
      | ({`E203_XLEN{op_and      }} & ander_res)//全0或1，用于门控结果输出
      | ({`E203_XLEN{op_xor      }} & xorer_res)
      | ({`E203_XLEN{op_addsub   }} & adder_res[`E203_XLEN-1:0])
      | ({`E203_XLEN{op_srl      }} & srl_res)
      | ({`E203_XLEN{op_sll      }} & sll_res)
      | ({`E203_XLEN{op_sra      }} & sra_res)
      | ({`E203_XLEN{op_mvop2    }} & mvop2_res)
      | ({`E203_XLEN{op_slttu    }} & slttu_res)
      | ({`E203_XLEN{op_max | op_maxu | op_min | op_minu}} & maxmin_res)
        ;
		  
//写回至各个alu控制模块
assign alu_req_alu_res     = alu_dpath_res[`E203_XLEN-1:0];
assign agu_req_alu_res     = alu_dpath_res[`E203_XLEN-1:0];
assign bjp_req_alu_add_res = alu_dpath_res[`E203_XLEN-1:0];//BJP地址
assign bjp_req_alu_cmp_res = cmp_res;		  
		  
//与alu的各种运算控制器的连接
localparam DPATH_MUX_WIDTH = ((`E203_XLEN*2)+21);//参数，控制信号宽度，用于门控
assign  {                                        //没有alu运算请求信号则不改变，节省功耗
     mux_op1
    ,mux_op2
    ,op_max  
    ,op_min  
    ,op_maxu 
    ,op_minu 
    ,op_add
    ,op_sub
    ,op_or
    ,op_xor
    ,op_and
    ,op_sll
    ,op_srl
    ,op_sra
    ,op_slt
    ,op_sltu
    ,op_mvop2
    ,op_cmp_eq 
    ,op_cmp_ne 
    ,op_cmp_lt 
    ,op_cmp_gt 
    ,op_cmp_ltu
    ,op_cmp_gtu
    }
    = 
        ({DPATH_MUX_WIDTH{alu_req_alu}} & {
             alu_req_alu_op1
            ,alu_req_alu_op2
            ,1'b0
            ,1'b0
            ,1'b0
            ,1'b0
            ,alu_req_alu_add
            ,alu_req_alu_sub
            ,alu_req_alu_or
            ,alu_req_alu_xor
            ,alu_req_alu_and
            ,alu_req_alu_sll
            ,alu_req_alu_srl
            ,alu_req_alu_sra
            ,alu_req_alu_slt
            ,alu_req_alu_sltu
            ,alu_req_alu_lui
            ,1'b0
            ,1'b0
            ,1'b0
            ,1'b0
            ,1'b0
            ,1'b0
        })
      | ({DPATH_MUX_WIDTH{bjp_req_alu}} & {
             bjp_req_alu_op1
            ,bjp_req_alu_op2
            ,1'b0
            ,1'b0
            ,1'b0
            ,1'b0
            ,bjp_req_alu_add
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
            ,bjp_req_alu_cmp_eq 
            ,bjp_req_alu_cmp_ne 
            ,bjp_req_alu_cmp_lt 
            ,bjp_req_alu_cmp_gt 
            ,bjp_req_alu_cmp_ltu
            ,bjp_req_alu_cmp_gtu

        })
      | ({DPATH_MUX_WIDTH{agu_req_alu}} & {
             agu_req_alu_op1
            ,agu_req_alu_op2
            ,agu_req_alu_max  
            ,agu_req_alu_min  
            ,agu_req_alu_maxu 
            ,agu_req_alu_minu 
            ,agu_req_alu_add
            ,1'b0
            ,agu_req_alu_or
            ,agu_req_alu_xor
            ,agu_req_alu_and
            ,1'b0
            ,1'b0
            ,1'b0
            ,1'b0
            ,1'b0
            ,agu_req_alu_swap
            ,1'b0
            ,1'b0
            ,1'b0
            ,1'b0
            ,1'b0
            ,1'b0
        })
        ;




endmodule                               