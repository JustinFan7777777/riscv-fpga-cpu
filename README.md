# 基于 RISC-V RV32I 的单周期 CPU 设计与实现

> 计算机组成原理 CPU Project — 小组 Tue34_w_10

---

## 成员

| 姓名 | 学号 | 负责工作 |
|------|------|---------|
| 范晓乐 | 12412307 | Verilog 设计、VGA 控制器、Pipeline、项目协调 |
| 刘一骏 | 12411922 | 汇编编码、RARS 模拟验证 |
| 陈俊希 | 12411025 | Vivado 综合、上板测试、Difftest 验证 |

---

## 项目概述

在 EGO1 (XC7A35T) 开发板上实现 RISC-V RV32I 单周期 CPU，支持 31 条指令，通过 Difftest 33/33 全部通过。

### Bonus 功能

| Bonus | 分值 | 说明 |
|-------|------|------|
| VGA 文本显示 | 5 | 640×480@60Hz, 80×30 彩色字符 |
| 贪吃蛇游戏 | 5 | 纯汇编, MMIO 按键 + VGA 渲染 |
| 五级流水线 | 6 | IF→ID→EX→MEM→WB, 转发+暂停+冲刷 |
| ISA 扩展 | 4 | POPCNT / CLZ / CTZ 硬件加速指令 |
| 可视化工具 | 2 | 浏览器内 CPU 数据通路动画 |

---

## 快速开始

### 打开工程

1. 打开 Vivado 2017.4
2. Tcl Console: `cd` 到本目录 → `source create_project.tcl`
3. Run Synthesis → Implementation → Generate Bitstream
4. 烧录 `TopDebug.bit` 到 EGO1

### 模式切换

- SwitchIn[15] **拨下** = 单周期 CPU
- SwitchIn[15] **拨上** = 五级流水线 CPU

### 上板验证

```bash
# Difftest 差分测试 (需 Python + UART)
python difftest.py  # 预期 33/33 PASS

# VGA 帧缓冲地址
# 0xFFFF_0100 – 0xFFFF_13BF (80×30 字符)

# 贪吃蛇按键
# btn[0]=上  btn[1]=下  btn[2]=左  btn[3]=右  btn[4]=重开
```

---

## 目录结构

```
├── cpu_project/              # Vivado 工程
│   ├── cpu_project.xpr
│   └── cpu_project.srcs/
├── assembly/                 # 汇编测试
│   ├── batch_test.asm
│   └── batch_test.hex
├── other/                    # Bonus 代码
│   ├── vga/                  # 字模 ROM + 生成脚本
│   ├── snake/                # 贪吃蛇汇编
│   ├── isa/                  # ISA 扩展测试
│   ├── mul/                  # 软件乘法
│   └── cpu_viz/              # 可视化工具
├── project_log/              # 项目文档
├── create_project.tcl        # 一键建工程脚本
└── gitlog.txt                # Git 提交记录
```

---

## AI 工具声明

本项目使用 Claude Code (Anthropic) 辅助代码审查与文档优化，Gemini (Google) 辅助可视化页面 HTML 设计。所有 AI 生成内容均经人工审查和验证修正。
