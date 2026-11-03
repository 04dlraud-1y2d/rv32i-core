//==============================================================
// rv32i_top.v — RV32I 싱글사이클 코어 최상위 (데이터패스 배선)
//
// 한 사이클에 일어나는 일 (전부 같은 사이클 안에서 조합적으로):
//   1. FETCH   : instr_mem[PC] 읽기
//   2. DECODE  : opcode/funct3/funct7 분해 → control, imm_gen
//   3. REG READ: regfile에서 rs1, rs2 비동기 읽기
//   4. EXECUTE : ALU 연산 / 분기조건 판정
//   5. MEMORY  : data_mem 비동기 읽기, 또는 쓰기 데이터 준비
//   6. WRITE   : 클럭 엣지에 regfile / data_mem / PC 가 동시에 갱신
//
// 즉 1~5는 전부 조합 지연이고, 엣지에서 상태(PC, 레지스터, 메모리)만
// 한꺼번에 바뀐다. 클럭 주기는 가장 긴 경로(보통 LOAD:
// PC→instr_mem→regfile→ALU→data_mem→먹서→regfile 입력)로 결정된다.
// 이게 싱글사이클이 느린 이유이고, 파이프라인이 존재하는 이유다.
//==============================================================
`include "rv32i_defs.vh"

module rv32i_top #(
    parameter HEX_FILE  = "program.hex",
    parameter IMEM_WORDS = 1024,
    parameter DMEM_WORDS = 1024
) (
    input  wire        clk,
    input  wire        rst_n,
    output wire        halt,
    output wire [31:0] dbg_pc,
    output wire [31:0] dbg_instr
);

    //==========================================================
    // 1. PC 레지스터
    //==========================================================
    reg  [31:0] pc;
    wire [31:0] pc_next;

    always @(posedge clk) begin
        if (!rst_n)
            pc <= 32'h0000_0000;
        else if (!halt)        // ECALL을 만나면 PC를 멈춘다
            pc <= pc_next;
    end

    wire [31:0] pc_plus4 = pc + 32'd4;

    //==========================================================
    // 2. 명령어 FETCH
    //==========================================================
    wire [31:0] instr;

    instr_mem #(
        .WORDS    (IMEM_WORDS),
        .HEX_FILE (HEX_FILE)
    ) u_imem (
        .addr  (pc),
        .instr (instr)
    );

    //==========================================================
    // 3. 명령어 필드 분해
    //    RV32I는 rs1/rs2/rd 위치가 모든 포맷에서 고정이다.
    //    (해당 포맷이 그 필드를 안 쓰더라도 비트 위치는 같다)
    //==========================================================
    wire [6:0] opcode   = instr[6:0];
    wire [4:0] rd_addr  = instr[11:7];
    wire [2:0] funct3   = instr[14:12];
    wire [4:0] rs1_addr = instr[19:15];
    wire [4:0] rs2_addr = instr[24:20];
    wire       funct7_5 = instr[30];

    //==========================================================
    // 4. 제어 유닛
    //==========================================================
    wire       reg_write;
    wire [1:0] alu_src_a;
    wire       alu_src_b;
    wire [3:0] alu_op;
    wire [2:0] imm_type;
    wire       mem_read;
    wire       mem_write;
    wire [1:0] result_src;
    wire       branch;
    wire       jal;
    wire       jalr;

    control u_ctrl (
        .opcode     (opcode),
        .funct3     (funct3),
        .funct7_5   (funct7_5),
        .reg_write  (reg_write),
        .alu_src_a  (alu_src_a),
        .alu_src_b  (alu_src_b),
        .alu_op     (alu_op),
        .imm_type   (imm_type),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .result_src (result_src),
        .branch     (branch),
        .jal        (jal),
        .jalr       (jalr),
        .halt       (halt)
    );

    //==========================================================
    // 5. immediate
    //==========================================================
    wire [31:0] imm;

    imm_gen u_imm (
        .instr    (instr),
        .imm_type (imm_type),
        .imm      (imm)
    );

    //==========================================================
    // 6. 레지스터 파일
    //==========================================================
    wire [31:0] rs1_data, rs2_data;
    wire [31:0] wb_data;      // write-back 데이터 (아래 먹서에서 결정)

    regfile u_regfile (
        .clk (clk),
        .we  (reg_write && !halt),
        .ra1 (rs1_addr),
        .ra2 (rs2_addr),
        .wa  (rd_addr),
        .wd  (wb_data),
        .rd1 (rs1_data),
        .rd2 (rs2_data)
    );

    //==========================================================
    // 7. ALU 입력 먹서 + ALU
    //==========================================================
    reg [31:0] alu_a;
    always @(*) begin
        case (alu_src_a)
            `SRCA_RS1 : alu_a = rs1_data;
            `SRCA_PC  : alu_a = pc;          // AUIPC
            `SRCA_ZERO: alu_a = 32'd0;       // LUI
            default   : alu_a = rs1_data;
        endcase
    end

    wire [31:0] alu_b = alu_src_b ? imm : rs2_data;
    wire [31:0] alu_y;

    // 구조적 ALU (CLA + 배럴시프터). 플래그 출력은 이 데이터패스에서
    // 쓰지 않는다 — 분기 판정은 branch_unit 이 따로 한다.
    // (플래그로 분기를 돌리고 싶으면 7일차 확장 과제로 남겨둔다)
    alu32 #(
        .W  (32),
        .SW (5)
    ) u_alu (
        .a         (alu_a),
        .b         (alu_b),
        .alu_op    (alu_op),
        .result    (alu_y),
        .zero      (),
        .negative  (),
        .carry_out (),
        .overflow  ()
    );

    //==========================================================
    // 8. 분기 판정
    //==========================================================
    wire br_taken;

    branch_unit u_br (
        .a      (rs1_data),
        .b      (rs2_data),
        .funct3 (funct3),
        .taken  (br_taken)
    );

    //==========================================================
    // 9. 데이터 메모리 + LSU
    //    주소는 ALU가 만든 rs1 + imm 이다.
    //==========================================================
    wire [31:0] mem_rdata;
    wire [31:0] mem_wdata;
    wire [3:0]  wmask;
    wire [31:0] load_data;

    lsu u_lsu (
        .addr      (alu_y),
        .funct3    (funct3),
        .rs2_data  (rs2_data),
        .mem_rdata (mem_rdata),
        .mem_wdata (mem_wdata),
        .wmask     (wmask),
        .load_data (load_data)
    );

    data_mem #(
        .WORDS (DMEM_WORDS)
    ) u_dmem (
        .clk   (clk),
        .we    (mem_write && !halt),
        .addr  (alu_y),
        .wdata (mem_wdata),
        .wmask (wmask),
        .rdata (mem_rdata)
    );

    //==========================================================
    // 10. write-back 먹서
    //==========================================================
    reg [31:0] wb_mux;
    always @(*) begin
        case (result_src)
            `RES_ALU: wb_mux = alu_y;
            `RES_MEM: wb_mux = load_data;
            `RES_PC4: wb_mux = pc_plus4;     // JAL / JALR 복귀주소
            default : wb_mux = alu_y;
        endcase
    end
    assign wb_data = wb_mux;

    //==========================================================
    // 11. 다음 PC 결정
    //
    //  - JALR  : (rs1 + imm) & ~1   ← ALU 결과의 LSB를 0으로 강제
    //            (ISA 규정이다. 빼먹으면 홀수 주소로 점프한다)
    //  - JAL   : PC + imm(J)
    //  - 분기  : 조건 성립 시 PC + imm(B)
    //  - 그 외 : PC + 4
    //==========================================================
    wire [31:0] pc_target = pc + imm;                  // JAL / BRANCH 공용
    wire [31:0] pc_jalr   = {alu_y[31:1], 1'b0};
    wire        take_br   = branch && br_taken;

    assign pc_next = jalr              ? pc_jalr   :
                     (jal || take_br)  ? pc_target :
                                         pc_plus4;

    //==========================================================
    // 디버그 출력
    //==========================================================
    assign dbg_pc    = pc;
    assign dbg_instr = instr;

endmodule
