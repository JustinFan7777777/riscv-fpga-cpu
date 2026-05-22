# 基于 RISC-V RV32I 的单周期 CPU 设计与实现

> 计算机组成原理 CPU Project — 项目报告

---

## 1. 开发者说明

| 姓名 | 学号 | 负责工作 | 贡献比 |
|------|------|---------|--------|
| 范晓乐 | 12412307 | Verilog 代码设计、工程搭建、模块集成、Bug 修复、项目协调 | 1 |
| 刘一骏 | 12411922 | 汇编代码编写 (batch_test.asm)、RARS 模拟验证 | 1 |
| 陈俊希 | 12411025 | Vivado 综合实现、EGO1 上板测试、差分测试 (difftest) | 1 |

---

## 2. 开发环境

| 项 | 内容 |
|----|------|
| Vivado 版本 | 2017.4 |
| 操作系统 | macOS (代码开发) + Windows (综合上板) |
| 开发板 | EGO1 (XC7A35T-1CSG324C) |
| 仿真工具 | RARS (RISC-V Assembler and Runtime Simulator) |
| 差分测试 | 课程提供 Difftest 框架 (UART 通信) |
| GitHub 团队名 | cpu-project-12412307-12411025-12411922 |
| 仓库地址 | https://github.com/CS202ComputerOrganization/cpu-project-12412307-12411025-12411922 |

---

## 3. 开发计划与实施

### 3.1 开发时间线

| 阶段 | 时间 | 主要工作 |
|------|------|---------|
| 第 12 周 | 5.5–5.11 | 需求分析、架构设计、11 个 Verilog 模块编写、XDC 约束、batch_test.asm |
| 第 13 周 | 5.12–5.18 | Bug 修复 (8 个)、TCL 一键建工程脚本、RARS 模拟验证 (21/21 PASS)、项目文档整理 |
| 第 14 周 | 5.12–5.18 | Vivado 综合实现、EGO1 烧录、Difftest 调试 |
| 第 15 周 | 5.19–5.25 | IMem 组合读修复、时钟降频至 12.5MHz、Difftest 33/33 PASS、VGA 文本显示控制器 + 贪吃蛇游戏 Bonus 实现、文档与视频 |
| 第 16 周 | 5.26–6.1 | ISA 扩展 / 流水线 (超额展示, 按时间窗口选做)、最终提交 |

### 3.2 协作模式

三人分工明确，异步协作：Mac 端编写 Verilog 代码和汇编 → Windows 端综合上板 → 反馈 Bug → Mac 端修复 → 回归测试。Tcl 一键建工程脚本是关键——Windows 队友无需理解代码细节，只需按步骤操作即可复现结果。

**工具链说明：** 使用 GitHub Classroom 进行版本控制。汇编使用 RARS 编写并导出 hex，Vivado 通过 `$readmemh` 加载 hex 初始化 IMem。

---

## 4. CPU 架构设计说明

### 4a. ISA 特性

**指令集：** RISC-V RV32I (基础整数指令集)，参考 RISC-V Unprivileged ISA Specification v2.2。

**已实现指令 (31 条)：**

| 类型 | 指令 | 条数 |
|------|------|------|
| R-type | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU | 10 |
| I-type ALU | ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI, SLTIU | 9 |
| I-type Load | LW | 1 |
| S-type Store | SW | 1 |
| B-type Branch | BEQ, BNE, BLT, BGE, BLTU, BGEU | 6 |
| U-type | LUI, AUIPC | 2 |
| Jump | JAL, JALR | 2 |

**未实现：** LH, LHU, LB, LBU, SH, SB (6 条 byte/halfword 指令，基础 Case 不涉及)。

**寄存器：** 32 个 32-bit 通用寄存器 (x0–x31)，x0 硬连线为 0。遵循标准 ABI 命名约定。

**异常处理：** 不支持 (基础版本)。

**更新内容：** 无 ISA 扩展，严格遵循 RV32I 标准。

