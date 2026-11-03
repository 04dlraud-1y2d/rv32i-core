//==============================================================
// rv32i_defs.vh — 전체 설계에서 공유하는 상수 정의
//
// RV32I 명령어는 32비트 고정 길이이고, 하위 7비트가 opcode다.
// opcode가 "이 명령이 어떤 포맷(R/I/S/B/U/J)인가"를 결정하고,
// funct3 / funct7 이 같은 opcode 안에서 세부 연산을 구분한다.
//==============================================================
`ifndef RV32I_DEFS_VH
`define RV32I_DEFS_VH

//--------------------------------------------------------------
// opcode = instr[6:0]
//--------------------------------------------------------------
`define OP_LUI     7'b0110111   // U: rd = imm<<12
`define OP_AUIPC   7'b0010111   // U: rd = PC + (imm<<12)
`define OP_JAL     7'b1101111   // J: rd = PC+4, PC += imm
`define OP_JALR    7'b1100111   // I: rd = PC+4, PC = (rs1+imm)&~1
`define OP_BRANCH  7'b1100011   // B: 조건 분기
`define OP_LOAD    7'b0000011   // I: rd = mem[rs1+imm]
`define OP_STORE   7'b0100011   // S: mem[rs1+imm] = rs2
`define OP_IMM     7'b0010011   // I: rd = rs1 op imm   (ADDI 등)
`define OP_REG     7'b0110011   // R: rd = rs1 op rs2   (ADD 등)
`define OP_FENCE   7'b0001111   // 이 설계에서는 NOP 취급
`define OP_SYSTEM  7'b1110011   // ECALL/EBREAK → 시뮬레이션 정지

//--------------------------------------------------------------
// ALU 연산 코드
//
// 여기서 정의하지 않는다. alu32.v 가 쓰는 alu_defs.vh 를 그대로
// 가져온다. 두 파일이 각자 `ALU_SUB 를 다른 값으로 정의하면
// 조용히 한쪽이 덮어써지고, 디버깅이 매우 괴로워진다.
// (단일 진실 공급원 — ALU 인코딩의 주인은 ALU 쪽이다)
//--------------------------------------------------------------
`include "alu_defs.vh"

//--------------------------------------------------------------
// immediate 포맷 선택
//--------------------------------------------------------------
`define IMM_I      3'd0
`define IMM_S      3'd1
`define IMM_B      3'd2
`define IMM_U      3'd3
`define IMM_J      3'd4

//--------------------------------------------------------------
// ALU A입력 먹서 / 레지스터 write-back 소스 먹서
//--------------------------------------------------------------
`define SRCA_RS1   2'd0
`define SRCA_PC    2'd1
`define SRCA_ZERO  2'd2   // LUI 전용: 0 + imm

`define RES_ALU    2'd0
`define RES_MEM    2'd1
`define RES_PC4    2'd2   // JAL/JALR의 복귀 주소

`endif
