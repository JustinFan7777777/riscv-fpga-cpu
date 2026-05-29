#!/usr/bin/env python3
"""Minimal RISC-V RV32I assembler for batch_test_pipeline.asm"""
import sys

REGS = {
    'x0':0,'x1':1,'x2':2,'x3':3,'x4':4,'x5':5,'x6':6,'x7':7,
    'x8':8,'x9':9,'x10':10,'x11':11,'x12':12,'x13':13,'x14':14,'x15':15,
    'x16':16,'x17':17,'x18':18,'x19':19,'x20':20,'x21':21,'x22':22,'x23':23,
    'x24':24,'x25':25,'x26':26,'x27':27,'x28':28,'x29':29,'x30':30,'x31':31,
    'zero':0,'ra':1,'sp':2,'gp':3,'tp':4,'t0':5,'t1':6,'t2':7,
    's0':8,'s1':9,'a0':10,'a1':11,'a2':12,'a3':13,'a4':14,'a5':15,
    'a6':16,'a7':17,'s2':18,'s3':19,'s4':20,'s5':21,'s6':22,'s7':23,
    's8':24,'s9':25,'s10':26,'s11':27,'t3':28,'t4':29,'t5':30,'t6':31,
}

DIRECTIVES = {'.text', '.globl', '.global', '.data', '.section', '.align',
              '.byte', '.half', '.word', '.string', '.asciz', '.equ', '.set'}

def reg(r):
    return REGS[r.strip()]

def imm(s):
    return int(s.strip(), 0) & 0xFFFFFFFF

def imm12(s):
    return int(s.strip(), 0) & 0xFFF

def sext12(v):
    return v if v < 0x800 else v - 0x1000

def encode_j(offset):
    if offset < 0: offset = (1 << 21) + offset
    offset &= 0x1FFFFF
    return ((offset >> 20) & 1) << 31 | ((offset >> 1) & 0x3FF) << 21 | ((offset >> 11) & 1) << 20 | ((offset >> 12) & 0xFF) << 12

def encode_b(offset):
    if offset < 0: offset = (1 << 13) + offset
    offset &= 0x1FFF
    return ((offset >> 12) & 1) << 31 | ((offset >> 11) & 1) << 7 | ((offset >> 5) & 0x3F) << 25 | ((offset >> 1) & 0xF) << 8