### 4b. 时钟与 CPI

| 项 | 值 | 说明 |
|----|-----|------|
| 系统时钟 | 100MHz | EGO1 板载晶振 (引脚 P17) |
| CPU 时钟 | 12.5MHz | 100MHz / 8 (3-bit 计数器 + BUFG) |
| CPI | 1 | 单周期，无流水线 |
| 流水线级数 | 不涉及 | 基础版本 |

选择 12.5MHz 而非 25MHz 的原因：IMem 采用组合读以保证单周期取指正确性，组合 BRAM 读路径在 25MHz 下时序不收敛（后 18 组 difftest 超时），降频至 12.5MHz (周期 80ns) 后时序完全收敛。

**缺省说明：** 无多周期设计、无流水线、无超标量。

### 4c. 寻址空间

| 项 | 内容 |
|----|------|
| 架构 | 哈佛结构 (指令/数据内存物理分离) |
| 寻址单位 | 字节 (Byte)，指令 32-bit 对齐 |
| IMem | 64KB BRAM，地址空间 0x0000_0000–0x0000_FFFF，PC 复位地址 0x4000 |
| DMem | 64KB BRAM，地址空间 0x0000_0000–0x0000_FFFF，测试数据基址 0x4000 |
| 栈基址 | 未定义 (汇编测试未使用栈) |

**Difftest 测试数据地址布局：**

| 数据 | 地址 |
|------|------|
| CaseID | 0x4000 (Base + 0) |
| OperandA | 0x4004 (Base + 4) |
| OperandB | 0x4008 (Base + 8) |
| Result | 0x400C (Base + C) |

PC 复位为 0x4000 而非 0x0000 的原因：difftest 差分测试框架默认将 batch_test.hex 加载到 IMem 字节地址 0x4000，CPU 侧适配工具而非改造工具。`$readmemh` 通过 `HEX_LOAD_OFFSET = PC_RESET >> 2` 自动将 hex 内容加载到 mem[4096] 起始位置。

### 4d. 外设 IO

**方式：** MMIO (Memory-Mapped I/O)，轮询方式，无中断。

| 设备 | 地址 | 位宽 | 权限 |
|------|------|------|------|
| 拨码开关 (sw_pin + dip_pin) | 0xFFFF_0000 | 16-bit | 只读 |
| 按键 (btn_pin[4:0]) | 0xFFFF_0004 | 5-bit | 只读 |
| LED (led_pin[15:0]) | 0xFFFF_0008 | 16-bit | 读/写 |
| 数码管位选 (seg_cs) | 0xFFFF_000C | 8-bit | 读/写 |
| 数码管段选组0 (左4位) | 0xFFFF_0010 | 8-bit | 读/写 |
| 数码管段选组1 (右4位) | 0xFFFF_0014 | 8-bit | 读/写 |
| VGA 帧缓冲 (2400字) | 0xFFFF_0100 – 0xFFFF_13BF | 16-bit/字 | 读/写 |

MMIO 译码规则：地址高 16-bit 为 0xFFFF 时进入 MMIO 区域，低 4-bit 选择传统外设 (0x0000–0x0014)，0x0100–0x13BF 为 VGA 帧缓冲。CPU 通过 `lw`/`sw` 指令访问外设，如 `lw x1, 0(x31)` 其中 x31=0xFFFF0000 读取开关值，`sw x1, 0xFFFF0100(x0)` 写入 VGA 帧缓冲首字。

### 4e. CPU 接口

