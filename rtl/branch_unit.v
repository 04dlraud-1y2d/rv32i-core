//==============================================================
// branch_unit.v — 분기 조건 판정
//
// ALU로도 할 수 있지만(SLT/SUB 조합) 별도 비교기를 두는 쪽이
// 읽기 쉽고, 파이프라인으로 확장할 때도 분리해두는 게 편하다.
//
// funct3로 6가지를 구분한다. 010/011은 RV32I에 없는 빈자리다.
//   000 BEQ   001 BNE
//   100 BLT   101 BGE    (부호 비교)
//   110 BLTU  111 BGEU   (무부호 비교)
//==============================================================
module branch_unit (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [2:0]  funct3,
    output reg         taken
);

    always @(*) begin
        case (funct3)
            3'b000 : taken = (a == b);                        // BEQ
            3'b001 : taken = (a != b);                        // BNE
            3'b100 : taken = ($signed(a) <  $signed(b));      // BLT
            3'b101 : taken = ($signed(a) >= $signed(b));      // BGE
            3'b110 : taken = (a <  b);                        // BLTU
            3'b111 : taken = (a >= b);                        // BGEU
            default: taken = 1'b0;
        endcase
    end

endmodule
