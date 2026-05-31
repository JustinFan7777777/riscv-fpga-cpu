# ISA 硬件加速指令 — Bonus 演示指南

> ISA 指令扩展 | 分值: 4 | 状态: 完成
> 文件: ALU.v (3 个组合逻辑 function), Decoder.v (custom_op 译码), other/isa/isa_test.asm

---

## 一、功能介绍

在 RISC-V RV32I 基础上新增 3 条硬件加速指令，纯组合逻辑，单周期完成：

| 指令 | 编码 (funct7/funct3) | 功能 | 周期 |
|------|---------------------|------|------|
| POPCNT rd, rs1 | 0000001 / 001 | 统计 rs1 中 '1' 的个数 | 1 |
| CLZ rd, rs1 | 0000001 / 010 | 统计 rs1 前导零个数 | 1 |
| CTZ rd, rs1 | 0000001 / 011 | 统计 rs1 尾部零个数 | 1 |

---

## 二、关键技术 (指代码讲)

### 2.1 无冲突编码 — Decoder.v

```verilog
wire custom_op = inst[25];  // funct7 第 0 位
// RV32I 全部标准 R-type: funct7=0000000 或 0100000, bit[0] 均为 0
// 自定义指令: funct7=0000001, bit[0]=1 → 零开销区分
```

**ALU 译码 (Decoder.v):**
```verilog
3'b001: alucontrol_r = custom_op ? 4'b1010 : 4'b0101;  // POPCNT : SLL
3'b010: alucontrol_r = custom_op ? 4'b1011 : 4'b1000;  // CLZ    : SLT
3'b011: alucontrol_r = custom_op ? 4'b1100 : 4'b1001;  // CTZ    : SLTU
```

### 2.2 POPCNT — 分治法 5 级加法树 (ALU.v)

```
Step 1: 每 2-bit 一组 popcount → t = (x&0x55555555) + ((x>>1)&0x55555555)
Step 2: 每 4-bit 一组 → t = (t&0x33333333) + ((t>>2)&0x33333333)
Step 3: 每 8-bit 一组 → t = (t&0x0F0F0F0F) + ((t>>4)&0x0F0F0F0F)
Step 4: 每 16-bit 一组 → t = (t&0x00FF00FF) + ((t>>8)&0x00FF00FF)
Step 5: 32-bit 最终结果 → t = (t&0x0000FFFF) + ((t>>16)&0x0000FFFF)
```

5 级纯组合逻辑，O(log₂32)=5，无时钟延迟。

### 2.3 CLZ — 二分查找优先编码器 (ALU.v)

```
if (x == 0) return 32;     // 零值特殊处理
n = 0;
if (x[31:16] == 0) { n+=16; x<<=16; }  // 高 16 位全零 → 前导至少 16 个零
if (x[31:24] == 0) { n+=8;  x<<=8;  }  // 高 8 位全零
if (x[31:28] == 0) { n+=4;  x<<=4;  }  // 高 4 位全零
if (x[31:30] == 0) { n+=2;  x<<=2;  }  // 高 2 位全零
if (x[31]    == 0) { n+=1;           }  // 最高位为零
return n;
```

### 2.4 CTZ — 位反转 + CLZ (ALU.v)

```verilog
ctz(x) = clz(reverse_bits(x))  // 复用 CLZ 逻辑, 零额外电路
```

---

## 三、视频演示流程

**1. 代码走读:**
- ALU.v: popcount/clz/ctz 三个 function 的实现
- Decoder.v: custom_op 区分机制 + ALU 译码表修改

**2. 测试结果展示:**
- 加载 other/isa/isa_test.asm (63 条指令, 18 组边界值)
- 通过 UART Debug 读取 DMem 验证结果
- 18 组全部 PASS: 全零、全一、单比特、随机值

**3. 软件 vs 硬件对比 (关键画面):**

| 统计 0xFFFFFFFF 中 '1' 的个数 (=32) |
|---|
| 软件: ~100 条指令 (循环 32 次, 逐位检查+累加), ~100 周期 |
| 硬件: 1 条指令 `POPCNT t0, t0`, 1 周期 |
| **加速比: ~100x** |

---

## 四、创新点

1. **funct7[0] 零开销区分** — 所有标准 RV32I R-type 的 funct7[0]=0, 自定义=1
2. **POPCNT 分治法** — 5 级加法树, O(logN) 组合逻辑, 比软件快 ~100 倍
3. **CTZ 复用 CLZ** — `ctz(x) = clz(reverse_bits(x))`, 零额外电路
4. **完全向后兼容** — 所有 RV32I 标准指令不受影响
