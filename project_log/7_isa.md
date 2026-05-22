# ISA 指令扩展 — POPCNT / CLZ / CTZ

## 概述

在 RISC-V RV32I 基础上新增 3 条硬件加速指令，纯组合逻辑实现，单周期完成。

| 指令 | 编码 (funct7/funct3) | 功能 | 周期 |
|------|---------------------|------|------|
| POPCNT rd, rs1 | 0000001 / 001 | 统计 rs1 中 '1' 的个数 | 1 |
| CLZ rd, rs1 | 0000001 / 010 | 统计 rs1 前导零个数 | 1 |
| CTZ rd, rs1 | 0000001 / 011 | 统计 rs1 尾部零个数 | 1 |

## 创新点

1. **无冲突编码** — `custom_op = inst[25]` (funct7[0]) 区分自定义指令。RV32I 全部 R-type 的 funct7=0000000 或 0100000，bit[0] 均为 0。自定义设 bit[0]=1 实现零开销区分。

2. **POPCNT 分治法** — 5 级加法树: 2-bit→4-bit→8-bit→16-bit→32-bit，纯组合逻辑 O(logN)，比软件逐位统计快 ~32 倍。

3. **CLZ 二分查找** — 优先编码器，含 clz(0)=32 零值保护。从高 16 位逐级缩小搜索范围。

4. **CTZ 位反转** — `ctz(x) = clz(reverse_bits(x))`，复用 CLZ 逻辑，零额外组合电路。

5. **完全向后兼容** — 所有 RV32I 标准指令不受影响。新指令由 Decoder 自动译码，ALU 自动执行。

## 实现流程

```
Decoder.v:  inst[25]=1 → custom_op=1
  → R-type ALU 译码: funct3=001 → ALUControl=1010 (POPCNT)
                     funct3=010 → ALUControl=1011 (CLZ)
                     funct3=011 → ALUControl=1100 (CTZ)

ALU.v:  ALUControl=1010 → ALUResult = popcount(A)   [5级加法树]
        ALUControl=1011 → ALUResult = clz(A)         [二分查找]
        ALUControl=1100 → ALUResult = ctz(A)         [位反转+CLZ]
```

## 测试用例

`other/isa/isa_test.hex` — 63 条指令, 18 组边界值:

| 类别 | 测试数据 | 预期值 |
|------|---------|--------|
| POPCNT | 0x00000000, 0xFFFFFFFF, 0x00000001, 0x80000000, 0x33333333, 0x00FF00FF | 0, 32, 1, 1, 16, 16 |
| CLZ | 0x00000000, 0xFFFFFFFF, 0x80000000, 0x00000001, 0x0000FFFF, 0x00FF0000 | 32, 0, 0, 31, 16, 8 |
| CTZ | 0x00000000, 0xFFFFFFFF, 0x00000001, 0x80000000, 0x0000FF00, 0x00000010 | 32, 0, 0, 31, 8, 4 |

## 上板操作指南

### 步骤 1: 加载测试程序
```python
import serial, struct
ser = serial.Serial('COM3', 115200, timeout=0.5)

# 暂停CPU → 加载 isa_test.hex 到 IMem
ser.write(b'\x03'); ser.read(1)

with open('other/isa/isa_test.hex') as f:
    for i, line in enumerate(f):
        instr = int(line.strip(), 16)
        addr = i * 4
        ser.write(b'\x40' + struct.pack('>I', addr) + struct.pack('>I', instr))
        ser.read(1)

# 复位CPU (PC=0) → 单步执行全部63条指令 → 读DMem验证
ser.write(b'\x01'); ser.read(1)  # RESET
```

### 步骤 2: 验证结果 (读 DMem 0x0000-0x0043)
```python
expected = [0,32,1,1,16,16, 32,0,0,31,16,8, 32,0,0,31,8,4]
for i, exp in enumerate(expected):
    addr = i * 4
    ser.write(b'\x24' + struct.pack('>I', addr))
    resp = ser.read(5)
    actual = int.from_bytes(resp[1:5], 'big')
    status = "PASS" if actual == exp else f"FAIL (got {actual})"
    print(f"Test {i+1:2d}: expected {exp:2d}, {status}")
```

### 步骤 3: 验证清单
- [ ] 18 组测试全部 PASS
- [ ] CLZ(0) = 32 (零值保护正确)
- [ ] CTZ(0) = 32 (位反转+X)

### 软件 vs 硬件对比 (视频素材)
```
同是统计 0xFFFFFFFF 中 '1' 的个数 (32个):
  软件: li t0, 32; loop: andi+slli+srli+addi+bnez (约100条指令, ~100周期)
  硬件: POPCNT t0, t0 (1条指令, 1周期)
  加速比: ~100x
```
