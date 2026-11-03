//==============================================================
// instr_mem.v — 명령어 메모리 (비동기 ROM)
//
// 싱글사이클이 성립하려면 명령어 fetch가 조합적으로 끝나야 한다.
// 그래서 여기는 클럭이 없는 비동기 읽기다.
//
// 실제 FPGA에서는 Block RAM이 동기 읽기라서 이 구조가 그대로
// 합성되지 않는다 → 그때는 "fetch 1사이클"을 인정하고
// 멀티사이클이나 파이프라인으로 넘어가야 한다.
// 이게 싱글사이클 설계를 FPGA에 올릴 때 처음 만나는 벽이다.
//
// addr는 바이트 주소로 들어오고, 워드 인덱스는 addr[AW+1:2]다.
// (명령어는 4바이트 정렬이므로 하위 2비트는 항상 0)
//==============================================================
module instr_mem #(
    parameter WORDS    = 1024,
    parameter HEX_FILE = "program.hex"
) (
    input  wire [31:0] addr,
    output wire [31:0] instr
);

    localparam AW = $clog2(WORDS);

    reg [31:0] mem [0:WORDS-1];
    integer i;

    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h00000013; // NOP(addi x0,x0,0)
        $readmemh(HEX_FILE, mem);
    end

    assign instr = mem[addr[AW+1:2]];

endmodule
