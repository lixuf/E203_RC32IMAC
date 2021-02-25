`include "gen_defines.v"
module ex_lsu_ctrl(

);





//AGU和EAI的ICB总线经过汇合器汇合---本芯片未添加EAI，故eai_mem_holdup一直为0
///无浮点数和协处理器，故汇合器的浮点运算单元和协处理器的输入均为0
wire [USR_W-1:0] eai_icb_cmd_usr = {USR_W-1{1'b0}};
wire [USR_W-1:0] fpu_icb_cmd_usr = {USR_W-1{1'b0}};
wire [USR_W-1:0] fpu_icb_rsp_usr;
wire [USR_W-1:0] eai_icb_rsp_usr;
///汇合器参数
localparam LSU_ARBT_I_NUM   = 2;//输入数量
localparam LSU_ARBT_I_PTR_W = 1;//单次输出的数量
localparam USR_W = (`E203_ITAG_WIDTH+6+`E203_ADDR_SIZE);//输入数据的宽度
localparam USR_PACK_EXCL = 0;//指明cmd通道的异常位在第0位
///AGU到LSU
	///cmd通道
		//握手
		wire agu_icb_cmd_valid_pos;//来自AGU的读写请求信号
		assign agu_icb_cmd_valid_pos = (~eai_mem_holdup) & agu_icb_cmd_valid;
		wire agu_icb_cmd_ready_pos;//写回AGU的读写
		assign agu_icb_cmd_ready     = (~eai_mem_holdup) & agu_icb_cmd_ready_pos;
		//数据
		wire [USR_W-1:0] agu_icb_cmd_usr =//AGU的CMD通道的全部数据--输入到汇合器的输入端
      {
         agu_icb_cmd_back2agu  
        ,agu_icb_cmd_usign
        ,agu_icb_cmd_read
        ,agu_icb_cmd_size
        ,agu_icb_cmd_itag 
        ,agu_icb_cmd_addr 
        ,agu_icb_cmd_excl 
      };
	///rsp通道
	   //握手
		wire pre_agu_icb_rsp_valid;
      wire pre_agu_icb_rsp_ready;
		//数据
		wire pre_agu_icb_rsp_err  ;
      wire pre_agu_icb_rsp_excl_ok;
      wire [`E203_XLEN-1:0] pre_agu_icb_rsp_rdata;
		wire pre_agu_icb_rsp_back2agu; 
      wire pre_agu_icb_rsp_usign;
      wire pre_agu_icb_rsp_read;
      wire pre_agu_icb_rsp_excl;
      wire [2-1:0] pre_agu_icb_rsp_size;
		wire [`E203_ITAG_WIDTH -1:0] pre_agu_icb_rsp_itag;
		wire [`E203_ADDR_SIZE-1:0] pre_agu_icb_rsp_addr;
		wire [USR_W-1:0] pre_agu_icb_rsp_usr;
		assign 
      {
         pre_agu_icb_rsp_back2agu  
        ,pre_agu_icb_rsp_usign
        ,pre_agu_icb_rsp_read
        ,pre_agu_icb_rsp_size
        ,pre_agu_icb_rsp_itag 
        ,pre_agu_icb_rsp_addr
        ,pre_agu_icb_rsp_excl 
      } = pre_agu_icb_rsp_usr;
		
