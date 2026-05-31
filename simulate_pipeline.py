#!/usr/bin/env python3
"""
RISC-V RV32I 五级流水线周期精确模拟器
=========================================
用于验证 batch_test_pipeline.txt 的正确性，无需 Vivado。

用法:
    python3 simulate_pipeline.py [--nofwd] [--hex assembly/batch_test_pipeline.txt]

    --nofwd  : 关闭 forwarding，模拟纯 NOP 方案
    默认     : 开启 forwarding + load-use stall（模拟当前硬件）
"""

import sys
from dataclasses import dataclass, field
from typing import Optional

# ============================================================
# RISC-V 指令解码
# ============================================================

REGS = ['x0','ra','sp','gp','tp','t0','t1','t2','s0','s1',
        'a0','a1','a2','a3','a4','a5','a6','a7',
        's2','s3','s4','s5','s6','s7','s8','s9','s10','s11',
        't3','t4','t5','t6']

OPCODES = {
    0x37: 'LUI',    0x17: 'AUIPC',  0x6F: 'JAL',
    0x67: 'JALR',   0x63: 'BRANCH', 0x03: 'LOAD',
    0x23: 'STORE',  0x13: 'OP_IMM', 0x33: 'OP',
}

FUNCT3_NAME = {0:'ADD',1:'SLL',2:'SLT',3:'SLTU',4:'XOR',5:'SRL',6:'OR',7:'AND'}

def decode_inst(inst: int):
    """Return dict with all decoded fields."""
    if inst == 0:
        return {'name': 'NOP', 'rd': 0, 'rs1': 0, 'rs2': 0, 'funct3': 0, 'funct3_raw': 0,
                'funct7': 0, 'imm': 0, 'is_load': False, 'is_store': False,
                'is_branch': False, 'is_jump': False, 'is_jalr': False,
                'is_alu_r': False, 'is_alu_i': False, 'is_lui': False, 'is_auipc': False,
                'alu_control': 0, 'regwrite': False, 'alusrc': False,
                'memtoreg': False, 'memwrite': False, 'memread': False}
    opc = inst & 0x7F
    rd = (inst >> 7) & 0x1F
    f3 = (inst >> 12) & 0x07
    rs1 = (inst >> 15) & 0x1F
    rs2 = (inst >> 20) & 0x1F
    f7 = (inst >> 25) & 0x7F

    # Immediates
    imm_i_raw = (inst >> 20) & 0xFFF
    imm_i = imm_i_raw if imm_i_raw < 0x800 else imm_i_raw - 0x1000
    imm_s_raw = ((inst >> 25) << 5) | ((inst >> 7) & 0x1F)
    imm_s = imm_s_raw if imm_s_raw < 0x800 else imm_s_raw - 0x1000
    imm_b_raw = ((inst >> 31) << 12) | (((inst >> 7) & 1) << 11) | \
                (((inst >> 25) & 0x3F) << 5) | (((inst >> 8) & 0xF) << 1)
    imm_b = imm_b_raw if imm_b_raw < 0x1000 else imm_b_raw - 0x2000
    imm_u = inst & 0xFFFFF000
    imm_j_raw = ((inst >> 31) << 20) | (((inst >> 12) & 0xFF) << 12) | \
                (((inst >> 20) & 1) << 11) | (((inst >> 21) & 0x3FF) << 1)
    imm_j = imm_j_raw if imm_j_raw < 0x100000 else imm_j_raw - 0x200000

    name = OPCODES.get(opc, 'UNKNOWN')
    is_load = (opc == 0x03)
    is_store = (opc == 0x23)
    is_branch = (opc == 0x63)
    is_jump = (opc == 0x6F)
    is_jalr = (opc == 0x67)
    is_alu_r = (opc == 0x33)
    is_alu_i = (opc == 0x13)
    is_lui = (opc == 0x37)
    is_auipc = (opc == 0x17)

    if opc == 0x63:
        imm = imm_b
    elif opc == 0x6F:
        imm = imm_j
    elif opc in (0x37, 0x17):
        imm = imm_u
    elif opc == 0x23:
        imm = imm_s
    else:
        imm = imm_i

    alu_ctrl = 0
    if is_alu_r:
        alu_map = {0: (0 if f7 == 0 else 1), 1: 5, 2: 8, 3: 9, 4: 4, 5: (6 if f7 == 0 else 7), 6: 3, 7: 2}
        alu_ctrl = alu_map.get(f3, 0)
    elif is_alu_i:
        alu_map_i = {0: 0, 1: 5, 2: 8, 3: 9, 4: 4, 5: (6 if f7 == 0 else 7), 6: 3, 7: 2}
        alu_ctrl = alu_map_i.get(f3, 0)
    elif is_load or is_store or is_jump or is_jalr or is_lui or is_auipc:
        alu_ctrl = 0
    elif is_branch:
        alu_ctrl = 1

    # Control signals (matching Decoder.v)
    regwrite = is_alu_r or is_alu_i or is_load or is_lui or is_auipc or is_jump or is_jalr
    alusrc = is_alu_i or is_load or is_store or is_lui or is_auipc or is_jump or is_jalr
    memtoreg = is_load
    memwrite = is_store

    return {'name': name, 'rd': rd, 'rs1': rs1, 'rs2': rs2, 'funct3': f3, 'funct3_raw': f3,
            'funct7': f7, 'imm': imm, 'is_load': is_load, 'is_store': is_store,
            'is_branch': is_branch, 'is_jump': is_jump, 'is_jalr': is_jalr,
            'is_alu_r': is_alu_r, 'is_alu_i': is_alu_i, 'is_lui': is_lui, 'is_auipc': is_auipc,
            'alu_control': alu_ctrl, 'regwrite': regwrite, 'alusrc': alusrc,
            'memtoreg': memtoreg, 'memwrite': memwrite, 'memread': is_load}


