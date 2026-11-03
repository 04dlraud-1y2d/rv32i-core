#!/usr/bin/env python3
"""
asm.py - 최소 RV32I 어셈블러

사용법:
    python3 asm.py input.s output.hex [--list listing.txt]

출력은 $readmemh 가 읽을 수 있는 형식(한 줄에 32비트 워드 하나)이다.

지원:
  - RV32I 기본 정수 명령 전체 (FENCE/CSR 제외)
  - 라벨, 주석(#, //)
  - 의사명령: nop, mv, li, j, jr, ret, not, neg, seqz, snez
  - 지시어: .word

왜 어셈블러를 직접 쓰는가:
  명령어 인코딩을 손으로 한 번 짜보면 imm_gen.v 의 비트 배치가
  왜 그 모양인지 몸으로 이해된다. 특히 B/J 타입의 비트 뒤섞기는
  인코더를 써보는 것이 디코더를 읽는 것보다 빠르다.
"""

import re
import sys

# ---------------------------------------------------------------- 레지스터
ABI = {
    'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4,
    't0': 5, 't1': 6, 't2': 7,
    's0': 8, 'fp': 8, 's1': 9,
    'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13,
    'a4': 14, 'a5': 15, 'a6': 16, 'a7': 17,
    's2': 18, 's3': 19, 's4': 20, 's5': 21, 's6': 22,
    's7': 23, 's8': 24, 's9': 25, 's10': 26, 's11': 27,
    't3': 28, 't4': 29, 't5': 30, 't6': 31,
}


def reg(tok):
    t = tok.strip().lower()
    if re.fullmatch(r'x\d+', t):
        n = int(t[1:])
        if not 0 <= n <= 31:
            raise ValueError(f'레지스터 범위 초과: {tok}')
        return n
    if t in ABI:
        return ABI[t]
    raise ValueError(f'알 수 없는 레지스터: {tok}')


def imm(tok, labels=None, pc=None):
    t = tok.strip()
    if labels is not None and t in labels:
        return labels[t] - (pc or 0)
    try:
        return int(t, 0)
    except ValueError:
        raise ValueError(f'숫자/라벨을 해석할 수 없음: {tok}')


def chk(v, bits, name):
    """부호 있는 bits비트 범위 검사"""
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if not lo <= v <= hi:
        raise ValueError(f'{name} 범위 초과: {v} (허용 {lo}..{hi})')
    return v & ((1 << bits) - 1)


