//oitf单元实质上是一个FIFO，因此熟悉FIFO即可轻松写出
//功能：由于数据冲突只发可能发生在长指令上，因此需要记录
//		  未写回的长指令的操作数，以检查数据冒险，并返回给
//	     派遣单元，以决策是否阻塞派遣
//实现：1. 实现FIFO，只要使用generate模块实例多个寄存器，
//			 并用读写指针表明读写位置，以及使用读写标志位以判断
//        FIFO的空满
//     2. 判断是否有数据冒险，主要使用派遣单元送来的数据和FIFO中的数据，
//			 只需检查当前指令所用到的寄存器索引和FIFO内是否有相同的寄存器
//			 索引，有相同的则存在冒险；因为要检查所有的FIFO项，因此检查电
//			 路应在generate模块中与寄存器一同实例化


`include "gen_defines.v"
module ex_oitf(
//来自派遣单元
  input  dis_ena,//派遣一个长指令
  input  disp_i_rs1en,//表明当前指令是否需要操作数1
  input  disp_i_rs2en,//表明当前指令是否需要操作数2
  input  disp_i_rs3en,//表明当前指令是否需要操作数3
  input  disp_i_rdwen,//表明当前指令是否需要写回操作数
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rs1idx,//当前指令操作数1
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rs2idx,//当前指令操作数2
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rs3idx,//当前指令操作数3
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rdidx,//当前指令写操作数
  input  [`E203_PC_SIZE    -1:0] disp_i_pc,//当前指令pc
//送至派遣单元
  output oitfrd_match_disprs1,//派遣指令操作数1与当前任一表现相同
  output oitfrd_match_disprs2,//派遣指令操作数2与当前任一表现相同
  output oitfrd_match_disprs3,//派遣指令操作数3与当前任一表现相同
  output oitfrd_match_disprd,//派遣指令写操作数与当前任一表现相同
  output oitf_empty,//oitf为空
  output dis_ready,//fifo不满还可接受长指令
  output [`E203_ITAG_WIDTH-1:0] dis_ptr,//写指针
//来自写回单元
  input  ret_ena,//表明写回一个长指令，移除一个oitf表项
//输出至写回单元
  output [`E203_ITAG_WIDTH-1:0] ret_ptr,//读指针	
  output [`E203_RFIDX_WIDTH-1:0] ret_rdidx,//写回操作数索引
  output ret_rdwen,//结果写回使能
  output [`E203_PC_SIZE-1:0] ret_pc,//该指令的pc
  
input  clk,
input  rst_n
);
//FIFO
////FIFO的读写指针以及状态
wire alc_ptr_ena = dis_ena;//dis_ena表示派遣长指令，因此写指针使能
wire [`E203_ITAG_WIDTH-1:0] alc_ptr_r;//写指针

wire ret_ptr_ena = ret_ena;//ret_ena表示写回长指令，因此读指针使能
wire [`E203_ITAG_WIDTH-1:0] ret_ptr_r;//读指针