# ============================================================
# Pipeline 数据结构
# ============================================================

@dataclass
class IFID:
    pc: int = 0
    inst: int = 0
    pcplus4: int = 0

@dataclass
class IDEX:
    pc: int = 0
    inst: int = 0
    pcplus4: int = 0
    rs1_val: int = 0
    rs2_val: int = 0
    imm: int = 0
    rs1_addr: int = 0
    rs2_addr: int = 0
    rd_addr: int = 0
    regwrite: bool = False
    alusrc: bool = False
    memtoreg: bool = False
    memwrite: bool = False
    branch: bool = False
    jump: bool = False
    jalrsrc: bool = False
    alucontrol: int = 0
    funct3: int = 0
    lui: bool = False
    auipc: bool = False
    memread: bool = False  # = memtoreg for load-use detection

@dataclass
class EXMEM:
    aluresult: int = 0
    writedata: int = 0
    rd_addr: int = 0
    regwrite: bool = False
    memtoreg: bool = False
    memwrite: bool = False

@dataclass
class MEMWB:
    readdata: int = 0
    aluresult: int = 0
    rd_addr: int = 0
    regwrite: bool = False
    memtoreg: bool = False


# ============================================================
# ALU
# ============================================================

def alu_compute(a: int, b: int, ctrl: int) -> int:
    b32 = b & 0xFFFFFFFF
    if ctrl == 0:   return (a + b) & 0xFFFFFFFF       # ADD
    elif ctrl == 1: return (a - b) & 0xFFFFFFFF       # SUB
    elif ctrl == 2: return a & b                       # AND
    elif ctrl == 3: return a | b                       # OR
    elif ctrl == 4: return a ^ b                       # XOR
    elif ctrl == 5: return (a << (b32 & 0x1F)) & 0xFFFFFFFF  # SLL
    elif ctrl == 6: return (a & 0xFFFFFFFF) >> (b32 & 0x1F)   # SRL
    elif ctrl == 7:  # SRA
        sa = b32 & 0x1F
        if a & 0x80000000:
            return ((a >> sa) | ((0xFFFFFFFF << (32 - sa)) & 0xFFFFFFFF)) & 0xFFFFFFFF
        return (a >> sa) & 0xFFFFFFFF
    elif ctrl == 8:  # SLT
        sa = a if a < 0x80000000 else a - 0x100000000
        sb = b if b < 0x80000000 else b - 0x100000000
        return 1 if sa < sb else 0
    elif ctrl == 9: return 1 if (a & 0xFFFFFFFF) < (b & 0xFFFFFFFF) else 0
    return 0


