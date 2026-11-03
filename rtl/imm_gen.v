//==============================================================
// imm_gen.v — immediate 추출/부호확장
//
// RV32I 설계에서 제일 헷갈리는 부분이고, 버그도 여기서 제일 많이 난다.
// 명령어 비트가 포맷마다 흩어져 있는 이유는 "같은 비트 위치를 최대한
// 재사용해서 먹서를 줄이려고" 일부러 그렇게 배치한 것이다.
//
// 반드시 확인할 것:
//   - 모든 immediate는 instr[31]을 부호비트로 쓴다 (U타입 제외).
//   - B/J 타입은 최하위 비트가 항상 0이다 (2바이트 정렬).
//     그래서 imm[0]을 명령어에 안 싣고 상수 1'b0을 붙인다.
//   - U 타입은 부호확장이 아니라 하위 12비트를 0으로 채운다.
//
// 비트 맵 (i = instr):
//   I : i[31:20]                                      → 12비트
//   S : i[31:25], i[11:7]                             → 12비트
//   B : i[31], i[7], i[30:25], i[11:8], 0             → 13비트
//   U : i[31:12], 12'b0                               → 32비트
//   J : i[31], i[19:12], i[20], i[30:21], 0           → 21비트
//==============================================================
`include "rv32i_defs.vh"

module imm_gen (
    input  wire [31:0] instr,
    input  wire [2:0]  imm_type,
    output reg  [31:0] imm
);

    always @(*) begin
        case (imm_type)
            `IMM_I: imm = {{20{instr[31]}}, instr[31:20]};

            `IMM_S: imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};

            `IMM_B: imm = {{19{instr[31]}}, instr[31], instr[7],
                           instr[30:25], instr[11:8], 1'b0};

            `IMM_U: imm = {instr[31:12], 12'b0};

            `IMM_J: imm = {{11{instr[31]}}, instr[31], instr[19:12],
                           instr[20], instr[30:21], 1'b0};

            default: imm = 32'd0;
        endcase
    end

endmodule
