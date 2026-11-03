//==============================================================
// regfile.v — 32개 x 32비트 범용 레지스터
//
// 싱글사이클 설계의 핵심 타이밍 가정이 여기 있다:
//   - 읽기는 조합(비동기). 같은 사이클에 주소 주고 바로 값이 나온다.
//   - 쓰기는 클럭 상승엣지에 동기.
// 그래서 한 사이클 안에서 "읽고 → 연산하고 → 쓰기 대기" 가 성립한다.
//
// x0는 하드와이어 0이다. 쓰기를 시도해도 무시해야 한다.
// (이걸 빼먹으면 `addi x0, x0, 5` 같은 명령이 x0를 오염시킨다)
//==============================================================
module regfile (
    input  wire        clk,
    input  wire        we,          // write enable
    input  wire [4:0]  ra1,         // read addr 1 (rs1)
    input  wire [4:0]  ra2,         // read addr 2 (rs2)
    input  wire [4:0]  wa,          // write addr  (rd)
    input  wire [31:0] wd,          // write data
    output wire [31:0] rd1,
    output wire [31:0] rd2
);

    reg [31:0] regs [0:31];
    integer i;

    // 시뮬레이션 초기화. 실제 FPGA에서는 x0만 0이면 되고
    // 나머지는 소프트웨어가 초기화하는 것이 원칙이다.
    initial begin
        for (i = 0; i < 32; i = i + 1) regs[i] = 32'd0;
    end

    // 비동기 읽기 + x0 = 0 강제
    assign rd1 = (ra1 == 5'd0) ? 32'd0 : regs[ra1];
    assign rd2 = (ra2 == 5'd0) ? 32'd0 : regs[ra2];

    // 동기 쓰기. wa==0 이면 버린다.
    always @(posedge clk) begin
        if (we && (wa != 5'd0))
            regs[wa] <= wd;
    end

endmodule
