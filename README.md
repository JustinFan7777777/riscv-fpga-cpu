# RISC-V RV32I 单周期 & 五级流水线 CPU 设计与实现

> 计算机组成原理 CPU Project — 小组 Tue34_w_10
> Difftest 33/33 PASS

---

## 成员

| 姓名 | 学号 | 负责工作 |
|------|------|---------|
| 范晓乐 | 12412307 | Verilog 设计、VGA 控制器、Pipeline、项目协调 |
| 陈俊希 | 12411025 | Vivado 综合、上板测试、Difftest 验证 |
| 刘一骏 | 12411922 | 汇编编码、RARS 模拟验证 |

---

## 项目概述

在 EGO1 (XC7A35T) 开发板上实现 RISC-V RV32I CPU，支持单周期和五级流水线双模式，SwitchIn[15] 一键切换。Difftest 差分测试 33/33 全部通过。

### Bonus 功能

| Bonus | 分值 | 说明 |
|-------|------|------|
| VGA 文本显示 | 5 | 640×480@60Hz, 80×60 彩色字符, 双端口 BRAM 帧缓冲 |
| 贪吃蛇游戏 | 5 | RV32I+MUL 汇编, MMIO 按键 + VGA 渲染 + HUD + 障碍 + 暂停/加速, 813 条指令 |
| 五级流水线 | 6 | IF→ID→EX→MEM→WB, 转发+Load-Use stall+分支 flush |
| 可视化工具 | 4 | 浏览器内 CPU 数据通路动画, 纯 HTML 单文件 |
| 软件乘法 | — | 移位相加, 32-bit 有符号/无符号, 溢出展示 |

---

## 可复现验证流程

### 前置条件

- Vivado 2017.4 (学生机环境)
- EGO1 开发板 (XC7A35T) + Micro-USB 数据线
- VGA 显示器 + VGA 线 (Bonus 验证用)
- Python 3 + pyserial (`pip install pyserial`)
- 串口驱动 (CH340/CP2102)

---

### 一、基础功能验证 (Difftest 33/33)

**1. 打开工程**
```
双击 cpu_project/cpu_project.xpr → Vivado 自动打开工程
确认 Sources 面板中 sources_1 下有 17 个 .v 文件
确认顶层模块为 TopDebug (在 Hierarchy 面板中可见)
```

**2. 综合 → 实现 → 生成比特流**
```
Flow Navigator → Run Synthesis → 等待完成 (约 5 分钟)
→ Run Implementation → 等待完成 (约 10 分钟)
→ Generate Bitstream → 等待完成 (约 3 分钟)
确认 cpu_project/cpu_project.runs/impl_1/TopDebug.bit 已生成
```

**3. 烧录到 EGO1**
```
Hardware Manager → Open Target → Auto Connect
右键 xc7a35t_0 → Program Device
选择 TopDebug.bit → Program
等待 DONE 灯亮起
```

**4. 运行 Difftest**
```bash
# 确认 SwitchIn[15] 拨下 (单周期模式)
# 确认 Micro-USB 连接 PC, 串口驱动正常
python difftest.py --port COM3    # Windows
python difftest.py --port /dev/ttyUSB0  # Linux/Mac

# 预期输出:
# ====== Result: 33/33 passed ======
```

**5. 验证模式切换**
```
SwitchIn[15] 拨下 → LED 和数码管显示单周期 CPU 输出
SwitchIn[15] 拨上 → LED 和数码管切换到流水线 CPU 输出
(两个 CPU 同时运行, 输出一致; 切换即时生效无需重新烧录)
```

---

### 二、Bonus 功能验证

#### Bonus 1: VGA 文本显示

```
1. VGA 线连接 EGO1 → 显示器
2. 显示器开机
3. 烧录 TopDebug.bit
4. 运行 VGA 测试脚本:
   python other/vga/test.py --port COM3 --text "Hello" --fg A --bg 0
5. 预期: 显示器左上角出现亮绿色 "Hello" 字符
```

#### Bonus 2: 贪吃蛇游戏

