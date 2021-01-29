//IF
`define XLEN 32//jp指令imm符号扩展后的长度
`define RFIDX_WIDTH 5//寄存器位数
`define RFREG_NUM 32//寄存器个数
`define E203_TIMING_BOOST//开启主要表现在pcfetch中

`define E203_ADDR_SIZE   32//地址宽度
`define E203_CFG_ADDR_SIZE 32//同上
`define E203_CFG_ITCM_ADDR_WIDTH  16//按字节寻址，itcm有64KB
`define E203_ITCM_ADDR_WIDTH  `E203_CFG_ITCM_ADDR_WIDTH
`define E203_ITCM_BASE_REGION  `E203_ADDR_SIZE-1:`E203_ITCM_ADDR_WIDTH//第16位往上全是0，若pc也是则pc的地址落在itcm中


//EX
`define IR_Size 32
`define PC_Size 32