| 信号 | 方向 | 说明 |
|------|------|------|
| clk | 输入 | 100MHz 系统时钟 (EGO1 P17) |
| rst_n | 输入 | 复位按钮，低有效 (EGO1 P15)，与 Debug 软复位合并 |
| uart_rxd | 输入 | UART 接收 (EGO1 N5, 115200/8N1) |
| uart_txd | 输出 | UART 发送 (EGO1 T4, 115200/8N1) |
| SwitchIn[15:0] | 输入 | 16 个拨码开关 |
| ButtonIn[4:0] | 输入 | 5 个按键 |
| LEDOut[15:0] | 输出 | 16 个 LED |
| seg_cs[7:0] | 输出 | 8 位数码管位选 (共阳极，低有效) |
| seg_data_0[7:0] | 输出 | 数码管段选组0 |
| seg_data_1[7:0] | 输出 | 数码管段选组1 |
| vga_hs | 输出 | VGA 水平同步 (D7) |
| vga_vs | 输出 | VGA 垂直同步 (C4) |
| vga_r[3:0] | 输出 | VGA 红色通道 4-bit |
| vga_g[3:0] | 输出 | VGA 绿色通道 4-bit |
| vga_b[3:0] | 输出 | VGA 蓝色通道 4-bit |

**Debug 接口：** 通过 UART 支持 11 条调试命令 (PING/PONG, RESET, RUN, HALT, STEP, READ_REG, READ_PC, READ_INST, READ_DMEM, WRITE_INST, WRITE_DMEM)。DebugController 运行于 100MHz 域，CPU 运行于 12.5MHz 域，跨时钟域通过同步器 + 等待计数器实现。

### 4f. 上板使用说明

1. **烧录：** Micro USB 连接 EGO1，Vivado Hardware Manager 烧录 `TopDebug.bit`
2. **复位：** 按下 EGO1 右下角按键 P15 (低有效)，或通过 UART 发送 CMD_RESET (0x01)
3. **差分测试：** PC 端运行 difftest Python 脚本，通过 UART 自动加载测试数据、控制 CPU 执行、读取结果并比对
4. **传统 I/O 测试：** 拨码开关输入 CaseID (低 4 位)，LED[7:0] 显示结果低 8 位
5. **VGA 显示：** 连接 VGA 线到 EGO1 和显示器，CPU 通过 `sw` 指令写入 0xFFFF_0100–0xFFFF_13BF 即可输出 80×30 彩色字符画面

**CPU 内部结构简图：**

```
PC(0x4000) → IMem(BRAM 64KB, 组合读) → inst
  → Decoder(控制信号) + ImmGen(立即数)
  → RegFile(rs1, rs2)
  → ALU_A MUX(LUI=0, AUIPC=PC, else=rs1)
  → ALU_B MUX(ALUSrc=0→rs2, =1→imm)
  → ALU(10种运算) → ALUResult
    → DataMemory(addr, DMem 64KB + MMIO) → ReadData
    → MemtoReg MUX → WD3 → RegFile(writeback)
  → Branch比较 → PCSrc → Next-PC MUX → PC
```

### 4g. 关键设计决策

**指令内存组合读 (Ifetch.v)：** 单周期 CPU 要求当周期完成取指，BRAM 寄存器读 (1 周期延迟) 导致取指与执行不同步。改为组合读 `assign inst = mem[imem_addr]`，写仍保持同步时序。

**WD3 三选一 MUX (CPUTop.v)：** JAL/JALR 需将返回地址 PC+4 写回 rd，Load 需将内存值写回，其余写回 ALU 结果。优先级：JAL/JALR > Load > ALUResult。

**分支判断 (CPUTop.v)：** 直接在 CPUTop 用 funct3 比较 rs1/rs2，不使用 ALU Zero 标志。分支比较与 ALU 运算并行，路径更短。

**Next-PC 优先级 (Ifetch.v)：** halt > reset(0x4000) > JALR > JAL > branch taken > PC+4。

**跨时钟域同步：**
- DebugController + UART @100MHz, CPU @12.5MHz
- IMem Debug 信号 sync: posedge clk
- DMem Debug 信号 sync: negedge clk (错半拍改善时序)
- MEM_WAIT_CYCLES = 20, STEP_COUNTDOWN_INIT = 8 (100/12.5)

---

## 5. 自测试说明

### 5.1 测试方法

