#==============================================================
# RV32I 싱글사이클 코어 빌드/시뮬레이션
#
#   make          전체 (어셈블 → 컴파일 → 실행)
#   make trace    매 사이클 PC/명령어 출력
#   make wave     wave.vcd 생성 (gtkwave wave.vcd 로 열기)
#   make asm      테스트 프로그램만 다시 어셈블
#   make clean
#==============================================================

IVERILOG := iverilog
VVP      := vvp
PYTHON   := python3

RTL  := $(wildcard rtl/*.v)
TB   := test/tb_rv32i.v
SRC  := test/test_rv32i.s
HEX  := test/test_rv32i.hex
LST  := test/test_rv32i.lst
OUT  := sim.out

.PHONY: all asm trace wave clean

all: $(OUT)
	./$(OUT)

$(OUT): $(RTL) $(TB) $(HEX)
	$(IVERILOG) -g2005 -I rtl -o $(OUT) $(RTL) $(TB)

asm: $(HEX)

$(HEX): $(SRC) tools/asm.py
	$(PYTHON) tools/asm.py $(SRC) $(HEX) --list $(LST)

trace: $(OUT)
	./$(OUT) +trace

wave: $(OUT)
	./$(OUT) +dump
	@echo "wave.vcd 생성됨. gtkwave wave.vcd"

clean:
	rm -f $(OUT) $(HEX) $(LST) wave.vcd