```
1. VGA 线连接 EGO1 → 显示器
2. 烧录 TopDebug.bit
3. 通过 UART 加载 snake.txt 到 IMem 0x0000:
   (使用 Debug 命令 WRITE_INST 逐条写入, 或修改 Ifetch.v 的 INIT_FILE + PC_RESET)
4. 操作按键:
   btn[0]=上  btn[1]=下  btn[2]=左  btn[3]=右  btn[4]=重开
5. 预期: 蛇移动、吃食物增长、撞墙 Game Over、btn[4] 重启
```

#### Bonus 3: 五级流水线

```
1. 烧录 TopDebug.bit (含单周期+流水线双 CPU)
2. SwitchIn[15] 拨上 → 流水线模式
3. 通过 UART 加载含 data hazard 和 control hazard 的测试程序
4. Debug 命令 HALT → STEP → 读寄存器观察转发结果
5. 预期: 转发正确, Load-Use stall 触发, 分支 flush 正确
```

#### Bonus 4: CPU 数据通路可视化

```
1. 双击 other/cpu_viz/visualizer.html
2. 浏览器中打开, 无需网络
3. 从下拉菜单选择不同指令 (ADD/LW/SW/BEQ/JAL/LUI 等)
4. 预期: SVG 数据通路逐级点亮, 控制信号表实时更新
```

#### Bonus 5: 软件乘法

```
1. 通过 UART 加载 other/mul/soft_mul.txt 到 IMem
2. 运行测试 → Debug 命令读 DMem 0x0000-0x001F
3. 预期: 8 组测试 (正×正/零/负×正/负×负/溢出) 全部 PASS
```

---

### 三、串口 Debug 命令速查

| 命令码 | 名称 | 参数 | 响应 | 说明 |
|--------|------|------|------|------|
| 0x00 | PING | 无 | PONG (0x80) | 测试连通性 |
| 0x01 | RESET | 无 | ACK (0x81) | 复位 CPU |
| 0x02 | RUN | 无 | ACK | 全速运行 |
| 0x03 | HALT | 无 | ACK | 暂停 CPU |
| 0x04 | STEP | 无 | ACK | 单步执行一条指令 |
| 0x21 | READ_REG | 1B: 寄存器号 | DATA32 + 4B | 读寄存器值 |
| 0x22 | READ_PC | 无 | DATA32 + 4B | 读 PC 值 |
| 0x23 | READ_INST | 4B: 地址 | DATA32 + 4B | 读指令内存 |
| 0x24 | READ_DMEM | 4B: 地址 | DATA32 + 4B | 读数据内存 |
| 0x40 | WRITE_INST | 8B: 地址+数据 | ACK | 写指令内存 |
| 0x41 | WRITE_DMEM | 8B: 地址+数据 | ACK | 写数据内存 |

串口参数: 115200 波特率, 8 数据位, 1 停止位, 无校验 (8N1), RAW 二进制模式

---

## 目录结构

```
├── cpu_project/              # Vivado 工程
│   ├── cpu_project.xpr       # 双击打开工程
│   ├── cpu_project.srcs/     # 源文件 (17 .v + 2 .txt + 1 .xdc)
│   └── cpu_project.runs/     # 综合/实现/比特流输出
├── assembly/                 # 汇编测试
│   ├── batch_test.asm/.txt   # 基础功能 10 Case (单周期版)
│   └── batch_test_pipeline.asm/.txt  # 基础功能 10 Case (流水线版)
├── other/                    # Bonus 代码
│   ├── vga/                  # VGA 字模ROM + 生成/测试脚本
│   ├── snake/                # 贪吃蛇汇编
│   ├── mul/                  # 软件乘法
│   └── cpu_viz/              # 数据通路可视化工具
├── Final_Report.md           # 项目总结报告
├── Inclass_Guide.md          # 现场设计备考指南
└── gitlog.txt                # Git 提交记录
```

---

## AI 工具声明

本项目使用 Claude Code (Anthropic) 辅助代码审查与文档优化，Gemini (Google) 辅助可视化页面 HTML 设计。所有 AI 生成内容均经人工审查和验证修正。