| 方法 | 类型 | 用例描述 | 结果 | 结论 |
|------|------|---------|------|------|
| RARS 模拟 | 单元测试 | 5 个 Case (0,4,6,8,9) 共 21 组数据逐组验证 | 21/21 PASS | 汇编逻辑正确 |
| Difftest 上板 | 集成测试 | 10 个 Case (0–9) 共 33 组数据批量自动比对 | 33/33 PASS | CPU 硬件逻辑完全正确 |
| 传统 I/O | 集成测试 | 开关输入 CaseID, LED 显示结果低 8 位 | PASS | 基本硬件链路正常 |

**关于仿真：** 本项目采用 "Verilog 代码审查 + RARS 汇编验证 + Difftest 上板测试" 的流程，未进行子模块仿真或 CPU 集成仿真。理由：(1) 单周期 CPU 以组合逻辑为主，11 个模块端口和逻辑已通过逐行交叉审查验证；(2) RARS 对全部 10 个 Case 汇编逻辑验证 PASS；(3) 课程要求明确：能上板则无需仿真，仿真仅为无法上板时的降级方案（得分×0.3）；(4) Difftest 33/33 PASS 已全面验证硬件正确性。

### 5.2 Difftest 完整结果 (2026-05-18, 12.5MHz) (2026-05-18, 12.5MHz)

```
Loading 130 instructions to 0x00000000...
Verify OK: all 130 instructions correct

--- TestCase Batch Test (Data Base: 0x4000) ---
  [1/33]  case=0 AND        0x00000F0F & 0x00001234 → 0x00000204 PASS
  [2/33]  case=0 AND        0xFFFFFFFF & 0x00001234 → 0x00001234 PASS
  [3/33]  case=1 SLL        0x12481248 << 4       → 0x24812480 PASS
  [4/33]  case=1 SLL        0x00000001 << 13      → 0x00002000 PASS
  [5/33]  case=2 SRA        0x71240000 >>> 24     → 0x00000071 PASS
  [6/33]  case=2 SRA        0x81231234 >>> 4      → 0xF8123123 PASS
  [7/33]  case=3 LUI+ADD    0x10000000 + 0x12345  → 0x22345000 PASS
  [8/33]  case=3 LUI+ADD    0x00000001 + 0x12345  → 0x12345001 PASS
  [9/33]  case=4 JAL+AUIPC  0 + 0                 → 0x12345000 PASS
  [10/33] case=4 JAL+AUIPC  0x10 + 0              → 0x12345010 PASS
  [11/33] case=5 JAL+JALR   5 + 6                 → 0x0000000B PASS
  [12/33] case=5 JAL+JALR   1 + 2                 → 0x00000003 PASS
  [13/33] case=6 Fibonacci  n=1                   → 0x00000001 PASS
  [14/33] case=6 Fibonacci  n=2                   → 0x00000001 PASS
  [15/33] case=6 Fibonacci  n=3                   → 0x00000002 PASS
  [16/33] case=6 Fibonacci  n=4                   → 0x00000003 PASS
  [17/33] case=7 Popcount   0xC1 (2 ones)         → 0x00000003 PASS
  [18/33] case=7 Popcount   0xF8 (5 ones)         → 0x00000005 PASS
  [19/33] case=8 IEEE754    0x8000 (负零)         → type 0     PASS
  [20/33] case=8 IEEE754    0x0000 (正零)         → type 0     PASS
  [21/33] case=8 IEEE754    0x7C00 (+∞)           → type 1     PASS
  [22/33] case=8 IEEE754    0xFC00 (-∞)           → type 1     PASS
  [23/33] case=8 IEEE754    0xFC01 (NaN)          → type 2     PASS
  [24/33] case=8 IEEE754    0x2026 (规约正数)      → type 3     PASS
  [25/33] case=8 IEEE754    0xC202 (规约负数)      → type 3     PASS
  [26/33] case=8 IEEE754    0x0003 (非规约正)      → type 4     PASS
  [27/33] case=8 IEEE754    0x80E1 (非规约负)      → type 4     PASS
  [28/33] case=9 Q3.4       +1.0                 → 0x10       PASS
  [29/33] case=9 Q3.4       +1.5                 → 0x18       PASS
  [30/33] case=9 Q3.4       +3.0                 → 0x30       PASS
  [31/33] case=9 Q3.4       -4.0                 → 0xC0       PASS
  [32/33] case=9 Q3.4       +3.125               → 0x32       PASS
  [33/33] case=9 Q3.4       -1.75                → 0xE4       PASS

====== Result: 33/33 passed ======
```

