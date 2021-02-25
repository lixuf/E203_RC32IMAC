//该模块为长指令写回仲裁模块，比较不好想的是握手部分，其余很简单
//功能：1. 如果无异常，则需按照fifo的顺序把数据写回
//     2. 如果有异常，则将异常信息写入commit
//实现：1. 将输入输出模块的各个数据分块然后配以逻辑控制连接起来
//     2. 善用门控信号以节省功耗和控制不定态，当无需此通路时用一信号且上，使得整个通路均为0，消除不定态
//     3. 握手信号是输入和输出模块互锁

`include "gen_defines.v"
module ex_longpwbck(
  //与LSU
  input  lsu_wbck_i_valid,
  output lsu_wbck_i_ready, 
  input  [`E203_XLEN-1:0] lsu_wbck_i_wdat,//待写回的数据
  input  [`E203_ITAG_WIDTH -1:0] lsu_wbck_i_itag,//当前指令的itag，即在fifo中的位置
	  //错误信息
	  input  lsu_wbck_i_err , //表示有写回异常或错误
	  input  lsu_cmt_i_buserr ,//表示访存有异常或错误
	  input  [`E203_ADDR_SIZE -1:0] lsu_cmt_i_badaddr,
	  input  lsu_cmt_i_ld, 
	  input  lsu_cmt_i_st, 

  //与最终写回单元
  output longp_wbck_o_valid,
  input  longp_wbck_o_ready, 
  output [`E203_FLEN-1:0] longp_wbck_o_wdat,
  output [5-1:0] longp_wbck_o_flags,
  output [`E203_RFIDX_WIDTH -1:0] longp_wbck_o_rdidx,
  output longp_wbck_o_rdfpu,
  
  //与commit
  output  longp_excp_o_valid,
  input   longp_excp_o_ready,
  output  longp_excp_o_insterr,
  output  longp_excp_o_ld,
  output  longp_excp_o_st,
  output  longp_excp_o_buserr , 
  output [`E203_ADDR_SIZE-1:0] longp_excp_o_badaddr,
  output [`E203_PC_SIZE -1:0] longp_excp_o_pc,
 
  //与oitf
  input  oitf_empty,
  input  [`E203_ITAG_WIDTH -1:0] oitf_ret_ptr,
  input  [`E203_RFIDX_WIDTH-1:0] oitf_ret_rdidx,
  input  [`E203_PC_SIZE-1:0] oitf_ret_pc,
  input  oitf_ret_rdwen,   
  input  oitf_ret_rdfpu,   
  output oitf_ret_ena,
  
  input  clk,
  input  rst_n
);
//握手，为输入与输出模块的互锁
   //lsu_wbck_i_valid为来自lsu的读写请求，本模块接收后接收数据并判断是否达到写回条件
	
	wire wbck_i_valid;//当达到写回条件后，该变量与lsu_wbck_i_valid同值
	assign wbck_i_valid = ({1{wbck_sel_lsu}} & lsu_wbck_i_valid);
	
	//当wbck_i_valid==1时，向相应的输出模块输出读写请求信号，传输数据
	assign longp_wbck_o_valid = need_wbck & wbck_i_valid & (need_excp ? longp_excp_o_ready : 1'b1);
	assign longp_excp_o_valid = need_excp & wbck_i_valid & (need_wbck ? longp_wbck_o_ready : 1'b1);

	//longp_excp_o_ready 这两个信号表示输出模块接收完数据
	//longp_wbck_o_ready
	
	wire wbck_i_ready;//与longp_xxxx_o_ready同值，表示向输出模块传输完毕，需要反馈至输入模块
	assign wbck_i_ready = //将串行的两个mux改为并行的两个mux，提速
       (need_wbck ? longp_wbck_o_ready : 1'b1)//与最终写回仲裁单元通讯
     & (need_excp ? longp_excp_o_ready : 1'b1);//与commit通讯
	  
	  
	assign lsu_wbck_i_ready = wbck_ready4lsu & wbck_i_ready;//写回到输入模块，表明写回数据完毕

//接收来自lsu的数据
///数据
	wire [`E203_FLEN-1:0] wbck_i_wdat;//待写回的数据
	wire [`E203_FLEN-1:0] lsu_wbck_i_wdat_exd = lsu_wbck_i_wdat;
	assign wbck_i_wdat  = ({`E203_FLEN{wbck_sel_lsu}} & lsu_wbck_i_wdat_exd );


	wire wbck_i_err ;//错误码                      
	assign wbck_i_err   = wbck_sel_lsu & lsu_wbck_i_err 

	wire [`E203_PC_SIZE-1:0] wbck_i_pc;//该指令的pc                         ;
	assign wbck_i_pc    = oitf_ret_pc;

	wire [`E203_RFIDX_WIDTH-1:0] wbck_i_rdidx;//带写入寄存器的索引
	assign wbck_i_rdidx = oitf_ret_rdidx;

	wire wbck_i_rdwen;//写回寄存器使能
	assign wbck_i_rdwen = oitf_ret_rdwen;

	wire wbck_i_rdfpu;//浮点运算无需理会
	assign wbck_i_rdfpu = oitf_ret_rdfpu;

	wire [5-1:0] wbck_i_flags;//不支持此功能，无需理会
	assign wbck_i_flags  = 5'b0;
	
	assign {//各种错误信息
         longp_excp_o_insterr
        ,longp_excp_o_ld   
        ,longp_excp_o_st  
        ,longp_excp_o_buserr
        ,longp_excp_o_badaddr } = 
             ({`E203_ADDR_SIZE+4{wbck_sel_lsu}} & 
              {
                1'b0,
                lsu_cmt_i_ld,//表示访存错误为load指令
                lsu_cmt_i_st,//表示访存错误为store指令
                lsu_cmt_i_buserr,//访存错误异常指示
                lsu_cmt_i_badaddr//访存错误的地址
              }) 
              ;
//写入最终写回模块
wire need_wbck = wbck_i_rdwen & (~wbck_i_err);//无错误码且写回寄存器使则表示需要写回
assign longp_wbck_o_wdat  = wbck_i_wdat ;
assign longp_wbck_o_flags = wbck_i_flags ;
assign longp_wbck_o_rdfpu = wbck_i_rdfpu ;
assign longp_wbck_o_rdidx = wbck_i_rdidx;

//写入交付模块，异常接口
wire need_excp = wbck_i_err;//表示产生异常，需要与commit通讯
assign longp_excp_o_pc    = wbck_i_pc;
  //其他信号均在来自lsu的数据中声名 longp_excp_o_xxx

  
//长指令写回仲裁--总是以队头优先，即按顺序最先进入队列的优先写回，保证顺序写回以简化逻辑
  //oitf_ret_ptr 是oitf的读指针，指向队列的头
  //lsu_wbck_i_itag 是该指令的itag，即指向该指令在fifo中的表项
  //lsu_wbck_i_itag == oitf_ret_ptr是为了确保指令被顺序执行
  //oitf_empty表明oitf为空
wire wbck_ready4lsu = (lsu_wbck_i_itag == oitf_ret_ptr) & (~oitf_empty);//当oitf中即将被读出的指令为该指令则可写回
wire wbck_sel_lsu = lsu_wbck_i_valid & wbck_ready4lsu;//表明准备好，可执行写回。且该信号作为门控信号的门控，控制着以上诸多信号
                                                      //的更新，使得信号仅在 wbck_sel_lsu==1时更新，以减少能耗，
																		//型似 wbck_sel_lsu & 的均属于此。

																		
//长指令写回成功后需要在oitf中删除该表项
assign oitf_ret_ena = wbck_i_valid & wbck_i_ready;//表明写回成功，需要删掉该表项



endmodule    