///汇合器的输入
	//CMD通道
	wire [LSU_ARBT_I_NUM*1-1:0] arbt_bus_icb_cmd_valid;
	wire [LSU_ARBT_I_NUM*1-1:0] arbt_bus_icb_cmd_ready;
	wire [LSU_ARBT_I_NUM*`E203_ADDR_SIZE-1:0] arbt_bus_icb_cmd_addr;
	wire [LSU_ARBT_I_NUM*1-1:0] arbt_bus_icb_cmd_read;
	wire [LSU_ARBT_I_NUM*`E203_XLEN-1:0] arbt_bus_icb_cmd_wdata;
	wire [LSU_ARBT_I_NUM*`E203_XLEN/8-1:0] arbt_bus_icb_cmd_wmask;
	wire [LSU_ARBT_I_NUM*1-1:0] arbt_bus_icb_cmd_lock;
	wire [LSU_ARBT_I_NUM*1-1:0] arbt_bus_icb_cmd_excl;
	wire [LSU_ARBT_I_NUM*2-1:0] arbt_bus_icb_cmd_size;
	wire [LSU_ARBT_I_NUM*USR_W-1:0] arbt_bus_icb_cmd_usr;
	wire [LSU_ARBT_I_NUM*2-1:0] arbt_bus_icb_cmd_burst;
	wire [LSU_ARBT_I_NUM*2-1:0] arbt_bus_icb_cmd_beat;	
	    ////用在后面////
	wire [LSU_ARBT_I_NUM*1-1:0] arbt_bus_icb_cmd_valid_raw;
   assign arbt_bus_icb_cmd_valid_raw =
      // The EAI take higher priority
                           {
                             agu_icb_cmd_valid
                           , eai_icb_cmd_valid
                           } ;
					/////				////
	assign arbt_bus_icb_cmd_valid =
      // The EAI take higher priority
                           {
                             agu_icb_cmd_valid_pos
                           , eai_icb_cmd_valid
                           } ;

   assign arbt_bus_icb_cmd_addr =
                           {
                             agu_icb_cmd_addr
                           , eai_icb_cmd_addr
                           } ;

   assign arbt_bus_icb_cmd_read =
                           {
                             agu_icb_cmd_read
                           , eai_icb_cmd_read
                           } ;

   assign arbt_bus_icb_cmd_wdata =
                           {
                             agu_icb_cmd_wdata
                           , eai_icb_cmd_wdata
                           } ;

   assign arbt_bus_icb_cmd_wmask =
                           {
                             agu_icb_cmd_wmask
                           , eai_icb_cmd_wmask
                           } ;
                         
   assign arbt_bus_icb_cmd_lock =
                           {
                             agu_icb_cmd_lock
                           , eai_icb_cmd_lock
                           } ;

   assign arbt_bus_icb_cmd_burst =
                           {
                             2'b0
                           , 2'b0
                           } ;

   assign arbt_bus_icb_cmd_beat =
                           {
                             1'b0
                           , 1'b0
                           } ;

   assign arbt_bus_icb_cmd_excl =
                           {
                             agu_icb_cmd_excl
                           , eai_icb_cmd_excl
                           } ;
                           
   assign arbt_bus_icb_cmd_size =
                           {
                             agu_icb_cmd_size
                           , eai_icb_cmd_size
                           } ;

   assign arbt_bus_icb_cmd_usr =
                           {
                             agu_icb_cmd_usr
                           , eai_icb_cmd_usr
                           } ;

   assign                   {
                             agu_icb_cmd_ready_pos
                           , eai_icb_cmd_ready
                           } = arbt_bus_icb_cmd_ready;
	//RSP通道
   wire [LSU_ARBT_I_NUM*1-1:0] arbt_bus_icb_rsp_valid;
   wire [LSU_ARBT_I_NUM*1-1:0] arbt_bus_icb_rsp_ready;
   wire [LSU_ARBT_I_NUM*1-1:0] arbt_bus_icb_rsp_err;
   wire [LSU_ARBT_I_NUM*1-1:0] arbt_bus_icb_rsp_excl_ok;
   wire [LSU_ARBT_I_NUM*`E203_XLEN-1:0] arbt_bus_icb_rsp_rdata;
   wire [LSU_ARBT_I_NUM*USR_W-1:0] arbt_bus_icb_rsp_usr;
   assign                   {
                             pre_agu_icb_rsp_valid
                           , eai_icb_rsp_valid
                           } = arbt_bus_icb_rsp_valid;

   assign                   {
                             pre_agu_icb_rsp_err
                           , eai_icb_rsp_err
                           } = arbt_bus_icb_rsp_err;

   assign                   {
                             pre_agu_icb_rsp_excl_ok
                           , eai_icb_rsp_excl_ok
                           } = arbt_bus_icb_rsp_excl_ok;


   assign                   {
                             pre_agu_icb_rsp_rdata
                           , eai_icb_rsp_rdata
                           } = arbt_bus_icb_rsp_rdata;

   assign                   {
                             pre_agu_icb_rsp_usr
                           , eai_icb_rsp_usr
                           } = arbt_bus_icb_rsp_usr;

   assign arbt_bus_icb_rsp_ready = {
                             pre_agu_icb_rsp_ready
                           , eai_icb_rsp_ready
                           };