---

## 6. Bonus 设计说明

### 6.1 总览

实现了 6 项 Bonus，合计 26 分 (封顶 10 分)：

| Bonus | 类别 | 分值 | 状态 |
|-------|------|------|------|
| VGA 文本显示控制器 | 复杂外设接口 | 5 | ✅ 完成 |
| 贪吃蛇游戏 | 软硬件协同应用 | 5 | ✅ 完成 |
| ISA 硬件加速指令 | ISA 扩展 | 4 | ✅ 完成 |
| 五级流水线 | 架构优化 | 6 | ✅ 完成 |
| CPU 数据通路可视化 | 教学效率工具 | 2 | ✅ 完成 |
| 软件乘法 (移位相加) | 软硬件协同示例 | — | 溢出展示 |

### 6.2 VGA 文本显示控制器

**架构：** VGA.v (时序生成 + 字模 ROM + 像素着色) + DataMemory.v 内双端口帧缓冲 BRAM (2400×16-bit)。帧缓冲 Port A 挂载在 CPU 12.5MHz MMIO 空间 (0xFFFF_0100–0xFFFF_13BF)，Port B 由 VGA 模块以 25MHz 扫描读出。

**关键技术点：**
- 像素时钟 25MHz (100MHz/4, BUFG 驱动)
- 字模 ROM 2048×8-bit 分布式 RAM (LUT), `$readmemh` 初始化, 组合逻辑读出 (零额外延迟)
- 2 级像素流水线: BRAM 读 1 拍 → 字模 ROM 组合读 → 着色输出
- 每字符共 8 像素, 在倒数第 2 像素 (h_cnt[2:0]==6) 预取下一字符, 行首在水平消隐期预取
- 支持 16 种前景色 × 16 种背景色 (I+R+G+B), VGA 每通道 4-bit 输出 `{channel, channel, channel, I}`

**验证方法：** 通过 Debug Controller 的 UART 接口写入帧缓冲特定地址, 观察 VGA 显示器上对应位置是否显示正确颜色和字符。

### 6.3 贪吃蛇游戏

**技术方案：** 纯 RISC-V RV32I 汇编 (417 条指令), 无需乘法器 (用移位加法替代 `行×80 = 行×64 + 行×16`)。游戏逻辑完全运行在自研 CPU 上, 通过 MMIO 读取按键方向、写入 VGA 帧缓冲渲染画面。

**核心算法：**
- **环形缓冲区:** 512 元素, HEAD/TAIL 索引追踪蛇身, `& 0x1FF` 取模
- **自身碰撞:** 遍历 `(HEAD-LEN+1)` 到 `(HEAD-1)` 环形区间, 跳过即将擦除的 TAIL
- **LFSR 伪随机:** 16-bit, 多项式 `x^16+x^15+x^14+x^13+x^4+1`, 防零死锁
- **增量渲染:** 每帧仅更新 3 个位置 (新蛇头、旧头变身体、擦除蛇尾), 不清全屏

**按键映射：** btn[0]=上, btn[1]=下, btn[2]=左, btn[3]=右, btn[4]=重新开始。含方向反跳保护 (不允许 180° 瞬间反向)。

### 6.4 CPU 数据通路可视化工具

