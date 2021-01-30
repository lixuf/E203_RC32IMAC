`include "gen_defines.v"
//该模块为寄存器堆，较为容易实现，无难点
//主要使用genvar-generate语句循环实例化32个寄存器
//主要0号寄存器用于为0，和1号寄存器为了方便jalr从而旁路回去
//作者手册中推荐使用锁存器实现，可以有效减少面积和功耗，这里为了简化使用DFF
module ex_regfile(
  input  [`E203_RFIDX_WIDTH-1:0] read_src1_idx,//寄存器索引1_读
  input  [`E203_RFIDX_WIDTH-1:0] read_src2_idx,//寄存器索引2_读
  output [`E203_XLEN-1:0] read_src1_dat,//寄存器索引1读出的数据
  output [`E203_XLEN-1:0] read_src2_dat,//寄存器索引2读出的数据
  
  input  wbck_dest_wen,//写使能
  input  [`E203_RFIDX_WIDTH-1:0] wbck_dest_idx,//寄存器索引_写
  input  [`E203_XLEN-1:0] wbck_dest_dat,//要写入的数据
 
  output [`E203_XLEN-1:0] x1_r,//1号寄存器的输出端口，用于jalr的提前送回  
  
  input  test_mode,//??
  input  clk,
  input  rst_n
  );
 
//产生寄存器堆
genvar i;//generate的循环变量
generate//循环实例化以下模块，用于产生32个寄存器
	for(i=0;i<`E203_RFREG_NUM; i=i+1) 
	begin : regfile
		if(i==0)//0号寄存器用于为1
		begin : rf0
			assign rf_wen[i] = 1`b0;//不可写
			assign rf_r[i]=`E203_XLEN'b0;//输出数据为0
		end
		else 
		begin: rfno0
			assign rf_wen[i]=wbck_dest_wen & (wbck_dest_idx == i) ;//写使能信号
			sirv_gnrl_dffl #(`E203_XLEN) rf_dffl (rf_wen[i], wbck_dest_dat, rf_r[i], clk);
		end
	end
endgenerate

//寄存器堆接口
wire [`E203_XLEN-1:0] rf_r [`E203_RFREG_NUM-1:0];//二维数组，存放寄存器堆
wire [`E203_RFREG_NUM-1:0] rf_wen;//控制指定寄存器的写入

//输出
assign read_src1_dat = rf_r[read_src1_idx];//读
assign read_src2_dat = rf_r[read_src2_idx];//读
assign x1_r = rf_r[1];//1号寄存器旁路

endmodule
