`include "gen_defines.v"

module e203_ifu(
  output[`E203_PC_SIZE-1:0] inspect_pc,
  output ifu_active,
  input  itcm_nohold,

  input  [`E203_PC_SIZE-1:0] pc_rtvec,  

  input  ifu2itcm_holdup,

  input [`E203_ADDR_SIZE-1:0] itcm_region_indic,

  output ifu2itcm_icb_cmd_valid, 
  input  ifu2itcm_icb_cmd_ready, 
          
  output [`E203_ITCM_ADDR_WIDTH-1:0]   ifu2itcm_icb_cmd_addr, 

  input  ifu2itcm_icb_rsp_valid, 
  output ifu2itcm_icb_rsp_ready, 
  input  ifu2itcm_icb_rsp_err,   
          
  input  [`E203_ITCM_DATA_WIDTH-1:0] ifu2itcm_icb_rsp_rdata, 


  output ifu2biu_icb_cmd_valid, 
  input  ifu2biu_icb_cmd_ready, 
         
  output [`E203_ADDR_SIZE-1:0]   ifu2biu_icb_cmd_addr, 


  input  ifu2biu_icb_rsp_valid,
  output ifu2biu_icb_rsp_ready, 
  input  ifu2biu_icb_rsp_err,  
  input  [`E203_SYSMEM_DATA_WIDTH-1:0] ifu2biu_icb_rsp_rdata, 


  output [`E203_INSTR_SIZE-1:0] ifu_o_ir,
  output [`E203_PC_SIZE-1:0] ifu_o_pc,   
  output ifu_o_pc_vld,
  output ifu_o_misalgn,                   
  output ifu_o_buserr,                   
  output [`E203_RFIDX_WIDTH-1:0] ifu_o_rs1idx,
  output [`E203_RFIDX_WIDTH-1:0] ifu_o_rs2idx,
  output ifu_o_prdt_taken,              
  output ifu_o_muldiv_b2b,               
  output ifu_o_valid, 
  input  ifu_o_ready,

  output  pipe_flush_ack,
  input   pipe_flush_req,
  input   [`E203_PC_SIZE-1:0] pipe_flush_add_op1,  
  input   [`E203_PC_SIZE-1:0] pipe_flush_add_op2,
  input   [`E203_PC_SIZE-1:0] pipe_flush_pc,  


      
  input  ifu_halt_req,
  output ifu_halt_ack,

  input  oitf_empty,
  input  [`E203_XLEN-1:0] rf2ifu_x1,
  input  [`E203_XLEN-1:0] rf2ifu_rs1,
  input  dec2ifu_rden,
  input  dec2ifu_rs1en,
  input  [`E203_RFIDX_WIDTH-1:0] dec2ifu_rdidx,
  input  dec2ifu_mulhsu,
  input  dec2ifu_div   ,
  input  dec2ifu_rem   ,
  input  dec2ifu_divu  ,
  input  dec2ifu_remu  ,

  input  clk,
  input  rst_n
  );

  
  wire ifu_req_valid; 
  wire ifu_req_ready; 
  wire [`E203_PC_SIZE-1:0]   ifu_req_pc; 
  wire ifu_req_seq;
  wire ifu_req_seq_rv32;
  wire [`E203_PC_SIZE-1:0] ifu_req_last_pc;
  wire ifu_rsp_valid; 
  wire ifu_rsp_ready; 
  wire ifu_rsp_err;    
  wire [`E203_INSTR_SIZE-1:0] ifu_rsp_instr; 

  e203_ifu_ifetch u_e203_ifu_ifetch(
    .inspect_pc   (inspect_pc),
    .pc_rtvec      (pc_rtvec),  
    .ifu_req_valid (ifu_req_valid),
    .ifu_req_ready (ifu_req_ready),
    .ifu_req_pc    (ifu_req_pc   ),
    .ifu_req_seq     (ifu_req_seq     ),
    .ifu_req_seq_rv32(ifu_req_seq_rv32),
    .ifu_req_last_pc (ifu_req_last_pc ),
    .ifu_rsp_valid (ifu_rsp_valid),
    .ifu_rsp_ready (ifu_rsp_ready),
    .ifu_rsp_err   (ifu_rsp_err  ),
    .ifu_rsp_instr (ifu_rsp_instr),
    .ifu_o_ir      (ifu_o_ir     ),
    .ifu_o_pc      (ifu_o_pc     ),
    .ifu_o_pc_vld  (ifu_o_pc_vld ),
    .ifu_o_misalgn (ifu_o_misalgn),
    .ifu_o_buserr  (ifu_o_buserr ),
    .ifu_o_rs1idx  (ifu_o_rs1idx),
    .ifu_o_rs2idx  (ifu_o_rs2idx),
    .ifu_o_prdt_taken(ifu_o_prdt_taken),
    .ifu_o_muldiv_b2b(ifu_o_muldiv_b2b),
    .ifu_o_valid   (ifu_o_valid  ),
    .ifu_o_ready   (ifu_o_ready  ),
    .pipe_flush_ack     (pipe_flush_ack    ), 
    .pipe_flush_req     (pipe_flush_req    ),
    .pipe_flush_add_op1 (pipe_flush_add_op1),     
    .pipe_flush_pc      (pipe_flush_pc),  
    .pipe_flush_add_op2 (pipe_flush_add_op2), 
    .ifu_halt_req  (ifu_halt_req ),
    .ifu_halt_ack  (ifu_halt_ack ),

    .oitf_empty    (oitf_empty   ),
    .rf2ifu_x1     (rf2ifu_x1    ),
    .rf2ifu_rs1    (rf2ifu_rs1   ),
    .dec2ifu_rden  (dec2ifu_rden ),
    .dec2ifu_rs1en (dec2ifu_rs1en),
    .dec2ifu_rdidx (dec2ifu_rdidx),
    .dec2ifu_mulhsu(dec2ifu_mulhsu),
    .dec2ifu_div   (dec2ifu_div   ),
    .dec2ifu_rem   (dec2ifu_rem   ),
    .dec2ifu_divu  (dec2ifu_divu  ),
    .dec2ifu_remu  (dec2ifu_remu  ),

    .clk           (clk          ),
    .rst_n         (rst_n        ) 
  );



  e203_ifu_ift2icb u_e203_ifu_ift2icb (
    .ifu_req_valid (ifu_req_valid),
    .ifu_req_ready (ifu_req_ready),
    .ifu_req_pc    (ifu_req_pc   ),
    .ifu_req_seq     (ifu_req_seq     ),
    .ifu_req_seq_rv32(ifu_req_seq_rv32),
    .ifu_req_last_pc (ifu_req_last_pc ),
    .ifu_rsp_valid (ifu_rsp_valid),
    .ifu_rsp_ready (ifu_rsp_ready),
    .ifu_rsp_err   (ifu_rsp_err  ),
    .ifu_rsp_instr (ifu_rsp_instr),
    .itcm_nohold   (itcm_nohold),


    .itcm_region_indic (itcm_region_indic),
    .ifu2itcm_icb_cmd_valid(ifu2itcm_icb_cmd_valid),
    .ifu2itcm_icb_cmd_ready(ifu2itcm_icb_cmd_ready),
    .ifu2itcm_icb_cmd_addr (ifu2itcm_icb_cmd_addr ),
    .ifu2itcm_icb_rsp_valid(ifu2itcm_icb_rsp_valid),
    .ifu2itcm_icb_rsp_ready(ifu2itcm_icb_rsp_ready),
    .ifu2itcm_icb_rsp_err  (ifu2itcm_icb_rsp_err  ),
    .ifu2itcm_icb_rsp_rdata(ifu2itcm_icb_rsp_rdata),




    .ifu2biu_icb_cmd_valid(ifu2biu_icb_cmd_valid),
    .ifu2biu_icb_cmd_ready(ifu2biu_icb_cmd_ready),
    .ifu2biu_icb_cmd_addr (ifu2biu_icb_cmd_addr ),
    .ifu2biu_icb_rsp_valid(ifu2biu_icb_rsp_valid),
    .ifu2biu_icb_rsp_ready(ifu2biu_icb_rsp_ready),
    .ifu2biu_icb_rsp_err  (ifu2biu_icb_rsp_err  ),
    .ifu2biu_icb_rsp_rdata(ifu2biu_icb_rsp_rdata),



    .ifu2itcm_holdup (ifu2itcm_holdup),


    .clk           (clk          ),
    .rst_n         (rst_n        ) 
  );

  assign ifu_active = 1'b1;
  
endmodule