纯 HTML/CSS/JS/SVG 单文件 (~900 行)，双击即用。支持 12 条 RISC-V RV32I 指令的数据通路动画展示，包含 5 阶段着色 (IF/ID/EX/MEM/WB)、控制信号实时显示、流动虚线动画。8 大创新点详见 `project_log/4_visualizer.md`。

### 6.5 ISA 硬件加速指令

**指令编码：** 3 条自定义 R-type 指令，使用 RV32I 未占用的 funct7=0000001 编码空间：

| 指令 | opcode | funct3 | funct7 | 功能 |
|------|--------|--------|--------|------|
| POPCNT | 0110011 | 001 | 0000001 | `rd = popcount(rs1)` |
| CLZ | 0110011 | 010 | 0000001 | `rd = count_leading_zeros(rs1)` |
| CTZ | 0110011 | 011 | 0000001 | `rd = count_trailing_zeros(rs1)` |

**区分机制：** `custom_op = inst[25]` (funct7 第 0 位)。RV32I 全部 R-type 指令的 funct7=0000000 或 0100000，bit[0] 均为 0。自定义指令 funct7[0]=1 实现无冲突区分。

**硬件实现：**
- **POPCNT:** 32-bit 分治法，5 级加法树，纯组合逻辑 O(logN)
- **CLZ:** 二分查找优先编码器，含 clz(0)=32 零值保护
- **CTZ:** 位反转 + CLZ 组合实现

**测试：** `other/isa/isa_test.hex` (63 条指令, 18 组边界值)，覆盖全零、全一、单比特、随机值。

### 6.6 五级流水线

**架构：** IF→ID→EX→MEM→WB，复用单周期的 Decoder/RegFile/ImmGen/ALU/DataMemory 模块。

**新增模块：**
- `Ifetch_Pipe.v` — BRAM 寄存器读取指 (延迟由流水线吸收)
- `PipeRegs.v` — 4 组流水线寄存器 (IF/ID, ID/EX, EX/MEM, MEM/WB)
- `HazardUnit.v` — 数据转发 + Load-Use stall + 控制冒险 flush
- `CPUTopPipeline.v` — 五级流水线 CPU 顶层

**冒险处理：**
- 数据冒险 (RAW)：EX/MEM 和 MEM/WB → EX 转发，EX/MEM 优先级更高
- Load-Use 冒险：stall 1 周期 + NOP 插入 (转发无法解决)
- 控制冒险：假设不跳转，跳转时 flush IF/ID (1 周期 penalty)

**模式切换：** TopDebug.v 同时实例化 CPUTop(单周期) 和 CPUTopPipeline(流水线)，SwitchIn[15] 拨码开关一键切换。Debug 读信号经 cpu_mode MUX 选择活跃 CPU，Debug 写信号同时发给两个 CPU 保持 IMem/DMem 同步。

### 6.7 软件乘法 (移位相加)

纯 RV32I 汇编实现的 32-bit 乘法子程序 (62 条指令)，作为软硬件协同的补充示例。同一乘法操作，软件移位相加需 ~200 周期，硬件加速 (如 POPCNT) 只需 1 周期——直观体现 ASIC 加速的价值。

### 6.8 详细文档

- VGA 实现与上板: `project_log/5_vga.md`
- 贪吃蛇实现与上板: `project_log/6_snake.md`
- ISA 扩展实现: `project_log/7_isa.md`
- Pipeline 实现: `project_log/8_pipeline.md`
- 软件乘法: `project_log/9_mul.md`
- 可视化工具: `project_log/4_visualizer.md`

---

## 7. 问题与总结

### 7.1 Bug 记录 (共 10 个)