# ============================================================
# 流水线 CPU 模拟器
# ============================================================

class PipelineCPU:
    def __init__(self, hex_path: str, forwarding: bool = True):
        self.forwarding = forwarding
        self.pc_reset = 0x00004000

        # 指令内存
        self.imem = [0] * 2048
        with open(hex_path) as f:
            for i, line in enumerate(f):
                line = line.strip()
                if line:
                    self.imem[i] = int(line, 16)

        # 数据内存
        self.dmem = [0] * 65536

        # 寄存器堆
        self.regfile = [0] * 32

        # 流水线寄存器
        self.ifid = IFID()
        self.idex = IDEX()
        self.exmem = EXMEM()
        self.memwb = MEMWB()

        # PC
        self.pc_reg = self.pc_reset       # 超前取指PC
        self.pc_prev = self.pc_reset      # 对齐 inst 的 PC
        self.inst_reg = 0                  # BRAM 寄存器读 (1 拍延迟)

        # 统计
        self.cycles = 0
        self.inst_count = 0
        self.stalls = 0
        self.flushes = 0

        # 仿真控制
        self.trace = []

    def _signed(self, v: int) -> int:
        return v if v < 0x80000000 else v - 0x100000000

    def reset(self):
        self.regfile = [0] * 32
        self.ifid = IFID()
        self.idex = IDEX()
        self.exmem = EXMEM()
        self.memwb = MEMWB()
        # 模拟 reset_stall 后的状态: pc 已前进 1 拍, inst_reg 已加载第一条指令
        self.pc_reg = self.pc_reset + 4   # PC 已前进到 0x4004
        self.pc_prev = self.pc_reset       # 对应当前 inst_reg 的 PC
        self.inst_reg = self.imem[(self.pc_reset >> 2) & 0x7FF] & 0xFFFFFFFF
        self.cycles = 0
        self.inst_count = 0
        self.stalls = 0
        self.flushes = 0
        self.trace = []

    def cycle(self):
        """执行一个时钟周期 (五级流水线并行)"""
        c = self.cycles

        # ================= WB 阶段 =================
        wb_wd3 = self.memwb.readdata if self.memwb.memtoreg else self.memwb.aluresult
        if self.memwb.regwrite and self.memwb.rd_addr != 0:
            self.regfile[self.memwb.rd_addr] = wb_wd3

        # ================= MEM 阶段 =================
        mem_addr = self.exmem.aluresult & 0xFFFF
        if self.exmem.memwrite:
            # STORE
            byte_addr = mem_addr & 0xFFFC
            word_idx = byte_addr >> 2
            self.dmem[word_idx] = self.exmem.writedata & 0xFFFFFFFF
            mem_readdata = 0
        else:
            # LOAD (or no-op)
            word_idx = mem_addr >> 2
            mem_readdata = self.dmem[word_idx] if word_idx < len(self.dmem) else 0

        # ================= EX 阶段 =================
        # --- forwarding mux ---
        if self.forwarding:
            # Forward A
            fwd_a = 0  # 0=rs1, 1=EX/MEM, 2=MEM/WB
            if self.exmem.regwrite and not self.exmem.memtoreg and self.exmem.rd_addr != 0 \
               and self.exmem.rd_addr == self.idex.rs1_addr:
                fwd_a = 1
            elif self.memwb.regwrite and self.memwb.rd_addr != 0 \
                 and self.memwb.rd_addr == self.idex.rs1_addr \
                 and not (self.exmem.regwrite and not self.exmem.memtoreg \
                          and self.exmem.rd_addr != 0 \
                          and self.exmem.rd_addr == self.idex.rs1_addr):
                fwd_a = 2

            # Forward B
            fwd_b = 0
            if self.exmem.regwrite and not self.exmem.memtoreg and self.exmem.rd_addr != 0 \
               and self.exmem.rd_addr == self.idex.rs2_addr:
                fwd_b = 1
            elif self.memwb.regwrite and self.memwb.rd_addr != 0 \
                 and self.memwb.rd_addr == self.idex.rs2_addr \
                 and not (self.exmem.regwrite and not self.exmem.memtoreg \
                          and self.exmem.rd_addr != 0 \
                          and self.exmem.rd_addr == self.idex.rs2_addr):
                fwd_b = 2

            exmem_val = self.exmem.aluresult
            memwb_val = self.memwb.readdata if self.memwb.memtoreg else self.memwb.aluresult
            alu_a = memwb_val if fwd_a == 2 else (exmem_val if fwd_a == 1 else self.idex.rs1_val)
            alu_b_raw = memwb_val if fwd_b == 2 else (exmem_val if fwd_b == 1 else self.idex.rs2_val)
        else:
            alu_a = self.idex.rs1_val
            alu_b_raw = self.idex.rs2_val

        # LUI/AUIPC override
        if self.idex.lui:
            alu_a = 0
        elif self.idex.auipc:
            alu_a = self.idex.pc

        alu_b = self.idex.imm if self.idex.alusrc else alu_b_raw
        alu_raw = alu_compute(alu_a, alu_b, self.idex.alucontrol)

        # JAL/JALR write-back is PC+4
        ex_result = self.idex.pcplus4 if (self.idex.jump or self.idex.jalrsrc) else alu_raw

        # Branch/jump target
        branch_target = (self.idex.pc + self.idex.imm) & 0xFFFFFFFF
        jalr_sum = (alu_a + self.idex.imm) & 0xFFFFFFFF
        jalr_target = jalr_sum & 0xFFFFFFFE

        # Branch condition
        branch_taken = False
        if self.idex.branch:
            f3 = self.idex.funct3
            if f3 == 0:   branch_taken = (alu_a == alu_b)
            elif f3 == 1: branch_taken = (alu_a != alu_b)
            elif f3 == 4: branch_taken = (self._signed(alu_a) < self._signed(alu_b))
            elif f3 == 5: branch_taken = (self._signed(alu_a) >= self._signed(alu_b))
            elif f3 == 6: branch_taken = (alu_a < alu_b)
            elif f3 == 7: branch_taken = (alu_a >= alu_b)

        jump_taken = self.idex.jump
        jalr_taken = self.idex.jalrsrc
        ctrl_flush = branch_taken or jump_taken or jalr_taken

        # Write data for stores = rs2 value (forwarded)
        ex_writedata = alu_b_raw

        # --- Load-Use stall ---
        load_use = False
        if self.forwarding:
            if self.idex.memread and self.idex.rd_addr != 0 and \
               (self.idex.rd_addr == self.ifid.inst and False):  # simulated by checking IDs
                pass
            # Proper load-use: instruction in EX is load, instruction in ID reads loaded reg
            id_inst = self.ifid.inst
            id_rs1 = (id_inst >> 15) & 0x1F
            id_rs2 = (id_inst >> 20) & 0x1F
            if self.idex.memread and self.idex.rd_addr != 0 and \
               (self.idex.rd_addr == id_rs1 or self.idex.rd_addr == id_rs2):
                load_use = True

        stall = load_use and self.forwarding

        # ================= ID 阶段 =================
        id_inst = self.ifid.inst
        d = decode_inst(id_inst)

        # RegFile read (with bypass for same-cycle WB write)
        def rf_read(addr):
            if addr == 0: return 0
            if self.memwb.regwrite and self.memwb.rd_addr == addr:
                return self.memwb.readdata if self.memwb.memtoreg else self.memwb.aluresult
            return self.regfile[addr]

        rs1_val = rf_read(d['rs1'])
        rs2_val = rf_read(d['rs2'])

        # ================= IF 阶段 =================
        # BRAM 寄存器读: 1 拍延迟, inst_raw 将在周期结束时锁存到 inst_reg
        inst_raw = self.imem[(self.pc_reg >> 2) & 0x7FF] if self.pc_reg < 0x6000 else 0

        flush_ifid = ctrl_flush

        # Next PC
        take_branch = branch_taken or jump_taken or jalr_taken
        if jalr_taken:
            target = jalr_target
        elif jump_taken:
            target = branch_target
        else:
            target = branch_target

        if stall:
            next_pc = self.pc_reg
        elif take_branch:
            next_pc = target
        else:
            next_pc = (self.pc_reg + 4) & 0xFFFFFFFF

        # ================= 更新流水线寄存器 =================
        # MEM/WB ← EX/MEM
        new_memwb = MEMWB(
            readdata=mem_readdata,
            aluresult=self.exmem.aluresult,
            rd_addr=self.exmem.rd_addr,
            regwrite=self.exmem.regwrite,
            memtoreg=self.exmem.memtoreg,
        )

        # EX/MEM ← ID/EX (hardware never flushes EX/MEM — 仅 flush IF/ID 和 ID/EX)
        new_exmem = EXMEM(
            aluresult=ex_result,
            writedata=ex_writedata,
            rd_addr=self.idex.rd_addr,
            regwrite=self.idex.regwrite,
            memtoreg=self.idex.memtoreg,
            memwrite=self.idex.memwrite,
        )

        # ID/EX ← ID (or NOP if ctrl_flush or stall)
        if ctrl_flush:
            new_idex = IDEX()
        elif stall:
            new_idex = self.idex
        else:
            new_idex = IDEX(
                pc=self.ifid.pc, inst=self.ifid.inst, pcplus4=self.ifid.pcplus4,
                rs1_val=rs1_val, rs2_val=rs2_val, imm=d['imm'],
                rs1_addr=d['rs1'], rs2_addr=d['rs2'], rd_addr=d['rd'],
                regwrite=d['regwrite'], alusrc=d['alusrc'],
                memtoreg=d['memtoreg'], memwrite=d['memwrite'],
                branch=d['is_branch'],
                jump=d['is_jump'], jalrsrc=d['is_jalr'],
                alucontrol=d['alu_control'], funct3=d['funct3_raw'],
                lui=d['is_lui'], auipc=d['is_auipc'], memread=d['memread'],
            )

        # IF/ID ← IF (or NOP if flush). IF/ID 捕获 inst_reg (BRAM 1拍延迟读取的值)
        if flush_ifid:
            new_ifid = IFID()
            self.flushes += 1
        elif stall:
            new_ifid = self.ifid
        else:
            new_ifid = IFID(
                pc=self.pc_prev,
                inst=self.inst_reg,  # 用上一拍锁存的值, 与 pc_prev 对齐
                pcplus4=(self.pc_prev + 4) & 0xFFFFFFFF,
            )

        # BRAM 寄存器读: inst_reg 锁存当前拍读取的值, 下一拍出现在 IF/ID
        new_inst_reg = inst_raw

        # PC update
        new_pc_prev = self.pc_reg
        new_pc_reg = next_pc

        # ================= 提交更新 =================
        self.memwb = new_memwb
        self.exmem = new_exmem
        self.idex = new_idex
        self.ifid = new_ifid
        self.inst_reg = new_inst_reg
        self.pc_reg = new_pc_reg
        self.pc_prev = new_pc_prev

        if not stall:
            self.inst_count += 1
        else:
            self.stalls += 1

        self.cycles += 1

        # Trace for debugging
        if id_inst != 0 or self.idex.inst != 0:
            self.trace.append((c, self.ifid.pc, id_inst, d['name'], d['rd'],
                               self.idex.regwrite, ctrl_flush, stall))

    def run_until_store(self, max_cycles=5000):
        """Run until a SW to 0x400C completes, then return the stored value."""
        for _ in range(max_cycles):
            self.cycle()
            # Check if sw to 0x400C happened
            # sw reaches MEM stage → data is in dmem
            # After MEM stage, data is committed
            pass
        return None

    def run_test(self, case_id: int, op_a: int, op_b: int, max_cycles=10000):
        """Run one test case and return the result."""
        self.reset()
        # Write test inputs to data memory
        self.dmem[0x4000 >> 2] = case_id & 0xFFFFFFFF
        self.dmem[0x4004 >> 2] = op_a & 0xFFFFFFFF
        self.dmem[0x4008 >> 2] = op_b & 0xFFFFFFFF
        self.dmem[0x400C >> 2] = 0xDEADBEEF

        for _ in range(max_cycles):
            self.cycle()
            # sw writes in MEM stage during the cycle
            # After the cycle, dmem is updated. Check if sw to 0x400C just happened.
            if self.dmem[0x400C >> 2] != 0xDEADBEEF:
                return self.dmem[0x400C >> 2]

        return self.dmem[0x400C >> 2]


