//==============================================================
// tb_rv32i.v — RV32I 코어 테스트벤치
//
// 실행:
//   iverilog -g2005 -I rtl -o sim.out rtl/*.v test/tb_rv32i.v
//   ./sim.out                  → 결과 요약만
//   ./sim.out +trace           → 매 사이클 PC/명령어 추적
//   ./sim.out +dump            → wave.vcd 생성 (GTKWave로 열기)
//
// 검증 방식: 프로그램이 ecall로 멈춘 뒤
//   (1) 레지스터 파일 최종값
//   (2) 데이터 메모리 최종값
// 을 기대값과 비교한다. 계층적 참조(dut.u_regfile.regs[i])를 쓰는데,
// 이건 시뮬레이션 전용 문법이다. 합성에는 쓸 수 없다.
//==============================================================
`timescale 1ns / 1ps

module tb_rv32i;

    reg  clk   = 1'b0;
    reg  rst_n = 1'b0;
    wire halt;
    wire [31:0] dbg_pc, dbg_instr;

    integer errors = 0;
    integer checks = 0;
    integer cycles = 0;
    integer i;

    localparam MAX_CYCLES = 2000;

    //----------------------------------------------------------
    // DUT
    //----------------------------------------------------------
    rv32i_top #(
        .HEX_FILE ("test/test_rv32i.hex")
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .halt      (halt),
        .dbg_pc    (dbg_pc),
        .dbg_instr (dbg_instr)
    );

    //----------------------------------------------------------
    // 클럭: 주기 10ns
    //----------------------------------------------------------
    always #5 clk = ~clk;

    //----------------------------------------------------------
    // 검사 태스크
    //----------------------------------------------------------
    task check_reg;
        input [4:0]  idx;
        input [31:0] expected;
        reg   [31:0] actual;
        begin
            actual = (idx == 0) ? 32'd0 : dut.u_regfile.regs[idx];
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("  [FAIL] x%0d = 0x%08x (%0d)   기대 0x%08x (%0d)",
                         idx, actual, $signed(actual),
                         expected, $signed(expected));
            end
        end
    endtask

    task check_mem;
        input [31:0] byte_addr;
        input [31:0] expected;
        reg   [31:0] actual;
        begin
            actual = dut.u_dmem.mem[byte_addr >> 2];
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("  [FAIL] mem[0x%03x] = 0x%08x   기대 0x%08x",
                         byte_addr, actual, expected);
            end
        end
    endtask

    //----------------------------------------------------------
    // 추적 (옵션)
    //----------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n && !halt && $test$plusargs("trace"))
            $display("  %4d  pc=0x%08x  instr=0x%08x", cycles, dbg_pc, dbg_instr);
    end

    //----------------------------------------------------------
    // 메인
    //----------------------------------------------------------
    initial begin
        if ($test$plusargs("dump")) begin
            $dumpfile("wave.vcd");
            $dumpvars(0, tb_rv32i);
        end

        $display("");
        $display("================ RV32I 싱글사이클 테스트 ================");

        // 리셋 2사이클
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        // halt 까지 실행
        while (!halt && cycles < MAX_CYCLES) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (cycles >= MAX_CYCLES) begin
            $display("[ERROR] %0d 사이클 내에 ecall에 도달하지 못했습니다.", MAX_CYCLES);
            $display("        → PC가 폭주하거나 무한루프에 빠진 것입니다.");
            errors = errors + 1;
        end else begin
            $display("ecall 도달. 실행 사이클 = %0d", cycles);
        end

        $display("");
        $display("---- 레지스터 검사 ----");

        // ---- I타입 / 기본 ----
        check_reg(5'd1,  32'd10);
        check_reg(5'd2,  -32'sd3);
        check_reg(5'd3,  32'd2);              // andi
        check_reg(5'd4,  32'd15);             // ori
        check_reg(5'd5,  32'd5);              // xori
        check_reg(5'd6,  32'd1);              // slti  (부호)
        check_reg(5'd7,  32'd0);              // sltiu (무부호)
        check_reg(5'd8,  32'd40);             // slli
        check_reg(5'd9,  32'd5);              // srli
        check_reg(5'd10, -32'sd2);            // srai  (산술 시프트)

        // ---- R타입 ----
        check_reg(5'd11, 32'd7);              // add
        check_reg(5'd12, 32'd13);             // sub
        check_reg(5'd13, 32'd10240);          // sll
        check_reg(5'd14, 32'd1);              // slt
        check_reg(5'd15, 32'd0);              // sltu
        check_reg(5'd16, -32'sd9);            // xor
        check_reg(5'd17, 32'd10);             // srl  (shamt=0)
        check_reg(5'd18, -32'sd3);            // sra  (shamt=0)
        check_reg(5'd19, -32'sd1);            // or
        check_reg(5'd20, 32'd8);              // and

        // ---- U타입 ----
        check_reg(5'd21, 32'h12345000);       // lui
        check_reg(5'd22, 32'h0000005c);       // auipc: 해당 명령의 PC

        // ---- load 결과 ----
        check_reg(5'd23, 32'h00000100);       // base
        check_reg(5'd24, 32'd10);             // lw
        check_reg(5'd25, -32'sd1);
        check_reg(5'd26, -32'sd1);            // lb  부호확장
        check_reg(5'd27, 32'd255);            // lbu 0확장
        check_reg(5'd28, -32'sd1);            // lh  부호확장
        check_reg(5'd29, 32'd65535);          // lhu 0확장

        // ---- 분기 / 점프 ----
        check_reg(5'd30, 32'd63);             // 6종 분기 전부 정답
        check_reg(5'd31, 32'h000000ec);       // jal 복귀주소

        $display("---- 메모리 검사 ----");
        check_mem(32'h100, 32'h0000000a);     // sw
        check_mem(32'h104, 32'h000000ff);     // sb  (byte0)
        check_mem(32'h108, 32'h0000ffff);     // sh  (low half)
        check_mem(32'h110, 32'h00005a00);     // sb  (byte1 — 비정렬 오프셋)
        check_mem(32'h114, 32'h07ab0000);     // sh  (high half)
        check_mem(32'h200, 32'h0000000a);     // FUNC 실행 표식
        check_mem(32'h210, 32'h0000005a);     // lbu 재저장
        check_mem(32'h214, 32'h000007ab);     // lhu 재저장

        // ---- x0 불변 확인 ----
        check_reg(5'd0, 32'd0);

        $display("");
        if (errors == 0)
            $display("  ✅  PASS — %0d개 항목 전부 통과", checks);
        else
            $display("  ❌  FAIL — %0d개 중 %0d개 실패", checks, errors);
        $display("=========================================================");
        $display("");

        $finish;
    end

endmodule