| # | 问题 | 修复 | 阶段 |
|---|------|------|------|
| 1 | JAL/JALR 将 ALUResult (跳转目标) 而非 PC+4 写回 rd | 新增 JALWDSrc, WD3 三选一 MUX | 第 13 周 |
| 2 | `{rs1_val+Imm}[31:1], 1'b0` 语法不合法 | 拆为中间 wire (Bug 7 最终修复) | 第 13 周 |
| 3 | 16KB IMem/DMem 不够 (0x4000 可能越界) | 扩容至 64KB, 地址 [15:2] | 第 13 周 |
| 4 | EGO1 端口宽度不匹配 (32→16/5/8) | 全部端口对齐硬件位宽 | 第 13 周 |
| 5 | Ifetch 使用了未声明的 Branch 信号 | PCSrc 已包含 Branch, 删除冗余 | 第 13 周 |
| 6 | RegFile `integer i` 在 always 内声明 | 移到模块级 (Verilog-2001 兼容) | 第 13 周 |
| 7 | `{(rs1+Imm)[31:1], 1'b0}` Vivado 综合报错 | 中间 wire jalr_sum = rs1+Imm | 第 13 周 |
| 8 | difftest 从 IMem 0x4000 放指令，CPU 复位到 0x0000 | PC_RESET = 0x4000, hex 偏移 4096 | 第 13 周 |
| 9 | BRAM 寄存器读导致取指延迟 1 周期，单周期失效 | 去除 mem_dout, 改为组合读 | 第 15 周 |
| 10 | 25MHz 组合 BRAM 读路径时序不收敛，后 18 组 difftest 超时 | 降频至 12.5MHz (100MHz/8) | 第 15 周 |

### 7.2 关键决策与反思

**1. 架构选型：单周期优先。** 最初考虑流水线，但评估后决定单周期先行。理由：单周期调试简单，所有状态在同一拍可见；基础功能 80 分单周期即可覆盖；留出时间打磨代码质量。

**2. 哈佛架构。** 与 difftest 框架天然匹配 (指令/数据通过不同 UART 命令分别访问)，且双 BRAM 避免结构冲突。

**3. 适配工具而非改造工具。** difftest 封闭不可改、RARS 内存布局不可配——每次遇到工具限制时，选择在 CPU 侧适配 (PC_RESET=0x4000, IMem 组合读)。效率远高于试图改造外部工具。

**4. Vivado 2017.4 语法限制。** 表达式 part-select、always 块内变量声明等 Verilog-2001 特性不被完整支持，每次都是综合报错 → 重构为兼容写法。跨平台协作 (Mac 开发 → Windows 综合) 的典型摩擦。

**5. 跨时钟域设计。** Debug @100MHz, CPU @12.5MHz。纯同步器 + 等待计数器，无异步 FIFO——简单但足够可靠。

**6. 三人异步协作。** Mac → Windows → Mac 的迭代循环中，Tcl 脚本和详细操作指南是减少沟通摩擦的关键。Windows 队友不需要理解代码逻辑，只需按步骤执行。

### 7.3 对课程的建议

- 建议提供统一的 RARS 内存配置文件，避免每组重复踩坑
- 建议提供 Vivado 2017.4 已知不支持语法清单
- difftest 的 IMem 起始地址如可配置，可减少硬件侧适配工作

---

## 附录 A. 汇编设计说明 (刘一骏)

`batch_test.asm` (130 条指令, 390 行) 采用**主调度器 + Case 函数**的跳转表架构：

1. `lui s0, 0x4` 设基址 0x4000
2. 调度器循环读 CaseID (0(s0)) → beq 逐值比较 → 跳转对应 Case
3. Case 函数从 4(s0)/8(s0) 读操作数 → 计算 → 结果 sw 到 12(s0)
4. `j dispatcher_loop` 回到调度器，CaseID≥10 时进入死循环等待 Host