///汇合器本体定义
sirv_gnrl_icb_arbt # (
.ARBT_SCHEME (0),// Priority based
.ALLOW_0CYCL_RSP (0),// Dont allow the 0 cycle response because in BIU we always have CMD_DP larger than 0
                       //   when the response come back from the external bus, it is at least 1 cycle later
                       //   for ITCM and DTCM, Dcache, .etc, definitely they cannot reponse as 0 cycle
.FIFO_OUTS_NUM   (`E203_LSU_OUTS_NUM),
.FIFO_CUT_READY  (0),
.ARBT_NUM   (LSU_ARBT_I_NUM),
.ARBT_PTR_W (LSU_ARBT_I_PTR_W),
.USR_W      (USR_W),
.AW         (`E203_ADDR_SIZE),
.DW         (`E203_XLEN) 
) u_lsu_icb_arbt(
.o_icb_cmd_valid        (arbt_icb_cmd_valid )     ,
.o_icb_cmd_ready        (arbt_icb_cmd_ready )     ,
.o_icb_cmd_read         (arbt_icb_cmd_read )      ,
.o_icb_cmd_addr         (arbt_icb_cmd_addr )      ,
.o_icb_cmd_wdata        (arbt_icb_cmd_wdata )     ,
.o_icb_cmd_wmask        (arbt_icb_cmd_wmask)      ,
.o_icb_cmd_burst        (arbt_icb_cmd_burst)     ,
.o_icb_cmd_beat         (arbt_icb_cmd_beat )     ,
.o_icb_cmd_excl         (arbt_icb_cmd_excl )     ,
.o_icb_cmd_lock         (arbt_icb_cmd_lock )     ,
.o_icb_cmd_size         (arbt_icb_cmd_size )     ,
.o_icb_cmd_usr          (arbt_icb_cmd_usr  )     ,

.o_icb_rsp_valid        (arbt_icb_rsp_valid )     ,
.o_icb_rsp_ready        (arbt_icb_rsp_ready )     ,
.o_icb_rsp_err          (arbt_icb_rsp_err)        ,
.o_icb_rsp_excl_ok      (arbt_icb_rsp_excl_ok)    ,
.o_icb_rsp_rdata        (arbt_icb_rsp_rdata )     ,
.o_icb_rsp_usr          (arbt_icb_rsp_usr   )     ,
                               
.i_bus_icb_cmd_ready    (arbt_bus_icb_cmd_ready ) ,
.i_bus_icb_cmd_valid    (arbt_bus_icb_cmd_valid ) ,
.i_bus_icb_cmd_read     (arbt_bus_icb_cmd_read )  ,
.i_bus_icb_cmd_addr     (arbt_bus_icb_cmd_addr )  ,
.i_bus_icb_cmd_wdata    (arbt_bus_icb_cmd_wdata ) ,
.i_bus_icb_cmd_wmask    (arbt_bus_icb_cmd_wmask)  ,
.i_bus_icb_cmd_burst    (arbt_bus_icb_cmd_burst)  ,
.i_bus_icb_cmd_beat     (arbt_bus_icb_cmd_beat )  ,
.i_bus_icb_cmd_excl     (arbt_bus_icb_cmd_excl )  ,
.i_bus_icb_cmd_lock     (arbt_bus_icb_cmd_lock )  ,
.i_bus_icb_cmd_size     (arbt_bus_icb_cmd_size )  ,
.i_bus_icb_cmd_usr      (arbt_bus_icb_cmd_usr  )  ,
                                
.i_bus_icb_rsp_valid    (arbt_bus_icb_rsp_valid ) ,
.i_bus_icb_rsp_ready    (arbt_bus_icb_rsp_ready ) ,
.i_bus_icb_rsp_err      (arbt_bus_icb_rsp_err)    ,
.i_bus_icb_rsp_excl_ok  (arbt_bus_icb_rsp_excl_ok),
.i_bus_icb_rsp_rdata    (arbt_bus_icb_rsp_rdata ) ,
.i_bus_icb_rsp_usr      (arbt_bus_icb_rsp_usr) ,
                             
.clk                    (clk  ),
.rst_n                  (rst_n)
);
///汇合器的输出/输入--cmd是输出汇合器进行之后的运算，rsp是输入汇合器分发给agu/fpu/eai
  ///cmd
	//握手
	wire arbt_icb_cmd_valid;
	wire arbt_icb_cmd_ready;
	//数据
	wire [`E203_ADDR_SIZE-1:0] arbt_icb_cmd_addr;
   wire arbt_icb_cmd_read;
   wire [`E203_XLEN-1:0] arbt_icb_cmd_wdata;
   wire [`E203_XLEN/8-1:0] arbt_icb_cmd_wmask;
   wire arbt_icb_cmd_lock;
   wire arbt_icb_cmd_excl;
   wire [1:0] arbt_icb_cmd_size;
   wire [1:0] arbt_icb_cmd_burst;
   wire [1:0] arbt_icb_cmd_beat;
   wire [USR_W-1:0] arbt_icb_cmd_usr;
  ///rsp
   //握手
	wire arbt_icb_rsp_valid;
   wire arbt_icb_rsp_ready;
   //数据
	wire arbt_icb_rsp_err;
   wire arbt_icb_rsp_excl_ok;
   wire [`E203_XLEN-1:0] arbt_icb_rsp_rdata;
   wire [USR_W-1:0] arbt_icb_rsp_usr;
///汇合器中存放输入输出间的分发信息的fifo，当cmd握手就将分发信息压入fifo，当rsp握手则在fifo中提出一个分发信息
///fifo这种数据结构可以保证按顺序写回请求信号所对应的反馈信号，该fifo默认深度为1，表示可以有一个滞外指令
   //分发信息--除了以下的5个还有分发器输入的数据--即FIFO的入队信息
	///分发信息长度
	localparam SPLT_FIFO_W = (USR_W+5);
	///按照地址判断访问哪个存储器       //只需判断地址范围以上的位是否与地址范围的高位一致？？
	wire arbt_icb_cmd_itcm = (arbt_icb_cmd_addr[`E203_ITCM_BASE_REGION] ==  itcm_region_indic[`E203_ITCM_BASE_REGION]);
	wire arbt_icb_cmd_dtcm = (arbt_icb_cmd_addr[`E203_DTCM_BASE_REGION] ==  dtcm_region_indic[`E203_DTCM_BASE_REGION]);
	wire arbt_icb_cmd_dcache = 1'b0;//无cache，故一直为0                                             //若非I/DTCM则需要BIU的IO接口去外存取
	wire arbt_icb_cmd_biu    = (~arbt_icb_cmd_itcm) & (~arbt_icb_cmd_dtcm) & (~arbt_icb_cmd_dcache);//或者是访问外部设备寄存器
	///表示store-c是否执行成功
	//wire arbt_icb_cmd_scond_true;
	//fifo输出的信息--即入队的分发信息，把cmd对应到其rsp
	wire arbt_icb_rsp_biu;
   wire arbt_icb_rsp_dcache;
   wire arbt_icb_rsp_dtcm;
   wire arbt_icb_rsp_itcm;
   wire arbt_icb_rsp_scond_true;	
	//fifo的控制信号
	///fifo的操作--进/出 
	wire splt_fifo_wen = arbt_icb_cmd_valid & arbt_icb_cmd_ready;//cmd握手，进入fifo等待反馈
	wire splt_fifo_ren = arbt_icb_rsp_valid & arbt_icb_rsp_ready;//rsq握手，反馈信号到来，退出fifo，并分发回去
	///fifo入队
	wire splt_fifo_i_ready;//入队准许信号
   wire splt_fifo_i_valid = splt_fifo_wen;//入队请求信号
	///fifo出队
	wire splt_fifo_o_valid;//出队请求信号
   wire splt_fifo_o_ready = splt_fifo_ren;//出队准许信号
	///fifo状态
   wire splt_fifo_empty   = (~splt_fifo_o_valid);//表示队空
   wire splt_fifo_full    = (~splt_fifo_i_ready);//表示队满
   //fifo入队接口
	wire [SPLT_FIFO_W-1:0] splt_fifo_wdat;//入队数据
	assign splt_fifo_wdat =  {
          arbt_icb_cmd_biu,
          arbt_icb_cmd_dcache,
          arbt_icb_cmd_dtcm,
          arbt_icb_cmd_itcm,
          arbt_icb_cmd_scond_true,
          arbt_icb_cmd_usr 
          };
	//fifo出队接口
	wire [SPLT_FIFO_W-1:0] splt_fifo_rdat;//出队数据	
	assign   
      {
          arbt_icb_rsp_biu,
          arbt_icb_rsp_dcache,
          arbt_icb_rsp_dtcm,
          arbt_icb_rsp_itcm,
          arbt_icb_rsp_scond_true, 
          arbt_icb_rsp_usr 
          } = splt_fifo_rdat & {SPLT_FIFO_W{splt_fifo_o_valid}};
	//fifo本体
	sirv_gnrl_pipe_stage # (
    .CUT_READY(0),
    .DP(1),
    .DW(SPLT_FIFO_W)
   ) u_e203_lsu_splt_stage (
    .i_vld  (splt_fifo_i_valid),
    .i_rdy  (splt_fifo_i_ready),
    .i_dat  (splt_fifo_wdat ),
    .o_vld  (splt_fifo_o_valid),
    .o_rdy  (splt_fifo_o_ready),  
    .o_dat  (splt_fifo_rdat ),  
  
    .clk  (clk),
    .rst_n(rst_n)
   );
	
	
	
	
	
	
	
	
//互斥检测器--实现A指令中的load和store的互斥属性，即load相似与信号量的P操作，store相似于信号量的V操作
//当执行load-r时将互斥有效标志设置为，且访问地址写入互斥检测器，之后只有当store-c存储的地址与互斥检测器中的一样时
//才判断为执行成功，并写入以及清除掉互斥检测器的有效标志位，以此实现获取(load-r)与释放(stire-c)属性。
//除了正常清除互斥检测器中有效位之外，还有如下意外情况可清除有效位：异常，中断和mert
///互斥检测器
	//有效位
	wire excl_flg_r;
	wire excl_flg_clr;
	wire excl_flg_ena = excl_flg_set | excl_flg_clr;
   wire excl_flg_nxt = excl_flg_set | (~excl_flg_clr);
   sirv_gnrl_dfflr #(1) excl_flg_dffl (excl_flg_ena, excl_flg_nxt, excl_flg_r, clk, rst_n);
	//存入的地址
	wire [`E203_ADDR_SIZE-1:0] excl_addr_r;
	wire excl_addr_ena;
	wire [`E203_ADDR_SIZE-1:0] excl_addr_nxt;
	sirv_gnrl_dfflr #(`E203_ADDR_SIZE) excl_addr_dffl (excl_addr_ena, excl_addr_nxt, excl_addr_r, clk, rst_n);
	//一些需要的判断信号
	wire icb_cmdaddr_eq_excladdr = (arbt_icb_cmd_addr == excl_addr_r);//判断访问的地址是否与互斥检测器中的一样
