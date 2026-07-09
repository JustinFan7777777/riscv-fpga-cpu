# RISC-V RV32I 单周期 & 五级流水线 CPU — 项目总结报告

> 计算机组成原理 CPU Project · 小组 Tue34_w_10 · 范晓乐 / 陈俊希 / 刘一骏
> Difftest 33/33 PASS · 2026 年 5 月

---

## 一、项目概述

在 EGO1 (XC7A35T-1CSG324C) FPGA 开发板上实现完整的 RISC-V RV32I CPU，支持**单周期**和**五级流水线**双模式，通过 SwitchIn[15] 拨码开关一键切换。使用 Vivado 2017.4 综合实现，Difftest v1.4 差分测试框架 33/33 全部通过。

**技术指标：** 37 条标准 RV32I 指令 + MUL | CPU 时钟 12.5MHz | 哈佛架构 | MMIO 外设 | UART Debug 接口 | VGA 640×480@60Hz

---

## 二、CPU 架构设计

### 2.1 ISA 与寄存器

**指令集：** RISC-V RV32I (基础整数指令集) + RV32M 的 MUL 子集，参考 RISC-V Unprivileged ISA Specification v2.2。37 条标准 RV32I 指令覆盖 R/I/S/B/U/J 全部六种格式 (ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND, ADDI/SLLI/SLTI/SLTIU/XORI/SRLI/SRAI/ORI/ANDI, LB/LH/LW/LBU/LHU, SB/SH/SW, BEQ/BNE/BLT/BGE/BLTU/BGEU, LUI/AUIPC, JAL/JALR)，并额外支持 MUL。

**寄存器：** 32 个 32-bit 通用寄存器 (x0–x31)，x0 硬连线为 0。

### 2.2 单周期数据通路

CPI = 1。一个 12.5MHz 时钟周期 (80ns) 内完成 IF→ID→EX→MEM→WB 全部五步。关键设计：

- **IMem 组合读：** `assign inst = mem[addr]` 零延迟取指
- **WD3 三选一 MUX：** JAL/JALR (PC+4) > Load (ReadData) > ALUResult
- **ALU_A 三选一 MUX：** LUI (0) / AUIPC (PC) / 默认 (rs1)
- **分支判断：** 直接在 CPUTop 用 funct3 比较 rs1/rs2，与 ALU 并行
- **Next-PC 优先级：** halt > reset > JALR > JAL > branch > PC+4

### 2.3 五级流水线

IF→ID→EX→MEM→WB。Forwarding (EX/MEM & MEM/WB→EX, EX/MEM 优先) 解决大部分 RAW。Load-Use stall 1 周期插入 NOP。分支 predict-not-taken, flush IF/ID 1 周期 penalty。

**独有设计：** BRAM 寄存器读 (延迟由流水线吸收) 节省 ~14000 LUTs；RegFile negedge 写 + bypass；复位预热 1 拍；flush 延长 1 拍补偿 BRAM 读延迟。

### 2.4 寻址空间 (哈佛架构)

| 存储 | 容量 | 地址范围 |
|------|------|---------|
| IMem | 8KB (2048×32-bit) | PC 0x4000–0x5FFF → 物理 0x000–0x7FF |
| DMem | 64KB (16384×32-bit) | 0x00000000–0x0000FFFF |
| MMIO | — | 0xFFFF_0000–0xFFFF_267F |
| 栈基址 | — | 0x0000F000 |

### 2.5 外设 IO (MMIO + 轮询)

| 外设 | 地址 | 位宽 | 权限 |
|------|------|------|------|
| 拨码开关 | 0xFFFF_0000 | 16-bit | 只读 |
| 按键 | 0xFFFF_0004 | 5-bit | 只读 |
| LED | 0xFFFF_0008 | 16-bit | 读/写 |
| 数码管位选/段选 | 0xFFFF_000C–0xFFFF_0014 | 8-bit | 读/写 |
| J5-1 随机种子输入 | 0xFFFF_0018 | 1-bit | 只读 |
| VGA 帧缓冲 | 0xFFFF_0100–0xFFFF_267F | 16-bit/字 (4800字) | 读/写 |

Debug 接口: UART 115200/8N1, 11 条命令 (PING/RESET/RUN/HALT/STEP/READ_REG/READ_PC/READ_INST/READ_DMEM/WRITE_INST/WRITE_DMEM)。DebugController @100MHz, CPU @12.5MHz, 跨时钟域同步。

### 2.6 模块清单 (17 个 Verilog)

