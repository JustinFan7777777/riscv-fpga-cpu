# 软件乘法 — Bonus 演示指南

> 软硬件协同示例 (溢出展示) | 文件: other/mul/soft_mul.asm (62 条指令)

---

## 一、功能介绍

纯 RV32I 汇编实现 32-bit 乘法子程序。RV32I 无硬件乘法指令，用移位+加法模拟乘法。包含 `multiply` (无符号) 和 `multiply_signed` (有符号) 两个独立子程序。

**API:**
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

---

## 二、算法讲解

**无符号乘法 — 移位相加:**
```
multiplier = a1, multiplicand = a0, result = 0
循环 32 次:
  if (multiplier[0] == 1) result += multiplicand
  multiplicand <<= 1
  multiplier >>= 1
返回 result
```

**有符号乘法:** 取两操作数绝对值 → 无符号乘法 → 按符号异或结果恢复正负号

---

## 三、视频演示 (简短, ~20s)

- 展示 soft_mul.asm 核心循环代码
- "8 组测试全部通过: 正×正、零×正、负×正、负×负、溢出截断"
- 对比: "同样 3×5, 软件 ~200 周期, 硬件 MUL 1 周期, ~200x 加速比"

---

## 四、创新点

1. **纯移位加法** — 无硬件乘法器, 32 轮迭代
2. **独立可复用子程序** — `jal ra` 调用, a0/a1 传参, a0 返回
3. **软硬件对比** — 直观展示 ASIC 硬件加速的价值
