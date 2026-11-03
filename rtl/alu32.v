//==============================================================
//  alu_defs.vh  --  RV32I ALU control encoding
//--------------------------------------------------------------
//  ALU control code = {funct7[5], funct3} 와 1:1 대응되도록 배치.
//  디코더가 instruction field 를 거의 그대로 흘려보낼 수 있어
//  control path 의 로직 단수를 줄일 수 있다.
//==============================================================
`include "alu_defs.vh"

`timescale 1ns/1ps


module cla0(
  input wire [3:0] a,
  input wire [3:0] b,
  input wire cin,
  output wire [3:0] sum,
  output wire bg,
  output wire bp,
  output wire c3
);
  wire [3:0] g=a&b;
  wire [3:0] p=a^b;
  wire [3:0] c;
  assign c[0]=cin;
  assign c[1]=g[0]|(p[0]&cin);
  assign c[2]=g[1]|(p[1]&g[0])|(p[1]&p[0]&cin);
  assign c[3]=g[2]|(p[2]&g[1])|(p[2]&p[1]&g[0])|(p[2]&p[1]&p[0]&cin);
  assign sum=p^c;
  assign c3=c[3];
  assign bg=g[3]|(p[3]&g[2])|(p[3]&p[2]&g[1])|(p[3]&p[2]&p[1]&g[0]);
  assign bp=&p;
endmodule

module cla #(
  parameter W=32,
  parameter B=W/4
)(
  input wire [W-1:0] a,
  input wire [W-1:0] b,
  input wire cin,
  output wire [W-1:0] sum,
  output cout,
  output cout_prev);
  
  wire [B-1:0] bg, bp, c3;
  wire [B:0] bc;
  assign bc[0]=cin;
  
  genvar j;
  generate //하드웨어 구조(모듈, 게이트등)의 반복 생성 및 조건부 선택. 컴파일 때 한번 실행
    //반면 always는 if나 for처럼 함수 안의 제어문. 런타임동안 신호 감지시 특정 동작 기술
    for(j=0;j<B;j=j+1) begin: BLK
      cla0 inst1(.a(a[4*j +:4]), 
                 .b(b[4*j +:4]), 
                 .cin(bc[j]), 
                 .sum(sum[4*j +:4]), 
                 .bg(bg[j]),
                 .bp(bp[j]),
                 .c3(c3[j])
                );
      assign bc[j+1]=bg[j]|bp[j]&bc[j];
    end
  endgenerate
  
  assign cout=bc[B];
  assign cout_prev=c3[B-1];
endmodule

    
module barrel_shifter #(
  parameter W=32,
  parameter SW=5)(
  input wire [W-1:0] din,
  input wire [SW-1:0] shamt,
  input wire left,
  input wire arith,
  output wire [W-1:0] dout);
  
  function [W-1:0] bitrev;
    input [W-1:0] x;
    integer k;
    begin
      for(k=0;k<W;k=k+1)
        bitrev[k]=x[W-1-k];
    end
  endfunction
  
  wire [W-1:0] src=left? bitrev(din):din;
  wire fill=(arith&~left)? din[W-1]:1'b0;
  wire [W-1:0] stg[0:SW];
  assign stg[0]=src;
  
  genvar s;
  generate
    for(s=0;s<SW;s=s+1) begin: SHIFT_STAGE
      localparam integer D=(1<<s);
      assign stg[s+1]=shamt[s]? {{D{fill}},stg[s][W-1:D]}:stg[s];
    end
  endgenerate
  
  assign dout=left? bitrev(stg[SW]):stg[SW];
endmodule

module alu32 #(
  parameter W=32,
  parameter SW=5)(
  input wire [W-1:0] a,
  input wire [W-1:0] b,
  input wire [3:0] alu_op,
  output reg [W-1:0] result,
  output wire zero,
  output wire negative, 
  output wire carry_out,
  output wire overflow);
  
  wire do_sub=(alu_op==`ALU_SUB)|(alu_op==`ALU_SLT)|(alu_op==`ALU_SLTU);
  wire [W-1:0] b_eff=b^{W{do_sub}};
  wire [W-1:0] sum;
  wire cout, cout_prev;
  
  cla #(.W(W)) u_add (
    .a(a), 
    .b(b_eff), 
    .cin(do_sub), 
    .sum(sum), 
    .cout(cout), 
    .cout_prev(cout_prev));
  
  wire ovf_raw = cout^cout_prev;
  wire slt_signed=sum[W-1]^ovf_raw;
  wire slt_unsigned=~cout;
  wire [W-1:0] shift_out;
  
  barrel_shifter #(.W(W), .SW(SW)) inst1(
    .din(a),
    .shamt(b[SW-1:0]),
    .left(alu_op==`ALU_SLL),
    .arith(alu_op==`ALU_SRA),
    .dout(shift_out));
  
  always@(*) begin
    case(alu_op)
      `ALU_ADD, `ALU_SUB: result=sum;
      `ALU_AND: result=a&b;
      `ALU_OR: result=a|b;
      `ALU_XOR: result=a^b;
      `ALU_SLL, `ALU_SRL, `ALU_SRA: result=shift_out;
      `ALU_SLT: result={{(W-1){1'b0}}, slt_signed};
      `ALU_SLTU: result={{(W-1){1'b0}}, slt_unsigned};
      `ALU_PASSB: result=b;
      default: result={W{1'b0}};
    endcase
  end
  
  wire is_arith=(alu_op==`ALU_ADD)||(alu_op==`ALU_SUB);
  assign zero=~(|result);
  assign negative=result[W-1];
  assign carry_out=is_arith?cout:1'b0;
  assign overflow=is_arith?ovf_raw:1'b0;
endmodule
  
      

  
      
    
                                      
                                      