wire oitf_full ;//表明fifo以满
generate
  if(`E203_OITF_DEPTH > 1) 
		begin: depth_gt1
      wire alc_ptr_flg_r;//写指针标志位
      wire alc_ptr_flg_nxt = ~alc_ptr_flg_r;
      wire alc_ptr_flg_ena = (alc_ptr_r == ($unsigned(`E203_OITF_DEPTH-1))) & alc_ptr_ena;//表明是否以索引至边界，是则从0计数
      //当写指针指到边界时才会使得读写指针位置关系改变，因此该寄存器的使能信号使能当指针指到边界
      sirv_gnrl_dfflr #(1) alc_ptr_flg_dfflrs(alc_ptr_flg_ena, alc_ptr_flg_nxt, alc_ptr_flg_r, clk, rst_n);
      
      wire [`E203_ITAG_WIDTH-1:0] alc_ptr_nxt; 
      //若越界则置为0
      assign alc_ptr_nxt = alc_ptr_flg_ena ? `E203_ITAG_WIDTH'b0 : (alc_ptr_r + 1'b1);
      //同步写指针的时钟
      sirv_gnrl_dfflr #(`E203_ITAG_WIDTH) alc_ptr_dfflrs(alc_ptr_ena, alc_ptr_nxt, alc_ptr_r, clk, rst_n);
      
      
      wire ret_ptr_flg_r;//读指针标志位
      wire ret_ptr_flg_nxt = ~ret_ptr_flg_r;
      wire ret_ptr_flg_ena = (ret_ptr_r == ($unsigned(`E203_OITF_DEPTH-1))) & ret_ptr_ena;
      //当写指针指到边界时才会使得读写指针位置关系改变，因此该寄存器的使能信号使能当指针指到边界
      sirv_gnrl_dfflr #(1) ret_ptr_flg_dfflrs(ret_ptr_flg_ena, ret_ptr_flg_nxt, ret_ptr_flg_r, clk, rst_n);
      
      wire [`E203_ITAG_WIDTH-1:0] ret_ptr_nxt; 
      //做越界则置为0
      assign ret_ptr_nxt = ret_ptr_flg_ena ? `E203_ITAG_WIDTH'b0 : (ret_ptr_r + 1'b1);
		//同步读指针的时钟
      sirv_gnrl_dfflr #(`E203_ITAG_WIDTH) ret_ptr_dfflrs(ret_ptr_ena, ret_ptr_nxt, ret_ptr_r, clk, rst_n);

      assign oitf_empty = (ret_ptr_r == alc_ptr_r) &   (ret_ptr_flg_r == alc_ptr_flg_r);//空
      assign oitf_full  = (ret_ptr_r == alc_ptr_r) & (~(ret_ptr_flg_r == alc_ptr_flg_r));//满
		end
endgenerate

////生成fifo 
    //各表项信号
     //后面会用generate循环实例化寄存器用于实现fifo
	  //因此所有信号均是多位，且数量与fifo大小一致
	wire [`E203_OITF_DEPTH-1:0] vld_set;//寄存器标配信号
	wire [`E203_OITF_DEPTH-1:0] vld_clr;
	wire [`E203_OITF_DEPTH-1:0] vld_ena;
	wire [`E203_OITF_DEPTH-1:0] vld_nxt;
wire [`E203_OITF_DEPTH-1:0] vld_r;//表示是否存放了有效指令的指示信号
wire [`E203_OITF_DEPTH-1:0] rdwen_r;//是否写回寄存器
wire [`E203_RFIDX_WIDTH-1:0] rdidx_r[`E203_OITF_DEPTH-1:0];//结果写回寄存器下标
wire [`E203_PC_SIZE-1:0] pc_r[`E203_OITF_DEPTH-1:0];//当前表项指令的pc--用于长指令在写回级的异常
	wire [`E203_OITF_DEPTH-1:0] rd_match_rs1idx;//分别对应四个写回派遣单元的信号
	wire [`E203_OITF_DEPTH-1:0] rd_match_rs2idx;
	wire [`E203_OITF_DEPTH-1:0] rd_match_rs3idx;
	wire [`E203_OITF_DEPTH-1:0] rd_match_rdidx;

	  //循环实例化表项，组成fifo
genvar i;
  generate
      for (i=0; i<`E203_OITF_DEPTH; i=i+1) begin:oitf_entries//{
  
        assign vld_set[i] = alc_ptr_ena & (alc_ptr_r == i);//分配表项//写指针与该表项编号一致且需要写表项时则分配
        assign vld_clr[i] = ret_ptr_ena & (ret_ptr_r == i);//移除表项//读指针与该表项编号一致且需要移除一表项
        assign vld_ena[i] = vld_set[i] |   vld_clr[i];//使能，当分配或移除发生时则可对寄存器操作
        assign vld_nxt[i] = vld_set[i] | (~vld_clr[i]);
  
        sirv_gnrl_dfflr #(1) vld_dfflrs(vld_ena[i], vld_nxt[i], vld_r[i], clk, rst_n);//门控时钟，同步rd_match四个信号
		  //表项，移除时候不用清除，下次直接覆盖，以节省能耗
        sirv_gnrl_dffl #(`E203_RFIDX_WIDTH) rdidx_dfflrs(vld_set[i], disp_i_rdidx, rdidx_r[i], clk);//表项中指令写回寄存器索引
        sirv_gnrl_dffl #(`E203_PC_SIZE    ) pc_dfflrs   (vld_set[i], disp_i_pc   , pc_r[i]   , clk);//表项中指令的pc
        sirv_gnrl_dffl #(1)                 rdwen_dfflrs(vld_set[i], disp_i_rdwen, rdwen_r[i], clk);//表项中指令是否写回

        assign rd_match_rs1idx[i] = vld_r[i] & rdwen_r[i] & disp_i_rs1en & (rdidx_r[i] == disp_i_rs1idx);
        assign rd_match_rs2idx[i] = vld_r[i] & rdwen_r[i] & disp_i_rs2en & (rdidx_r[i] == disp_i_rs2idx);
        assign rd_match_rs3idx[i] = vld_r[i] & rdwen_r[i] & disp_i_rs3en & (rdidx_r[i] == disp_i_rs3idx);
        assign rd_match_rdidx [i] = vld_r[i] & rdwen_r[i] & disp_i_rdwen & (rdidx_r[i] == disp_i_rdidx );
  
      end
endgenerate







//写回派遣单元
assign dis_ready = (~oitf_full);//若fifo不满则还可接受长指令
   //在module中以说明
assign oitfrd_match_disprs1 = |rd_match_rs1idx;//RAW
assign oitfrd_match_disprs2 = |rd_match_rs2idx;//RAW
assign oitfrd_match_disprs3 = |rd_match_rs3idx;//RAW
assign oitfrd_match_disprd  = |rd_match_rdidx ;//WAW
assign dis_ptr = alc_ptr_r;


//送至写回单元
assign ret_rdidx = rdidx_r[ret_ptr];//在module中以说明
assign ret_pc    = pc_r [ret_ptr];
assign ret_rdwen = rdwen_r[ret_ptr];
assign ret_rdfpu = rdfpu_r[ret_ptr];
assign ret_ptr = ret_ptr_r; 

  
  
  
endmodule