# ---------------------------------------------------------------- 인코더
def r_type(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def i_type(i12, rs1, f3, rd, op):
    return ((i12 & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def s_type(i12, rs2, rs1, f3, op):
    i12 &= 0xFFF
    return (((i12 >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (f3 << 12) | ((i12 & 0x1F) << 7) | op


def b_type(i13, rs2, rs1, f3, op):
    # imm[12|10:5] rs2 rs1 f3 imm[4:1|11] op
    i13 &= 0x1FFF
    b12 = (i13 >> 12) & 1
    b11 = (i13 >> 11) & 1
    b10_5 = (i13 >> 5) & 0x3F
    b4_1 = (i13 >> 1) & 0xF
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | \
           (f3 << 12) | (b4_1 << 8) | (b11 << 7) | op


def u_type(i20, rd, op):
    return ((i20 & 0xFFFFF) << 12) | (rd << 7) | op


def j_type(i21, rd, op):
    # imm[20|10:1|11|19:12] rd op
    i21 &= 0x1FFFFF
    b20 = (i21 >> 20) & 1
    b19_12 = (i21 >> 12) & 0xFF
    b11 = (i21 >> 11) & 1
    b10_1 = (i21 >> 1) & 0x3FF
    return (b20 << 31) | (b19_12 << 12) | (b11 << 20) | (b10_1 << 21) | \
           (rd << 7) | op


# ---------------------------------------------------------------- 명령어 표
OP_REG, OP_IMM = 0b0110011, 0b0010011
OP_LOAD, OP_STORE = 0b0000011, 0b0100011
OP_BRANCH, OP_JAL, OP_JALR = 0b1100011, 0b1101111, 0b1100111
OP_LUI, OP_AUIPC, OP_SYSTEM = 0b0110111, 0b0010111, 0b1110011

R_OPS = {   # name: (funct7, funct3)
    'add': (0x00, 0b000), 'sub': (0x20, 0b000),
    'sll': (0x00, 0b001), 'slt': (0x00, 0b010), 'sltu': (0x00, 0b011),
    'xor': (0x00, 0b100), 'srl': (0x00, 0b101), 'sra': (0x20, 0b101),
    'or': (0x00, 0b110), 'and': (0x00, 0b111),
}
I_OPS = {   # name: funct3
    'addi': 0b000, 'slti': 0b010, 'sltiu': 0b011,
    'xori': 0b100, 'ori': 0b110, 'andi': 0b111,
}
SHIFT_I = {  # name: (funct3, funct7)
    'slli': (0b001, 0x00), 'srli': (0b101, 0x00), 'srai': (0b101, 0x20),
}
LOADS = {'lb': 0b000, 'lh': 0b001, 'lw': 0b010, 'lbu': 0b100, 'lhu': 0b101}
STORES = {'sb': 0b000, 'sh': 0b001, 'sw': 0b010}
BRANCHES = {'beq': 0b000, 'bne': 0b001, 'blt': 0b100,
            'bge': 0b101, 'bltu': 0b110, 'bgeu': 0b111}

MEM_RE = re.compile(r'^\s*(-?\w+)\s*\(\s*([\w\d]+)\s*\)\s*$')


def split_ops(s):
    return [o.strip() for o in s.split(',')] if s.strip() else []


def li_words(v):
    """li 가 몇 개 명령으로 펼쳐지는지 / 어떻게 펼쳐지는지"""
    if -2048 <= v <= 2047:
        return 1
    return 2


# ---------------------------------------------------------------- 파싱
def parse(src):
    """(addr, mnemonic, operand_str, srcline) 리스트와 라벨 테이블을 만든다"""
    items, labels = [], {}
    addr = 0
    for ln, raw in enumerate(src.splitlines(), 1):
        line = raw.split('#')[0].split('//')[0].strip()
        while line:
            m = re.match(r'^([A-Za-z_.$][\w.$]*)\s*:\s*(.*)$', line)
            if m:
                name = m.group(1)
                if name in labels:
                    raise ValueError(f'{ln}행: 라벨 중복 {name}')
                labels[name] = addr
                line = m.group(2).strip()
                continue
            break
        if not line:
            continue

        parts = line.split(None, 1)
        mn = parts[0].lower()
        ops = parts[1] if len(parts) > 1 else ''

        if mn == '.word':
            n = len(split_ops(ops))
            items.append((addr, mn, ops, ln))
            addr += 4 * n
            continue

        size = 4
        if mn == 'li':
            o = split_ops(ops)
            try:
                size = 4 * li_words(int(o[1], 0))
            except ValueError:
                size = 4          # 라벨이면 lui+addi 대신 1개로 가정하지 않음
        items.append((addr, mn, ops, ln))
        addr += size
    return items, labels


def encode(items, labels):
    out = []
    for addr, mn, ops_s, ln in items:
        try:
            o = split_ops(ops_s)

            # ---------------- 지시어
            if mn == '.word':
                for k, v in enumerate(o):
                    out.append((addr + 4 * k, imm(v, labels), ln, mn, v))
                continue

            # ---------------- 의사명령 → 실제 명령 치환
            if mn == 'nop':
                mn, o = 'addi', ['x0', 'x0', '0']
            elif mn == 'mv':
                mn, o = 'addi', [o[0], o[1], '0']
            elif mn == 'not':
                mn, o = 'xori', [o[0], o[1], '-1']
            elif mn == 'neg':
                mn, o = 'sub', [o[0], 'x0', o[1]]
            elif mn == 'seqz':
                mn, o = 'sltiu', [o[0], o[1], '1']
            elif mn == 'snez':
                mn, o = 'sltu', [o[0], 'x0', o[1]]
            elif mn == 'j':
                mn, o = 'jal', ['x0', o[0]]
            elif mn == 'jr':
                mn, o = 'jalr', ['x0', '0(' + o[0] + ')']
            elif mn == 'ret':
                mn, o = 'jalr', ['x0', '0(x1)']
            elif mn == 'li':
                v = imm(o[1], labels)
                rd = reg(o[0])
                if -2048 <= v <= 2047:
                    out.append((addr, i_type(v, 0, 0b000, rd, OP_IMM), ln, 'addi', ops_s))
                else:
                    hi = (v + 0x800) >> 12
                    lo = v - (hi << 12)
                    out.append((addr, u_type(hi, rd, OP_LUI), ln, 'lui', ops_s))
                    out.append((addr + 4, i_type(lo, rd, 0b000, rd, OP_IMM), ln, 'addi', ops_s))
                continue

            # ---------------- 실제 명령
            if mn in R_OPS:
                f7, f3 = R_OPS[mn]
                w = r_type(f7, reg(o[2]), reg(o[1]), f3, reg(o[0]), OP_REG)

            elif mn in I_OPS:
                v = chk(imm(o[2], labels), 12, 'immediate')
                w = i_type(v, reg(o[1]), I_OPS[mn], reg(o[0]), OP_IMM)

            elif mn in SHIFT_I:
                f3, f7 = SHIFT_I[mn]
                sh = imm(o[2], labels)
                if not 0 <= sh <= 31:
                    raise ValueError(f'shamt 범위 초과: {sh}')
                w = i_type((f7 << 5) | sh, reg(o[1]), f3, reg(o[0]), OP_IMM)

            elif mn in LOADS:
                m = MEM_RE.match(o[1])
                if not m:
                    raise ValueError(f'형식 오류. offset(reg) 필요: {o[1]}')
                v = chk(imm(m.group(1), labels), 12, 'offset')
                w = i_type(v, reg(m.group(2)), LOADS[mn], reg(o[0]), OP_LOAD)

            elif mn in STORES:
                m = MEM_RE.match(o[1])
                if not m:
                    raise ValueError(f'형식 오류. offset(reg) 필요: {o[1]}')
                v = chk(imm(m.group(1), labels), 12, 'offset')
                w = s_type(v, reg(o[0]), reg(m.group(2)), STORES[mn], OP_STORE)

            elif mn in BRANCHES:
                tgt = imm(o[2], labels) - (addr if o[2] in labels else 0)
                v = chk(tgt, 13, 'branch offset')
                w = b_type(v, reg(o[1]), reg(o[0]), BRANCHES[mn], OP_BRANCH)

            elif mn == 'jal':
                if len(o) == 1:          # jal label  (rd=x1 생략형)
                    rd, t = 1, o[0]
                else:
                    rd, t = reg(o[0]), o[1]
                tgt = imm(t, labels) - (addr if t in labels else 0)
                v = chk(tgt, 21, 'jal offset')
                w = j_type(v, rd, OP_JAL)

            elif mn == 'jalr':
                if len(o) == 1:
                    m = MEM_RE.match(o[0])
                    rd = 1
                else:
                    m = MEM_RE.match(o[1])
                    rd = reg(o[0])
                if not m:
                    raise ValueError(f'형식 오류. offset(reg) 필요: {o[-1]}')
                v = chk(imm(m.group(1), labels), 12, 'offset')
                w = i_type(v, reg(m.group(2)), 0b000, rd, OP_JALR)

            elif mn == 'lui':
                w = u_type(imm(o[1], labels), reg(o[0]), OP_LUI)

            elif mn == 'auipc':
                w = u_type(imm(o[1], labels), reg(o[0]), OP_AUIPC)

            elif mn == 'ecall':
                w = 0x00000073
            elif mn == 'ebreak':
                w = 0x00100073
            else:
                raise ValueError(f'지원하지 않는 명령: {mn}')

            out.append((addr, w, ln, mn, ops_s))

        except Exception as e:
            raise ValueError(f'{ln}행 "{mn} {ops_s}": {e}') from None

    return out


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    src_path, hex_path = sys.argv[1], sys.argv[2]
    list_path = None
    if '--list' in sys.argv:
        list_path = sys.argv[sys.argv.index('--list') + 1]

    with open(src_path, encoding='utf-8') as f:
        src = f.read()

    items, labels = parse(src)
    words = encode(items, labels)

    with open(hex_path, 'w') as f:
        for _, w, _, _, _ in words:
            f.write(f'{w & 0xFFFFFFFF:08x}\n')

    if list_path:
        with open(list_path, 'w', encoding='utf-8') as f:
            f.write('addr      word      src\n')
            f.write('-' * 60 + '\n')
            for a, w, ln, mn, ops in words:
                f.write(f'{a:08x}  {w & 0xFFFFFFFF:08x}  {mn} {ops}\n')
            f.write('\n라벨:\n')
            for k, v in sorted(labels.items(), key=lambda x: x[1]):
                f.write(f'  {k:20s} 0x{v:08x} ({v})\n')

    print(f'{len(words)} 개 명령 → {hex_path}')


if __name__ == '__main__':
    main()