def assemble_line(line, labels, pc):
    """Return (instr_or_none, reloc_info_or_none) or None for empty/directive lines."""
    line = line.strip()
    if not line: return None
    if '#' in line: line = line[:line.index('#')]
    line = line.strip()
    if not line: return None

    # Label
    if ':' in line:
        lbl, _, rest = line.partition(':')
        labels[lbl.strip()] = pc
        line = rest.strip()
        if not line: return None

    # Directives
    if line.startswith('.'):
        return ('directive',)

    parts = line.replace(',', ' ').split()
    parts = [p for p in parts if p]
    if not parts: return None
    op = parts[0].lower()
    a = parts[1:]

    # R-type
    if op in ('add','sub','sll','slt','sltu','xor','srl','sra','or','and'):
        f3 = {'add':0,'sub':0,'sll':1,'slt':2,'sltu':3,'xor':4,'srl':5,'sra':5,'or':6,'and':7}[op]
        f7 = 0x20 if op == 'sub' else (0x20 if op == 'sra' else 0)
        return (f7 << 25) | (reg(a[2]) << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | 0x33

    # I-type ALU
    if op in ('addi','slti','sltiu','xori','ori','andi'):
        f3 = {'addi':0,'slti':2,'sltiu':3,'xori':4,'ori':6,'andi':7}[op]
        return (imm12(a[2]) << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | 0x13

    # I-type shift
    if op in ('slli','srli','srai'):
        f3 = {'slli':1,'srli':5,'srai':5}[op]
        f7 = 0x20 if op == 'srai' else 0
        shamt = int(a[2].strip(), 0) & 0x1F
        return (f7 << 25) | (shamt << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | 0x13

    # LW
    if op == 'lw':
        off, rs = a[1].split('('); rs = rs.replace(')', '')
        return (imm12(off) << 20) | (reg(rs) << 15) | (2 << 12) | (reg(a[0]) << 7) | 0x03

    # SW
    if op == 'sw':
        off, rs = a[1].split('('); rs = rs.replace(')', '')
        o = int(off.strip(), 0) & 0xFFF
        return ((o >> 5) << 25) | (reg(a[0]) << 20) | (reg(rs) << 15) | (2 << 12) | ((o & 0x1F) << 7) | 0x23

    # LUI (immediate is the U-immediate value, placed in bits[31:12])
    if op == 'lui':
        return ((imm(a[1]) << 12) & 0xFFFFF000) | (reg(a[0]) << 7) | 0x37

    # AUIPC (same U-immediate format as LUI)
    if op == 'auipc':
        return ((imm(a[1]) << 12) & 0xFFFFF000) | (reg(a[0]) << 7) | 0x17

    # JAL
    if op == 'jal':
        if a[1] in labels:
            return ('J', reg(a[0]), a[1])
        return encode_j(imm(a[1])) | (reg(a[0]) << 7) | 0x6F

    # JALR
    if op == 'jalr':
        off = imm(a[2]) if len(a) > 2 else 0
        return ((off & 0xFFF) << 20) | (reg(a[1]) << 15) | (0 << 12) | (reg(a[0]) << 7) | 0x67

    # Branches
    if op in ('beq','bne','blt','bge','bltu','bgeu'):
        f3 = {'beq':0,'bne':1,'blt':4,'bge':5,'bltu':6,'bgeu':7}[op]
        if a[2] in labels:
            return ('B', reg(a[0]), reg(a[1]), f3, a[2])
        return encode_b(imm(a[2])) | (reg(a[1]) << 20) | (reg(a[0]) << 15) | (f3 << 12) | 0x63

    # Pseudo: nop, mv, j, jr, li, ble, bgtz, beqz, bnez
    if op == 'nop':
        return 0x00000013
    if op == 'mv':
        return (reg(a[1]) << 15) | (0 << 12) | (reg(a[0]) << 7) | 0x13
    if op == 'j':
        if a[0] in labels: return ('J', 0, a[0])
        return encode_j(imm(a[0])) | 0x6F
    if op == 'jr':
        return (reg(a[0]) << 15) | (0 << 12) | (0 << 7) | 0x67
    if op == 'li':
        return (imm12(a[1]) << 20) | (reg(a[0]) << 7) | 0x13
    if op == 'ble':
        if a[2] in labels: return ('B', reg(a[1]), reg(a[0]), 5, a[2])
        return encode_b(imm(a[2])) | (reg(a[0]) << 20) | (reg(a[1]) << 15) | (5 << 12) | 0x63
    if op == 'bgtz':
        if a[1] in labels: return ('B', 0, reg(a[0]), 4, a[1])
        return encode_b(imm(a[1])) | (reg(a[0]) << 20) | (0 << 15) | (4 << 12) | 0x63
    if op == 'beqz':
        if a[1] in labels: return ('B', reg(a[0]), 0, 0, a[1])
        return encode_b(imm(a[1])) | (0 << 20) | (reg(a[0]) << 15) | (0 << 12) | 0x63
    if op == 'bnez':
        if a[1] in labels: return ('B', reg(a[0]), 0, 1, a[1])
        return encode_b(imm(a[1])) | (0 << 20) | (reg(a[0]) << 15) | (1 << 12) | 0x63

    # Handle _start: label with nothing after
    raise ValueError(f"Unknown: {op} {a} at pc=0x{pc:08X}")

def collect_labels_and_count(filepath):
    """Pass 1: scan lines, register labels, compute PC for each line."""
    with open(filepath, encoding='utf-8') as f:
        lines = f.readlines()

    labels = {}
    pc = 0
    for ln in lines:
        line = ln.strip()
        if not line: continue
        if '#' in line: line = line[:line.index('#')]
        line = line.strip()
        if not line: continue

        # Label only (e.g., "label:")
        if ':' in line:
            lbl, _, rest = line.partition(':')
            labels[lbl.strip()] = pc
            rest = rest.strip()
            if not rest: continue
            line = rest

        if line.startswith('.'): continue

        parts = line.replace(',', ' ').split()
        parts = [p for p in parts if p]
        if not parts: continue
        pc += 4

    return labels

def assemble(filepath):
    with open(filepath, encoding='utf-8') as f:
        lines = f.readlines()

    # Pass 1: collect all labels (forward references now OK)
    labels = collect_labels_and_count(filepath)

    # Pass 2: assemble with all labels known
    raw = []  # (pc, instr_or_tuple_or_directive)
    pc = 0
    for ln in lines:
        r = assemble_line(ln, labels, pc)
        if r is not None:
            raw.append((pc, r))
            if not isinstance(r, tuple) or r[0] != 'directive':
                pc += 4

    # Pass 3: resolve relocations
    out = {}
    for pc, r in raw:
        if isinstance(r, int):
            out[pc] = r
        elif isinstance(r, tuple) and r[0] == 'directive':
            pass
        elif isinstance(r, tuple) and r[0] == 'J':
            _, rd, target = r
            off = labels[target] - pc
            out[pc] = encode_j(off) | (rd << 7) | 0x6F
        elif isinstance(r, tuple) and r[0] == 'B':
            _, rs1, rs2, f3, target = r
            off = labels[target] - pc
            out[pc] = encode_b(off) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | 0x63

    return out, labels

def write_hex(resolved, outpath, max_pc=None):
    if max_pc is None:
        max_pc = max(resolved.keys())
    n = (max_pc // 4) + 1
    with open(outpath, 'w') as f:
        for i in range(n):
            f.write(f"{resolved.get(i*4, 0):08X}\n")

if __name__ == '__main__':
    asm_path = sys.argv[1] if len(sys.argv) > 1 else 'assembly/batch_test_pipeline.asm'
    hex_path = sys.argv[2] if len(sys.argv) > 2 else 'assembly/batch_test_pipeline.hex'

    resolved, labels = assemble(asm_path)
    print(f"Instructions: {len(resolved)}, Labels: {len(labels)}")
    write_hex(resolved, hex_path)
    print(f"Written to {hex_path}")