| 模块 | 功能 | 行数 |
|------|------|------|
| TopDebug.v | 顶层: 时钟分频+BUFG+双 CPU MUX+VGA 直连 | ~370 |
| CPUTop.v | 单周期 CPU 顶层: 6 子模块连线 | ~330 |
| CPUTopPipeline.v | 流水线 CPU 顶层: 5 级流水+冒险处理 | ~340 |
| Ifetch.v | 单周期取指: PC+IMem 分布式 RAM+组合读 | ~175 |
| Ifetch_Pipe.v | 流水线取指: PC+IMem BRAM+寄存器读 | ~120 |
| Decoder.v | 译码: Main Decoder + ALU Decoder | ~315 |
| ImmGen.v | 立即数: I/S/B/U/J 六种格式 | ~110 |
| RegFile.v | 寄存器堆: 32×32, x0=0 | ~80 |
| RegFile_Pipe.v | 流水线寄存器堆: negedge 写+bypass | ~65 |
| ALU.v | ALU: 10 种标准运算 | ~125 |
| DataMemory.v | 数据内存: DMem BRAM+MMIO+VGA 帧缓冲 | ~235 |
| PipeRegs.v | 流水线寄存器: IF/ID, ID/EX, EX/MEM, MEM/WB | ~230 |
| HazardUnit.v | 冒险检测: 转发+Load-Use stall+分支 flush | ~95 |
| DebugController.v | Debug 控制器: FSM (6 状态), 11 命令 | ~555 |
| UartRx.v | UART 接收: 115200/8N1 | ~140 |
| UartTx.v | UART 发送: 115200/8N1 | ~125 |
| VGA.v | VGA 控制器: 时序+字模 ROM+帧缓冲+像素着色 | ~340 |

---

## 三、基础功能验证

### 3.1 测试结果

| 方法 | 用例 | 结果 |
|------|------|------|
| RARS 软件模拟 | 10 Case, 33 组数据 | 33/33 PASS |
| Difftest 上板差分测试 | 10 Case, 33 组数据自动比对 | 33/33 PASS |
| Pipeline 周期精确模拟器 | batch_test_pipeline.txt, 33 组 | 33/33 PASS |
| 传统开关+LED 上板测试 | Fibonacci (n=1-4) + IEEE754 (5 类型) 共 9 组 | 9/9 PASS |

### 3.2 Difftest 完整输出

```
[1/33]  case=0 AND        ... → 0x00000204 PASS
...
[33/33] case=9 Q3.4       -1.75 → 0xE4       PASS
====== Result: 33/33 passed ======
```

---

## 四、Bonus 功能

### 4.1 总览

| Bonus | 类别 | 最高分 | 核心文件 |
|-------|------|--------|---------|
| VGA 文本显示 | 复杂外设接口 | 5 | VGA.v, DataMemory.v (帧缓冲) |
| 贪吃蛇游戏 | 软硬件协同应用 | 5 | other/snake/snake.asm (813 指令) |
| 五级流水线 | 架构优化 | 6 | CPUTopPipeline.v, PipeRegs.v, HazardUnit.v |
| 可视化工具 | 教学效率工具 | 4 | other/cpu_viz/visualizer.html |
| 软件乘法 | 溢出展示 | — | other/mul/soft_mul.asm (62 指令) |

### 4.2 VGA 文本显示控制器

640×480@60Hz 文本模式。CPU 通过 MMIO (0xFFFF_0100–0xFFFF_267F) 写帧缓冲，VGA 控制器以 25MHz 独立时钟扫描显示。128 字符 × 8×16 字模 ROM (BRAM, `$readmemh` 加载)，显示时取 8×8 字符高度，形成 80×60 文本网格。帧缓冲为 4800×16-bit 双端口 BRAM (Port A CPU@12.5MHz, Port B VGA@25MHz)。2 级像素流水线 (fb_addr 预取提前 5 像素)。12-bit 色彩 (I+R+G+B 每通道 4-bit)。纯 Verilog, 零 IP 核。

### 4.3 贪吃蛇游戏

RISC-V RV32I+MUL 汇编实现。环形缓冲区 (512 元素, HEAD/TAIL, & 0x1FF 取模) O(1) 蛇身移动。16-bit LFSR 伪随机食物和 8 个随机障碍，种子混入 J5-1 数字输入。增量渲染。MUL 计算 VGA 行偏移 (row×80)。顶边框显示 SNAKE/SCORE/LVL，底边框显示操作提示。分数越高速度越快。自碰撞/障碍碰撞检测。btn[2] 短按暂停/继续、长按重开。

### 4.4 五级流水线

IF→ID→EX→MEM→WB。复用单周期全部模块。TopDebug 双 CPU 共存, SwitchIn[15] MUX 切换。三种冒险处理: (1) Forwarding EX/MEM & MEM/WB→EX, EX/MEM 优先; (2) Load-Use stall 1 周期 + NOP 插入; (3) 分支 predict-not-taken, flush IF/ID 1 拍。BRAM 替代分布式 RAM 省 ~14000 LUTs。RegFile negedge 写 + bypass 消 NBA 竞争。复位预热 + flush 延长补偿 BRAM 读延迟。

