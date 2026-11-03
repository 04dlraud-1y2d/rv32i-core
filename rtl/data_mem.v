//==============================================================
// data_mem.v — 데이터 메모리 (비동기 읽기 / 동기 쓰기)
//
// 읽기가 조합이어야 싱글사이클이 성립한다 (instr_mem과 같은 이유).
// 쓰기는 클럭 상승엣지에 일어난다.
//
// 바이트 쓰기 인에이블(wmask)을 지원한다. SB/SH 때문에 필요하다.
// 구현 방식: 기존 워드와 새 데이터를 바이트 단위로 먹싱한 merged를
// 만들어 통째로 쓴다. mem[i][7:0] <= ... 같은 부분선택 대입보다
// 합성툴 호환성이 좋다.
//==============================================================
module data_mem #(
    parameter WORDS = 1024
) (
    input  wire        clk,
    input  wire        we,
    input  wire [31:0] addr,       // 바이트 주소
    input  wire [31:0] wdata,      // lsu가 정렬해준 데이터
    input  wire [3:0]  wmask,      // 바이트 쓰기 인에이블
    output wire [31:0] rdata       // 워드 단위 조합 읽기
);

    localparam AW = $clog2(WORDS);

    reg [31:0] mem [0:WORDS-1];
    integer i;

    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'd0;
    end

    wire [AW-1:0] idx = addr[AW+1:2];

    assign rdata = mem[idx];

    // 바이트별 먹싱
    wire [31:0] merged = {
        wmask[3] ? wdata[31:24] : mem[idx][31:24],
        wmask[2] ? wdata[23:16] : mem[idx][23:16],
        wmask[1] ? wdata[15:8]  : mem[idx][15:8],
        wmask[0] ? wdata[7:0]   : mem[idx][7:0]
    };

    always @(posedge clk) begin
        if (we)
            mem[idx] <= merged;
    end

endmodule
