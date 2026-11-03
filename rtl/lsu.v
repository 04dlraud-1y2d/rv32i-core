//==============================================================
// lsu.v — Load/Store Unit (바이트 정렬 처리)
//
// 데이터메모리는 32비트 워드 단위로만 접근한다. 그런데 ISA는
// LB/LH/SB/SH 같은 바이트/하프워드 접근을 요구한다.
// 그 간극을 메우는 것이 이 모듈의 전부다.
//
// 많은 교과서 구현이 LW/SW만 지원하고 넘어가는 부분인데,
// 실제로 RV32I를 다 돌리려면 반드시 필요하다.
//
// 핵심 아이디어 두 개:
//  1) STORE : rs2를 addr[1:0]만큼 왼쪽으로 바이트 시프트해서 올리고,
//             쓰기 마스크(wmask)로 해당 바이트만 활성화한다.
//  2) LOAD  : 메모리가 준 워드에서 addr[1:0] 위치의 바이트/하프워드를
//             뽑아내고, funct3에 따라 부호확장 또는 0확장한다.
//
// funct3 매핑
//   LOAD  : 000 LB  001 LH  010 LW  100 LBU  101 LHU
//   STORE : 000 SB  001 SH  010 SW
//   (LB/LH는 부호확장, LBU/LHU는 0확장 — 이 차이가 버그의 단골)
//==============================================================
module lsu (
    input  wire [31:0] addr,        // ALU가 계산한 바이트 주소
    input  wire [2:0]  funct3,
    input  wire [31:0] rs2_data,    // STORE할 원본 값
    input  wire [31:0] mem_rdata,   // 메모리가 돌려준 워드(가공 전)

    output reg  [31:0] mem_wdata,   // 정렬된 쓰기 데이터
    output reg  [3:0]  wmask,       // 바이트 쓰기 인에이블
    output reg  [31:0] load_data    // 확장된 읽기 데이터
);

    wire [1:0] off = addr[1:0];          // 워드 내 바이트 오프셋
    wire [4:0] bsh = {off, 3'b000};      // off * 8 (비트 시프트량)

    //----------------------------------------------------------
    // STORE 경로
    //----------------------------------------------------------
    always @(*) begin
        case (funct3)
            3'b000: begin                        // SB
                mem_wdata = rs2_data << bsh;
                wmask     = 4'b0001 << off;
            end
            3'b001: begin                        // SH
                mem_wdata = rs2_data << bsh;
                wmask     = off[1] ? 4'b1100 : 4'b0011;
            end
            3'b010: begin                        // SW
                mem_wdata = rs2_data;
                wmask     = 4'b1111;
            end
            default: begin
                mem_wdata = rs2_data;
                wmask     = 4'b0000;
            end
        endcase
    end

    //----------------------------------------------------------
    // LOAD 경로
    //----------------------------------------------------------
    wire [7:0]  byte_sel = mem_rdata[bsh +: 8];              // 가변 바이트 선택
    wire [15:0] half_sel = off[1] ? mem_rdata[31:16]
                                  : mem_rdata[15:0];

    always @(*) begin
        case (funct3)
            3'b000 : load_data = {{24{byte_sel[7]}},  byte_sel};   // LB  (부호확장)
            3'b001 : load_data = {{16{half_sel[15]}}, half_sel};   // LH  (부호확장)
            3'b010 : load_data = mem_rdata;                        // LW
            3'b100 : load_data = {24'b0, byte_sel};                // LBU (0확장)
            3'b101 : load_data = {16'b0, half_sel};                // LHU (0확장)
            default: load_data = mem_rdata;
        endcase
    end

endmodule