**性能对比 (同一 batch_test 程序, 12.5MHz 同频):** 单周期每条指令固定 1 周期 (80ns); 流水线理想 CPI≈1, 5 条指令同时在流水线中重叠执行。以 Fibonacci (n=10, 约 50 条指令) 为例: 单周期需 50 周期, 流水线需约 54 周期 (含 4 周期流水线填充 + Load-Use/NOP 开销)。Load-Use stall 仅在 `lw + use` 紧邻时触发 (1 拍), 分支 flush 仅在跳转成立时触发 (1 拍)。通过 forwarding 消除大部分 RAW 冒险后, 实际 CPI≈1.08, 相比单周期吞吐量提升约 4.6× (5 级流水线理论最大值 5×, 扣除冒险开销)。若流水线 CPU 单独优化时钟至 25MHz (将单周期关键路径拆为 5 段), 性能差距将进一步拉大。

### 4.5 CPU 数据通路可视化工具

纯 HTML+CSS+JS+SVG 单文件 (~900 行), 双击即用。支持 11 条指令数据通路动画。5 阶段着色, 7 条控制信号实时显示。声明式配置 (每指令一 JS 对象)。CSS 类驱动激活。主干路径消除视觉缺口。透明度策略 (非活跃 opacity:0.18)。断网可用。

### 4.6 软件乘法

移位相加, 32 轮迭代。无符号 + 有符号 (绝对值→无符号乘→恢复符号)。8 组自测试全部 PASS。软件 200 周期 vs 硬件 MUL 1 周期, ~200x 加速比, 直观展示硬件加速价值。

---

## 五、关键 Bug 记录 (12 个)

| # | 问题 | 修复 |
|---|------|------|
| 1 | JAL/JALR 将跳转目标而非 PC+4 写回 rd | WD3 MUX 新增 JALWDSrc 选通 PCPlus4 |
| 2 | `{expr}[31:1]` Vivado 语法不支持 | 拆为中间 wire 再取位 |
| 3 | 分布式 RAM 组合读耗尽 LUT (16000+) | IMem 16K→2K 字, 字模 ROM 改 BRAM |
| 4 | 25MHz 时序不收敛, 后 18 组 difftest 超时 | CPU 降频至 12.5MHz |
| 5 | BRAM 寄存器读导致单周期取指延迟 | 改为组合读 `assign inst = mem[addr]` |
| 6 | `integer i` 在 always 内声明, Vivado 报错 | 移到模块级声明 |
| 7 | DataMemory BRAM 含复位导致推断失败 | 移除 BRAM 的 rst_n 复位, 加 ram_style 约束 |
| 8 | VGA 字模 ROM 路径指向错误目录 | 更正 FONT_FILE 为 `other/vga/font_rom.txt` |
| 9 | VGA 行末预取字符行号总+1, 15/16 行错位 | 仅在 v_cnt[3:0]==15 时递增字符行号 |
| 10 | Snake 自身碰撞遍历 [0..len-1] 而非环形缓冲区 | 改为环形起点 `(HEAD-LEN+1) & 0x1FF` |
| 11 | LFSR 缺少 x^0 项导致周期非 65535 | bit[0] 加入反馈 XOR |
| 12 | 流水线复位后首指令为 NOP (BRAM 读延迟) | 新增 reset_stall 冻结 IF/ID 1 拍 |

---

## 六、测试汇总

基础测试通过：Difftest 33/33, RARS 33/33, Pipeline 模拟器 33/33, 传统 IO 9/9, 软件乘法 8/8, VGA 显示测试, 贪吃蛇系统测试。

---

## 七、开发工具与 AI 声明

**开发环境：** Vivado 2017.4, macOS (代码开发) + Windows (综合上板), RARS, EGO1 XC7A35T。

**版本控制：** GitHub Classroom, gitlog.txt 记录完整提交历史。

**AI 工具：** Claude Code (Anthropic) — 代码审查、文档优化、调试辅助, 发现 7 个 Bug; Gemini (Google) — visualizer.html 初始 HTML 框架。所有 AI 生成内容经人工审查和修改验证。AI 辅助代码约占总量 50%。

---

## 附录: 文件索引

```
cpu_project/cpu_project.srcs/sources_1/new/  # 17 个 Verilog 模块
assembly/                                     # 基础功能汇编 + 流水线版
other/vga/                                    # VGA 字模 + 脚本
other/snake/                                  # 贪吃蛇汇编
other/mul/                                    # 软件乘法
other/cpu_viz/                                # 可视化工具
project_log/                                  # 详细开发文档 (0_video ~ 10_todo)
Inclass_Guide.md                              # 现场设计备考指南
gitlog.txt                                    # Git 提交记录
```
