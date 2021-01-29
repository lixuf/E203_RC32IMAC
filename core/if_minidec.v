`include "gen_defines.v"

module if_minidec(
input [`IR_Size-1:0] in_IR,

//输出至bpu
output dec_if32,
output dec_ifj,
output dec_jal,
output dec_jalr,
output dec_bxx,
output dec_bjp_imm,
output dec_jalr_rs1_indx
);

ex_decoder2 u_ex_decoder2(
.in_IR(in_IR),
.in_PC(`PC_Size'b0),

.dec_if32(dec_if32),
.dec_ifj(dec_ifj),
.dec_jal(dec_jal),
.dec_jalr(dec_jalr),
.dec_bxx(dec_bxx),
.dec_jalr_rs1_indx(dec_jalr_rs1_indx),
.dec_bjp_imm(dec_bjp_imm)
);

endmodule
