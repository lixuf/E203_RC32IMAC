//该模块为csr读写控制模块，用于执行csr的一系列指令，是纯组合逻辑，
//因此可以直接将信号传给csr，不需要握手，握手信号仅仅包括alu总控和csr
//的握手，在该模块内中转。
//功能：1.实现CSRRW,CSRRS,CSRRC,CSRRWI,CSRRSI,CSRRCI
//     2. 实现协处理器的扩展(本cpu未作扩展，因此不用实现，若需协处理器可在此处扩展)
//实现：1.熟悉各个指令的数据流动
//     2. 从数据总写取得数据，并按照指令要求送达	    
`inlcude "gen_defines.v"

module ex_alu_csrctrl(
//与alu总控传输
  //握手信号
  input  csr_i_valid,//来自alu总控的读写请求信号
  output csr_i_ready,//输出至alu总控的读写准许信号 
  //数据
  input  [`E203_XLEN-1:0] csr_i_rs1,//操作数1
  input  [`E203_DECINFO_CSR_WIDTH-1:0] csr_i_info,//信息总线
  input  csr_i_rdwen,//表示是否写回

//与csr传输
  //输出
  output csr_ena,//csr使能
  output csr_wr_en,//读使能
  output csr_rd_en,//写使能
  output [12-1:0] csr_idx,//待操作的寄存器索引
  output [`E203_XLEN-1:0] wbck_csr_dat,//写操作需写入的数据
  //输入
  input  csr_access_ilgl,//表示存取错误或异常
  input  [`E203_XLEN-1:0] read_csr_dat,//读操作需读出的数据
  
//与回写单元传输
  //握手
  output csr_o_valid,//输出至写回单元的读写请求信号
  input  csr_o_ready,//来自写回单元的读写准许信号
  //数据
  output [`E203_XLEN-1:0] csr_o_wbck_wdat,//待写回的数据
  output csr_o_wbck_err,//错误码
  
  input  clk,
  input  rst_n
  );
  
  assign sel_eai      = 1'b0;//协处理器选择信号，因无扩展协处理器，故为0
  
  
  //信息总线
    //指令，详见用户手册附录A
	 wire        csrrw  = csr_i_info[`E203_DECINFO_CSR_CSRRW ];
	 wire        csrrs  = csr_i_info[`E203_DECINFO_CSR_CSRRS ];
	 wire        csrrc  = csr_i_info[`E203_DECINFO_CSR_CSRRC ];
	 //操作数
	 wire        rs1imm = csr_i_info[`E203_DECINFO_CSR_RS1IMM];//操作数是否为立即数
	 wire        rs1is0 = csr_i_info[`E203_DECINFO_CSR_RS1IS0];//操作数是否为0号寄存器
	 wire [4:0]  zimm   = csr_i_info[`E203_DECINFO_CSR_ZIMMM ];//立即数
	 wire [11:0] csridx = csr_i_info[`E203_DECINFO_CSR_CSRIDX];//csr寄存器索引
	 
  //与写回单元传输
    //握手信号为alu总控和写回单元直接握手
    assign csr_o_valid      = csr_i_valid;
    assign csr_i_ready      = csr_o_ready;
	 //数据，来自csr的输入
    assign csr_o_wbck_err   = csr_access_ilgl;//错误码
    assign csr_o_wbck_wdat  = read_csr_dat;//将从csr中读取的数据写回
  
	 
  //与csr传输
    //输出
	 assign csr_idx = csridx;
    assign csr_rd_en = csr_i_valid & 
							 (
								(csrrw ? csr_i_rdwen : 1'b0) 
								| csrrs | csrrc 
    assign csr_wr_en = csr_i_valid & (
               | ((csrrs | csrrc) & (~rs1is0))
            );                                                                           
                                                                                         
    assign csr_ena = csr_o_valid & csr_o_ready & (~sel_eai);
	 wire [`E203_XLEN-1:0] csr_op1 = rs1imm ? {27'b0,zimm} : csr_i_rs1;
	 assign wbck_csr_dat = 
              ({`E203_XLEN{csrrw}} & csr_op1)
            | ({`E203_XLEN{csrrs}} & (  csr_op1  | read_csr_dat))
            | ({`E203_XLEN{csrrc}} & ((~csr_op1) & read_csr_dat));

endmodule
	 