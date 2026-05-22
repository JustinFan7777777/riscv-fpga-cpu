# 软件乘法 — 移位相加实现

## 概述

纯 RV32I 汇编实现的 32-bit 有符号/无符号乘法子程序。在无 M 扩展硬件乘法器的 CPU 上用移位+加法模拟乘法，作为软硬件协同设计的补充示例。

## 文件

```
other/mul/soft_mul.asm    # 汇编源码 (62条指令, 含注释)
other/mul/soft_mul.hex    # 编译后机器码
```

## 创新点

1. **逐位乘加** — 检查乘数最低位: 若=1 则累加被乘数。被乘数每轮左移 (×2)，乘数右移 (÷2)。32 轮完成。

2. **有符号支持** — 取绝对值执行无符号乘法，根据两操作数符号异或结果恢复正负号。

3. **O(n) 复杂度** — n=32，最坏约 200 条指令。软件 vs 硬件对比:
   ```
   3 × 5 = 15:
     软件: ~200 周期 (移位相加)
     硬件 (M 扩展 MUL): 1 周期
     加速比: ~200x
   ```

4. **独立子程序** — `multiply` (无符号) 和 `multiply_signed` (有符号) 可被任何汇编程序 `jal ra` 调用，参数在 a0/a1，结果在 a0。

## 使用方法

```asm
# 无符号: 3 × 5
li a0, 3
li a1, 5
jal ra, multiply       # a0 = 15

# 有符号: -4 × 7
li a0, -4
li a1, 7
jal ra, multiply_signed  # a0 = -28
```

## 自测试 (8 组)

| # | 操作数 | 预期结果 |
|---|--------|---------|
| 1 | 3 × 5 | 15 |
| 2 | 0 × 100 | 0 |
| 3 | 65535 × 1 | 65535 |
| 4 | -4 × 7 | -28 |
| 5 | -3 × -6 | 18 |
| 6 | 100 × 200 | 20000 |
| 7 | 65536 × 65536 | 0 (溢出, 低32位) |
| 8 | 7 × -4 | -28 |

## 上板操作指南

### 步骤 1: 加载测试程序
```python
import serial, struct
ser = serial.Serial('COM3', 115200, timeout=0.5)
ser.write(b'\x03'); ser.read(1)  # HALT

with open('other/mul/soft_mul.hex') as f:
    for i, line in enumerate(f):
        instr = int(line.strip(), 16)
        ser.write(b'\x40' + struct.pack('>I', i*4) + struct.pack('>I', instr))
        ser.read(1)
```

### 步骤 2: 运行并验证
```python
ser.write(b'\x01'); ser.read(1)  # RESET (PC=0)
ser.write(b'\x02'); ser.read(1)  # RUN
# 等待执行完成 (62条指令, 约5μs @12.5MHz)

# 读 DMem 验证 8 组测试结果
expected = [15, 0, 65535, -28 & 0xFFFFFFFF, 18, 20000, 0, -28 & 0xFFFFFFFF]
for i, exp in enumerate(expected):
    ser.write(b'\x24' + struct.pack('>I', i*4))
    resp = ser.read(5)
    actual = int.from_bytes(resp[1:5], 'big')
    print(f"Test {i+1}: {'PASS' if actual == exp else f'FAIL (got {actual}, exp {exp})'}")
```

### 步骤 3: 验证清单
- [ ] 8 组测试全部 PASS
- [ ] 无符号乘法正确
- [ ] 有符号乘法正确 (正×正, 负×正, 负×负)
- [ ] 溢出截断正确 (0x10000×0x10000 低32位=0)