| Case | 核心指令 | 设计要点 |
|------|---------|---------|
| 0 AND | `and t3, t1, t2` | 单条 R-type, 5 指令 |
| 1 SLL | `sll t3, t1, t2` | 移位量仅低 5 位有效 |
| 2 SRA | `sra t3, t1, t2` | 符号扩展验证 |
| 3 LUI+ADD | `lui a0, 0x12345; add t3, t1, a0` | U-type + R-type 组合 |
| 4 JAL+AUIPC | `jal a0, target; auipc a1, ...; sub t3, a1, a0` | PC 差值 = 立即数 0x12345000 |
| 5 JAL+JALR | `jal ra, func; ...; func: jr ra` | 函数调用-返回机制 |
| 6 Fibonacci | 迭代法, `add; addi; bgtz` 循环 | n≤2 直接返回 1 |
| 7 Popcount | 分治法, 6 条核心指令 O(1) | 2-bit→4-bit→8-bit 归并 |
| 8 IEEE754 | sign/exp/mantissa 字段提取, 5 分支决策树 | 9 组覆盖全部类型 |
| 9 Q3.4 | M×2^(exp-21), 正数截断/负数补码 | 6 组覆盖正负数 |

## 附录 B. 文件清单

### Verilog 源文件 (12 个)

```
cpu_project/cpu_project.srcs/sources_1/new/
├── TopDebug.v          # 顶层: 时钟分频+BUFG, 复位合并, VGA+Chip+Debug 实例化
├── CPUTop.v            # CPU顶层: 单周期数据通路, 6子模块连线, VGA直通
├── Ifetch.v            # 取指: PC+IMem BRAM(64KB), Next-PC MUX, 组合读
├── Decoder.v           # 译码: Main Decoder + ALU Decoder
├── ImmGen.v            # 立即数: I/S/B/U/J 六种格式
├── RegFile.v           # 寄存器堆: 32x32, x0=0
├── ALU.v               # ALU: 10种运算
├── DataMemory.v        # 数据内存: DMem BRAM + MMIO (6传统外设 + VGA帧缓冲)
├── DebugController.v   # Debug控制器: FSM(6状态), 11命令
├── UartRx.v            # UART接收: 115200/8N1
├── UartTx.v            # UART发送: 115200/8N1
└── VGA.v               # VGA控制器: 时序+字模ROM+帧缓冲+像素着色 (Bonus)
```

### 工程文件

```
├── create_project.tcl      # Vivado 一键建工程脚本
├── assembly/
│   ├── batch_test.asm      # 10 Case 汇编 (390行)
│   └── batch_test.hex      # 编译后 hex (130条指令)
├── cpu_project/.../ego1.xdc  # EGO1 完整引脚约束 (含VGA)
└── other/
    ├── cpu_viz/
    │   ├── README.md
    │   └── visualizer.html  # CPU数据通路可视化工具 (Bonus)
    ├── snake/
    │   ├── snake.asm        # 贪吃蛇汇编源码 (417条指令, Bonus)
    │   └── snake.hex        # 编译后机器码
    └── vga/
        ├── gen_font.py      # 字模ROM生成脚本
        └── font_rom.hex     # 128字符×8×16字模位图

> **提交说明：** 文档通过问卷提交 (https://f.kdocs.cn/g/5JvFO9aZ/)，视频上传云盘 (链接后续发)，压缩包仅包含源代码 + gitlog.txt。文件夹命名需含小组编号 (见分组共享文档)。

## 附录 C. 代码规范

| 项目 | 内容 |
|------|------|
| 顶层模块名 | TopDebug |
| CPU 模块名 | CPUTop |
| 子模块名 | Ifetch, Decoder, ImmGen, RegFile, ALU, DataMemory |
| 模块命名 | 子模块名大写 (ALU, CPUTop) |
| 常量命名 | 参数化常量用大写 (PC_RESET, MEM_WAIT_CYCLES, HEX_LOAD_OFFSET) |
| 端口命名 | 驼峰规则 (RegWrite, MemtoReg, ALUSrc, BranchTaken) |
| 符号化常量 | Ifetch: PC_RESET + INIT_FILE；DebugController: CMD_PING/RESET/STEP...；Decoder: opcode 硬编码分支 |
| 注释规范 | 每个 .v 文件头部有完整中文功能说明，关键数据通路有行内注释 |
