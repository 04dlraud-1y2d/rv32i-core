//==============================================================
// alu_defs.vh — 재구성본
//
// 주의: 원본 alu_defs.vh 가 업로드에 없어서, 파일 헤더 주석에 적힌
//       "ALU control code = {funct7[5], funct3} 와 1:1 대응" 규칙을
//       그대로 따라 복원한 것이다. 실제 본인 파일과 숫자가 다르면
//       아래를 본인 것으로 교체해야 한다.
//
//   {f7_5, funct3}
//     0_000  ADD      1_000  SUB
//     0_001  SLL
//     0_010  SLT
//     0_011  SLTU
//     0_100  XOR
//     0_101  SRL      1_101  SRA
//     0_110  OR
//     0_111  AND
//
//   PASSB 는 ISA 필드에 대응되는 자리가 없다(LUI 전용).
//   남은 코드 중 하나를 써야 하는데, 여기서는 1_111 로 가정했다.
//   ← 이 값은 추측이다.
//==============================================================
`ifndef ALU_DEFS_VH
`define ALU_DEFS_VH

`define ALU_ADD    4'b0000
`define ALU_SLL    4'b0001
`define ALU_SLT    4'b0010
`define ALU_SLTU   4'b0011
`define ALU_XOR    4'b0100
`define ALU_SRL    4'b0101
`define ALU_OR     4'b0110
`define ALU_AND    4'b0111
`define ALU_SUB    4'b1000
`define ALU_SRA    4'b1101
`define ALU_PASSB  4'b1111

`endif