# ============================================================
# 测试用例定义 (从 diff 测试提取)
# ============================================================

TEST_CASES = [
    # (case_id, op_a, op_b, expected)
    # Case 0: AND
    (0, 0x00000F0F, 0x00001234, 0x00000204),
    (0, 0xFFFFFFFF, 0x00001234, 0x00001234),
    # Case 1: SLL
    (1, 0x12481248, 0x00000004, 0x24812480),
    (1, 0x00000001, 0x0000002D, 0x00002000),
    # Case 2: SRA
    (2, 0x71240000, 0x00000018, 0x00000071),
    (2, 0x81231234, 0x00000024, 0xF8123123),
    # Case 3: LUI + ADD
    (3, 0x10000000, 0x00000000, 0x22345000),
    (3, 0x00000001, 0x00000000, 0x12345001),
    # Case 4: JAL + AUIPC
    (4, 0x00000000, 0x00000000, 0x12345000),
    (4, 0x00000010, 0x00000000, 0x12345010),
    # Case 5: JAL + JALR
    (5, 0x00000005, 0x00000006, 0x0000000B),
    (5, 0x00000001, 0x00000002, 0x00000003),
    # Case 6: Fibonacci
    (6, 0x00000001, 0x00000000, 0x00000001),
    (6, 0x00000002, 0x00000000, 0x00000001),
    (6, 0x00000003, 0x00000000, 0x00000002),
    (6, 0x00000004, 0x00000000, 0x00000003),
    # Case 7: Popcount
    (7, 0x000000C1, 0x00000000, 0x00000003),
    (7, 0x000000F8, 0x00000000, 0x00000005),
    # Case 8: IEEE 754 type
    (8, 0x00008000, 0x00000000, 0x00000000),
    (8, 0x00000000, 0x00000000, 0x00000000),
    (8, 0x00007C00, 0x00000000, 0x00000001),
    (8, 0x0000FC00, 0x00000000, 0x00000001),
    (8, 0x0000FC01, 0x00000000, 0x00000002),
    (8, 0x00002026, 0x00000000, 0x00000003),
    (8, 0x0000C202, 0x00000000, 0x00000003),
    (8, 0x00000003, 0x00000000, 0x00000004),
    (8, 0x000080E1, 0x00000000, 0x00000004),
    # Case 9: Float Q3.4
    (9, 0x00003C00, 0x00000000, 0x00000010),
    (9, 0x00003E00, 0x00000000, 0x00000018),
    (9, 0x00004200, 0x00000000, 0x00000030),
    (9, 0x0000C400, 0x00000000, 0x000000C0),
    (9, 0x00004240, 0x00000000, 0x00000032),
    (9, 0x0000BF00, 0x00000000, 0x000000E4),
]


