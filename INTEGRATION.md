# alu32 통합 기록

본인 `alu32.v`를 제가 준 `alu.v` 자리에 끼우면서 **4곳**을 고쳤습니다.
그냥 파일만 바꿔 넣으면 컴파일조차 안 됩니다.

검증 상태: **40/40 통과, 58사이클에 ecall 도달** (교체 전과 동일한 사이클 수).

---

## 고친 곳 1 — 매크로 충돌 (`rtl/rv32i_defs.vh`)

제 `rv32i_defs.vh`와 본인 `alu_defs.vh`가 **같은 이름을 다른 값으로** 정의하고 있었습니다.

```
rv32i_defs.vh:  `define ALU_SUB  4'd1       (= 0001)
alu_defs.vh  :  `define ALU_SUB  4'b1000    (= 1000)
```

include guard 이름이 서로 달라서 둘 다 통과하고, 나중에 읽힌 쪽이 조용히 덮어씁니다.
경고 한 줄 뜨고 끝나는데 증상은 "ALU가 가끔 엉뚱한 연산을 한다"로 나타납니다. 최악의 버그 유형입니다.

조치: `rv32i_defs.vh`에서 `ALU_*` 정의를 **전부 삭제**하고 `` `include "alu_defs.vh" ``로 바꿨습니다.
ALU 인코딩의 주인은 ALU 쪽입니다. 단일 진실 공급원을 하나로 둬야 합니다.

## 고친 곳 2 — 디코더 재작성 (`rtl/control.v`)

제 인코딩은 임의 번호(0~9)였고, 본인 인코딩은 `{funct7[5], funct3}` 1:1입니다.
그래서 룩업 `case`문이 아예 필요 없어졌습니다.

```verilog
if (is_reg)
    decode_alu = {f7_5, f3};                    // R타입: 그대로 통과
else
    decode_alu = (f3 == 3'b101) ? {f7_5, f3}    // SRLI / SRAI
                                : {1'b0, f3};   // 그 외 전부
```

**이게 본인이 그 인코딩을 고른 설계 의도입니다.** control path 로직 단수가 실제로 줄었습니다.

### 여기에 함정이 하나 있습니다 — 실제로 터뜨려서 확인했습니다

I타입에서 `instr[30]`을 그대로 쓰면 안 됩니다. I타입에서 그 비트는 `funct7[5]`가 아니라 **`imm[10]`** 입니다.

```
addi x2, x0, -3   →  imm = 0xFFD  →  imm[10] = 1
                  →  {1, 000} = ALU_SUB
                  →  ADDI가 SUB로 디코딩됨  →  x2 = 0 - 3 = +3 (부호 반대!)
```

일부러 그렇게 짜고 돌려본 결과:

```
[FAIL] x2  = 3   기대 -3        ← addi가 sub로 바뀜
[FAIL] x6  = 0   기대 1         ← 그 뒤 slti가 연쇄 오염
[FAIL] x10 = 1   기대 -2
[FAIL] x11 = 13  기대 7
[FAIL] x12 = 7   기대 13
... 9건 실패
```

그래서 `funct3 == 3'b101`(SRLI/SRAI)일 때만 `instr[30]`을 보고, 나머지는 0으로 강제합니다.
`OP_IMM`에는 SUBI가 없으므로 안전합니다.

## 고친 곳 3 — 인스턴스 교체 (`rtl/rv32i_top.v`)

모듈명과 포트명이 다릅니다. `alu` → `alu32`, `y` → `result`, 플래그 4개 추가.

```verilog
alu32 #(.W(32), .SW(5)) u_alu (
    .a(alu_a), .b(alu_b), .alu_op(alu_op),
    .result(alu_y),
    .zero(), .negative(), .carry_out(), .overflow()   // 미사용
);
```

플래그를 비워둔 이유: 이 데이터패스는 분기 판정을 `branch_unit.v`가 따로 합니다.
플래그로 분기를 돌리면 `branch_unit.v`를 지울 수 있지만, `BLTU`/`BGEU`를 `carry_out`에서,
`BLT`/`BGE`를 `negative ^ overflow`에서 끌어내야 하므로 분기마다 SUB를 먼저 시켜야 합니다.
7일차 확장 과제로 남기기 좋은 작업입니다.

## 고친 곳 4 — `rtl/alu.v` 삭제

제 동작적 ALU는 지웠습니다. 남겨두면 `make`의 `rtl/*.v`에 같이 잡혀서
`ALU_*` 매크로를 다시 끌어들입니다.

---

## 추측이 섞인 부분

`alu_defs.vh` 원본이 업로드에 없어서, 파일 헤더 주석의 `{funct7[5], funct3}` 규칙대로 복원한 것입니다.
`ALU_PASSB`는 ISA에 대응 자리가 없어서 `4'b1111`로 **임의 배정**했습니다.

**본인 `alu_defs.vh`가 따로 있으면 `rtl/alu_defs.vh`를 그걸로 덮어쓰고 `make`를 다시 돌리세요.**
`ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND` 10개가 `{funct7[5], funct3}` 규칙을 지키고 있다면
결과는 그대로 통과합니다. 규칙이 다르면 `control.v`의 `decode_alu()`를 그 규칙에 맞게 다시 써야 합니다.

현재 이 코어는 `ALU_PASSB`를 **쓰지 않습니다.** LUI를 `0 + imm`(`SRCA_ZERO` + `ALU_ADD`)으로
처리하고 있어서, PASSB 코드값을 제가 잘못 추측했어도 동작에 영향이 없습니다.
PASSB를 쓰도록 바꾸고 싶으면 `control.v`의 `OP_LUI` 항목에서
`alu_src_a`를 지우고 `alu_op = ALU_PASSB`로 바꾸면 됩니다.
