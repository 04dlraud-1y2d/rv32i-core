//==============================================================
// control.v — 메인 디코더 (싱글사이클이므로 순수 조합회로)
//
// 이 파일이 CPU 설계의 "두뇌"다. 멀티사이클/파이프라인에서는
// 상태머신이 되지만, 싱글사이클에서는 opcode → 제어신호 진리표다.
//
// 읽는 방법: 아래 case의 각 항목을 데이터패스 그림과 1:1로 대응시켜라.
// 제어신호 하나하나가 그림 속 먹서 하나 또는 write enable 하나다.
//
//   reg_write   : 레지스터파일에 쓸지
//   alu_src_a   : ALU A입력 = rs1 / PC / 0
//   alu_src_b   : ALU B입력 = rs2(0) / imm(1)
//   alu_op      : ALU 연산 종류
//   imm_type    : immediate 포맷
//   mem_read    : 데이터메모리 읽기 (싱글사이클에선 사실상 장식)
//   mem_write   : 데이터메모리 쓰기
//   result_src  : rd에 쓸 값 = ALU / MEM / PC+4
//   branch      : 조건분기 명령인가
//   jal / jalr  : 무조건 점프 종류
//   halt        : ECALL/EBREAK → 시뮬레이션 종료 신호
//==============================================================
`include "rv32i_defs.vh"

module control (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire       funct7_5,   // instr[30]. SUB/SRA/SRAI 구분용

    output reg        reg_write,
    output reg [1:0]  alu_src_a,
    output reg        alu_src_b,
    output reg [3:0]  alu_op,
    output reg [2:0]  imm_type,
    output reg        mem_read,
    output reg        mem_write,
    output reg [1:0]  result_src,
    output reg        branch,
    output reg        jal,
    output reg        jalr,
    output reg        halt
);

    //----------------------------------------------------------
    // funct3 (+ funct7[5]) → ALU 연산 변환
    //
    // alu32 의 alu_op 인코딩이 {funct7[5], funct3} 와 1:1 이므로
    // 룩업테이블이 필요 없다. 명령어 필드를 거의 그대로 흘려보낸다.
    // 이게 그 인코딩을 고른 설계 의도다 — control path 로직 단수가 줄어든다.
    //
    // ★ 단 하나의 함정:
    //   I타입에서 instr[30] 을 그대로 쓰면 안 된다. I타입에서 그 비트는
    //   funct7 이 아니라 imm[10] 이다.
    //   예: addi x2, x0, -3 → imm = 0xFFD → imm[10] = 1
    //       그대로 흘리면 {1,000} = ALU_SUB 로 디코딩되어 ADDI가 SUB가 된다.
    //
    //   그래서 I타입은 funct3 == 101 (SRLI/SRAI) 일 때만 instr[30] 을 보고,
    //   나머지는 0으로 강제한다. OP_IMM 에는 SUBI 가 없으므로 안전하다.
    //----------------------------------------------------------
    function [3:0] decode_alu;
        input [2:0] f3;
        input       f7_5;
        input       is_reg;   // 1 = R타입(OP_REG), 0 = I타입(OP_IMM)
        begin
            if (is_reg)
                decode_alu = {f7_5, f3};                    // R타입: 그대로 통과
            else
                decode_alu = (f3 == 3'b101) ? {f7_5, f3}    // SRLI / SRAI
                                            : {1'b0, f3};   // 그 외 전부
        end
    endfunction

    always @(*) begin
        // 기본값 = 아무것도 하지 않는 NOP. 각 case에서 필요한 것만 덮어쓴다.
        // (이 패턴을 안 쓰면 latch 추론 경고가 쏟아진다)
        reg_write  = 1'b0;
        alu_src_a  = `SRCA_RS1;
        alu_src_b  = 1'b0;
        alu_op     = `ALU_ADD;
        imm_type   = `IMM_I;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        result_src = `RES_ALU;
        branch     = 1'b0;
        jal        = 1'b0;
        jalr       = 1'b0;
        halt       = 1'b0;

        case (opcode)
            // rd = imm<<12.  ALU로 0 + imm 을 계산해서 재사용한다.
            `OP_LUI: begin
                reg_write  = 1'b1;
                alu_src_a  = `SRCA_ZERO;
                alu_src_b  = 1'b1;
                alu_op     = `ALU_ADD;
                imm_type   = `IMM_U;
                result_src = `RES_ALU;
            end

            // rd = PC + (imm<<12)
            `OP_AUIPC: begin
                reg_write  = 1'b1;
                alu_src_a  = `SRCA_PC;
                alu_src_b  = 1'b1;
                alu_op     = `ALU_ADD;
                imm_type   = `IMM_U;
                result_src = `RES_ALU;
            end

            // rd = PC+4 ; PC = PC + imm
            // 목표주소는 top의 전용 가산기(pc + imm)가 만든다.
            `OP_JAL: begin
                reg_write  = 1'b1;
                imm_type   = `IMM_J;
                result_src = `RES_PC4;
                jal        = 1'b1;
            end

            // rd = PC+4 ; PC = (rs1 + imm) & ~1
            // 목표주소는 ALU가 만든다 (rs1 + imm).
            `OP_JALR: begin
                reg_write  = 1'b1;
                alu_src_a  = `SRCA_RS1;
                alu_src_b  = 1'b1;
                alu_op     = `ALU_ADD;
                imm_type   = `IMM_I;
                result_src = `RES_PC4;
                jalr       = 1'b1;
            end

            // 조건분기. rd에 쓰지 않는다.
            `OP_BRANCH: begin
                imm_type = `IMM_B;
                branch   = 1'b1;
            end

            // rd = mem[rs1 + imm]
            `OP_LOAD: begin
                reg_write  = 1'b1;
                alu_src_a  = `SRCA_RS1;
                alu_src_b  = 1'b1;
                alu_op     = `ALU_ADD;
                imm_type   = `IMM_I;
                mem_read   = 1'b1;
                result_src = `RES_MEM;
            end

            // mem[rs1 + imm] = rs2
            `OP_STORE: begin
                alu_src_a = `SRCA_RS1;
                alu_src_b = 1'b1;
                alu_op    = `ALU_ADD;
                imm_type  = `IMM_S;
                mem_write = 1'b1;
            end

            // rd = rs1 op imm
            `OP_IMM: begin
                reg_write  = 1'b1;
                alu_src_a  = `SRCA_RS1;
                alu_src_b  = 1'b1;
                alu_op     = decode_alu(funct3, funct7_5, 1'b0);
                imm_type   = `IMM_I;
                result_src = `RES_ALU;
            end

            // rd = rs1 op rs2
            `OP_REG: begin
                reg_write  = 1'b1;
                alu_src_a  = `SRCA_RS1;
                alu_src_b  = 1'b0;
                alu_op     = decode_alu(funct3, funct7_5, 1'b1);
                result_src = `RES_ALU;
            end

            // 이 설계에서는 메모리 순서 보장이 필요 없으므로 NOP
            `OP_FENCE: begin
                // 전부 기본값(NOP)
            end

            // ECALL / EBREAK → 시뮬레이션 정지
            `OP_SYSTEM: begin
                halt = 1'b1;
            end

            default: begin
                // 정의되지 않은 opcode. 실제 CPU라면 illegal instruction
                // 예외를 띄워야 한다. 여기서는 NOP으로 흘린다.
            end
        endcase
    end

endmodule