def run_all_tests(cpu: PipelineCPU, verbose: bool = True):
    passed = 0
    total = len(TEST_CASES)
    for i, (cid, opa, opb, expected) in enumerate(TEST_CASES):
        result = cpu.run_test(cid, opa, opb)
        ok = (result == expected)
        if ok:
            passed += 1
        if verbose:
            status = "PASS" if ok else "FAIL"
            print(f"  [{i+1:2d}/{total}] case={cid} ops=[0x{opa:08X}, 0x{opb:08X}] "
                  f"=> 0x{result:08X} (expect 0x{expected:08X}) {status}")
    print(f"\n====== Result: {passed}/{total} passed ======")
    return passed == total


if __name__ == '__main__':
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--nofwd', action='store_true', help='Disable forwarding (pure NOP mode)')
    ap.add_argument('--hex', default='assembly/batch_test_pipeline.txt')
    ap.add_argument('--single', action='store_true', help='Use single-cycle hex')
    args = ap.parse_args()

    if args.single:
        args.hex = 'assembly/batch_test.txt'

    fwd = not args.nofwd
    mode = "NOP-only (no forwarding)" if args.nofwd else "forwarding + load-use stall"
    print(f"Pipeline Simulator")
    print(f"  Hex: {args.hex}")
    print(f"  Mode: {mode}")
    print()

    cpu = PipelineCPU(args.hex, forwarding=fwd)
    run_all_tests(cpu)