///执行load-reserved-获取
   //当load-r发生 设置有效位
	wire excl_flg_set = splt_fifo_wen & arbt_icb_cmd_usr[USR_PACK_EXCL] & arbt_icb_cmd_read & arbt_icb_cmd_excl;
   //当load-r发生 把访问地址写入互斥检测器
	assign excl_addr_ena = excl_flg_set;
	assign excl_addr_nxt = arbt_icb_cmd_addr;
///执行store-condition-释放
   //判断store-c是否成功-执行成功即访问地址于互斥检测器中存储的一致
	wire arbt_icb_cmd_scond = arbt_icb_cmd_usr[USR_PACK_EXCL] & (~arbt_icb_cmd_read);//表示发生的是store-c
	wire arbt_icb_cmd_scond_true = arbt_icb_cmd_scond & icb_cmdaddr_eq_excladdr & excl_flg_r;//表示成功
	//当store-c执行成功时，清除有效位
	assign excl_flg_clr = (splt_fifo_wen & (~arbt_icb_cmd_read) & icb_cmdaddr_eq_excladdr & excl_flg_r) 
                    | commit_trap | commit_mret;//当发生意外情况时也清除
	//当store-c执行不成功的时候，为了防止写入将写入mask置为0
	wire [`E203_XLEN/8-1:0] arbt_icb_cmd_wmask_pos = 
      (arbt_icb_cmd_scond & (~arbt_icb_cmd_scond_true)) ? {`E203_XLEN/8{1'b0}} : arbt_icb_cmd_wmask;
