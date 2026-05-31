# 基于 RISC-V RV32I 的单周期 & 五级流水线 CPU 设计与实现

> 计算机组成原理 CPU Project — 项目报告 (小组 Tue34_w_10)
> 提交问卷链接: https://f.kdocs.cn/g/5JvFO9aZ/

---

## 1. 开发者说明

| 姓名 | 学号 | 负责工作 | 贡献比 |
|------|------|---------|--------|
| 范晓乐 | 12412307 | Verilog 设计 (16个模块)、VGA 控制器、五级流水线、ISA 扩展、可视化工具、项目协调 | 40% |
| 陈俊希 | 12411025 | Vivado 综合实现、EGO1 上板测试、Difftest 差分测试验证 | 30% |
| 刘一骏 | 12411922 | 汇编代码编写 (batch_test.asm / snake.asm)、RARS 模拟验证 | 30% |

**AI 工具使用声明 (Requirement 1.1)：**
- **Claude Code (Anthropic)** — 用于 Verilog 代码审查与优化、文档汇总与润色、汇编代码调试辅助、Python 字模生成脚本
- **Gemini (Google)** — 用于 CPU 数据通路可视化工具 (other/cpu_viz/visualizer.html) 的初始 HTML 页面代码设计

> 所有 AI 生成代码均经人工审查、修改和验证，最终版本由团队成员确认。项目核心架构设计、Verilog 模块实现、Difftest 上板测试由团队成员自行完成。

---

## 2. 开发环境

| 项 | 内容 |
|----|------|
| Vivado 版本 | 2017.4 |
| 操作系统 | macOS (代码开发) + Windows (综合上板) |
| 开发板 | EGO1 (XC7A35T-1CSG324C) |
| 仿真工具 | RARS (RISC-V Assembler and Runtime Simulator) |
| 差分测试 | 课程提供 Difftest 框架 (UART 通信, v1.4) |
| GitHub 团队名 | cpu-project-12412307-12411025-12411922 |
| 仓库地址 | https://github.com/CS202ComputerOrganization/cpu-project-12412307-12411025-12411922 |

---

## 3. 开发计划与实施

### 3.1 开发时间线

| 阶段 | 时间 | 主要工作 |
|------|------|---------|
| 第 12 周 | 5.5–5.11 | 需求分析、架构设计、11 个 Verilog 模块编写、XDC 约束、batch_test.asm |
| 第 13 周 | 5.12–5.18 | Bug 修复 (8 个)、RARS 模拟验证、项目文档框架搭建 |
| 第 14 周 | 5.19–5.25 | Vivado 综合实现、EGO1 烧录、Difftest 调试、IMem 组合读修复、时钟降频至 12.5MHz |
| 第 15 周 | 5.26–6.1 | Difftest 33/33 PASS、6 项 Bonus 全部实现、文档完善、视频录制 |

### 3.2 协作模式

三人分工明确，异步协作：Mac 端编写 Verilog 代码和汇编 → Windows 端综合上板 → 反馈 Bug → Mac 端修复 → 回归测试。通过 GitHub Classroom 进行版本控制，gitlog.txt 记录完整提交历史。

---

## 4. CPU 架构设计说明

### 4a. ISA 特性

**指令集：** RISC-V RV32I (基础整数指令集)，参考 RISC-V Unprivileged ISA Specification v2.2。

**已实现指令 (31 条标准 + 3 条自定义)：**

| 指令 | 类型 | opcode | funct3 | funct7 | 汇编格式 | 功能描述 |
|------|------|--------|--------|--------|---------|---------|
| ADD | R | 0110011 | 000 | 0000000 | `ADD rd, rs1, rs2` | rd = rs1 + rs2 |
| SUB | R | 0110011 | 000 | 0100000 | `SUB rd, rs1, rs2` | rd = rs1 - rs2 |
| SLL | R | 0110011 | 001 | 0000000 | `SLL rd, rs1, rs2` | rd = rs1 << rs2[4:0] |
| SLT | R | 0110011 | 010 | 0000000 | `SLT rd, rs1, rs2` | rd = (rs1 < rs2 有符号) ? 1 : 0 |
| SLTU | R | 0110011 | 011 | 0000000 | `SLTU rd, rs1, rs2` | rd = (rs1 < rs2 无符号) ? 1 : 0 |
| XOR | R | 0110011 | 100 | 0000000 | `XOR rd, rs1, rs2` | rd = rs1 ^ rs2 |
| SRL | R | 0110011 | 101 | 0000000 | `SRL rd, rs1, rs2` | rd = rs1 >> rs2[4:0] (逻辑) |
| SRA | R | 0110011 | 101 | 0100000 | `SRA rd, rs1, rs2` | rd = rs1 >> rs2[4:0] (算术) |
| OR | R | 0110011 | 110 | 0000000 | `OR rd, rs1, rs2` | rd = rs1 \| rs2 |
| AND | R | 0110011 | 111 | 0000000 | `AND rd, rs1, rs2` | rd = rs1 & rs2 |
| ADDI | I | 0010011 | 000 | — | `ADDI rd, rs1, imm` | rd = rs1 + imm |
| SLLI | I | 0010011 | 001 | 0000000 | `SLLI rd, rs1, shamt` | rd = rs1 << shamt |
| SLTI | I | 0010011 | 010 | — | `SLTI rd, rs1, imm` | rd = (rs1 < imm 有符号) ? 1 : 0 |
| SLTIU | I | 0010011 | 011 | — | `SLTIU rd, rs1, imm` | rd = (rs1 < imm 无符号) ? 1 : 0 |
| XORI | I | 0010011 | 100 | — | `XORI rd, rs1, imm` | rd = rs1 ^ imm |
| SRLI | I | 0010011 | 101 | 0000000 | `SRLI rd, rs1, shamt` | rd = rs1 >> shamt (逻辑) |
| SRAI | I | 0010011 | 101 | 0100000 | `SRAI rd, rs1, shamt` | rd = rs1 >> shamt (算术) |
| ORI | I | 0010011 | 110 | — | `ORI rd, rs1, imm` | rd = rs1 \| imm |
| ANDI | I | 0010011 | 111 | — | `ANDI rd, rs1, imm` | rd = rs1 & imm |
| LW | I | 0000011 | 010 | — | `LW rd, offset(rs1)` | rd = mem[rs1 + offset] |
| SW | S | 0100011 | 010 | — | `SW rs2, offset(rs1)` | mem[rs1 + offset] = rs2 |
| BEQ | B | 1100011 | 000 | — | `BEQ rs1, rs2, offset` | if (rs1 == rs2) PC += offset |
| BNE | B | 1100011 | 001 | — | `BNE rs1, rs2, offset` | if (rs1 != rs2) PC += offset |
| BLT | B | 1100011 | 100 | — | `BLT rs1, rs2, offset` | if (rs1 < rs2 有符号) PC += offset |
| BGE | B | 1100011 | 101 | — | `BGE rs1, rs2, offset` | if (rs1 >= rs2 有符号) PC += offset |
| BLTU | B | 1100011 | 110 | — | `BLTU rs1, rs2, offset` | if (rs1 < rs2 无符号) PC += offset |
| BGEU | B | 1100011 | 111 | — | `BGEU rs1, rs2, offset` | if (rs1 >= rs2 无符号) PC += offset |
| LUI | U | 0110111 | — | — | `LUI rd, imm` | rd = imm << 12 |
| AUIPC | U | 0010111 | — | — | `AUIPC rd, imm` | rd = PC + (imm << 12) |
| JAL | J | 1101111 | — | — | `JAL rd, offset` | rd = PC+4; PC += offset |
| JALR | I | 1100111 | 000 | — | `JALR rd, offset(rs1)` | rd = PC+4; PC = (rs1+offset) & ~1 |

**Bonus ISA 扩展 (3 条自定义指令)：**

| 指令 | opcode | funct3 | funct7 | 功能 |
|------|--------|--------|--------|------|
| POPCNT | 0110011 | 001 | 0000001 | `rd = popcount(rs1)` |
| CLZ | 0110011 | 010 | 0000001 | `rd = count_leading_zeros(rs1)` |
| CTZ | 0110011 | 011 | 0000001 | `rd = count_trailing_zeros(rs1)` |

区分机制：`inst[25]` (funct7[0])。所有 RV32I 标准 R-type 指令 funct7[0]=0，自定义指令设 funct7[0]=1 实现零冲突。

**寄存器：** 32 个 32-bit 通用寄存器 (x0–x31)，x0 硬连线为 0。遵循标准 ABI 命名约定。

**异常处理：** 不支持 (基础版本)。

### 4b. 时钟与 CPI

| 项 | 单周期模式 | 流水线模式 |
|----|-----------|-----------|
| 系统时钟 | 100MHz (EGO1 P17) | 同 |
| CPU 时钟 | 12.5MHz (100MHz/8, 经 BUFG) | 同 |
| CPI | 1 | ≈1 (理想), >1 (stall/flush 时) |
| 流水线级数 | 不涉及 | 5 级 (IF→ID→EX→MEM→WB) |
| 冲突解决 | 不涉及 | 转发 (EX/MEM & MEM/WB→EX) + Load-Use stall + 分支 flush |

选择 12.5MHz 的原因：IMem 采用组合读以保证单周期取指正确性，组合 BRAM 读路径在更高频率下时序不收敛，降频至 12.5MHz (周期 80ns) 后时序完全收敛。

### 4c. 寻址空间

| 项 | 内容 |
|----|------|
| 架构 | 哈佛结构 (指令/数据内存物理分离) |
| 寻址单位 | 字节 (Byte)，指令 32-bit 对齐 |
| IMem | 8KB BRAM (2048×32-bit)，地址空间 PC: 0x4000–0x5FFF → 物理: 0x0000–0x07FF |
| DMem | 64KB BRAM (16384×32-bit)，地址空间 0x0000_0000–0x0000_FFFF |
| 栈基址 | 0x0000_F000 (sp=x2 初始化至此) |
| PC 复位 | 0x00004000 (适配 Difftest 框架) |

**Difftest 测试数据地址布局：**

| 数据 | 地址 |
|------|------|
| CaseID | 0x4000 (Base + 0) |
| OperandA | 0x4004 (Base + 4) |
| OperandB | 0x4008 (Base + 8) |
| Result | 0x400C (Base + C) |

注意：IMem 从 64KB 缩减至 8KB (2048 字) 以节省 LUT 资源。物理地址通过 `imem_phys_addr = PC[10:2]` 映射，覆盖 PC 0x4000–0x5FFF。

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

MMIO 译码规则：地址高 16-bit 为 0xFFFF 时进入 MMIO 区域。低 4-bit 选择传统外设 (0x0000–0x0014)，Addr[15:0] 在 0x0100–0x13BF 范围为 VGA 帧缓冲。CPU 通过 `lw`/`sw` 指令访问外设。

### 4e. CPU 接口

| 信号 | 方向 | 说明 |
|------|------|------|
| clk | 输入 | 100MHz 系统时钟 (EGO1 P17) |
| rst_n | 输入 | 复位按钮，低有效 (EGO1 P15)，与 Debug 软复位合并 |
| uart_rxd | 输入 | UART 接收 (EGO1 N5, 115200/8N1) |
| uart_txd | 输出 | UART 发送 (EGO1 T4, 115200/8N1) |
| SwitchIn[15:0] | 输入 | 16 个拨码开关，SwitchIn[15]=模式切换 |
| ButtonIn[4:0] | 输入 | 5 个按键 |
| LEDOut[15:0] | 输出 | 16 个 LED |
| seg_cs[7:0] | 输出 | 8 位数码管位选 (共阳极，低有效) |
| seg_data_0[7:0] | 输出 | 数码管段选组0 (左4位) |
| seg_data_1[7:0] | 输出 | 数码管段选组1 (右4位) |
| vga_hs | 输出 | VGA 水平同步 (D7) |
| vga_vs | 输出 | VGA 垂直同步 (C4) |
| vga_r[3:0] | 输出 | VGA 红色通道 4-bit |
| vga_g[3:0] | 输出 | VGA 绿色通道 4-bit |
| vga_b[3:0] | 输出 | VGA 蓝色通道 4-bit |

**Debug 接口：** 通过 UART 支持 11 条调试命令 (PING/PONG, RESET, RUN, HALT, STEP, READ_REG, READ_PC, READ_INST, READ_DMEM, WRITE_INST, WRITE_DMEM)。DebugController 运行于 100MHz 域，CPU 运行于 12.5MHz 域，跨时钟域通过同步器 + 等待计数器 (MEM_WAIT_CYCLES=20) 实现可靠通信。

**模式切换：** SwitchIn[15] 拨下(0)=单周期 CPU (默认)，拨上(1)=五级流水线 CPU。TopDebug.v 中两个 CPU 同时实例化，所有输出信号经 cpu_mode MUX 选择活跃 CPU。Debug 写信号同时广播到两个 CPU，保持 IMem/DMem 内容一致，切换模式无需重新加载程序。

### 4f. 上板使用说明

1. **烧录：** Micro USB 连接 EGO1，Vivado Hardware Manager 烧录 `TopDebug.bit`
2. **复位：** 按下 EGO1 按键 P15 (低有效)，或通过 UART 发送 CMD_RESET (0x01)
3. **模式切换：** SwitchIn[15]: 拨下=单周期 CPU (默认), 拨上=五级流水线 CPU。两种模式共享 IMem/DMem，切换即时生效无需重新烧录
4. **差分测试：** PC 端运行 difftest Python 脚本，通过 UART 自动加载测试数据、控制 CPU 执行、读取结果并比对
5. **传统 I/O 测试：** 拨码开关输入 CaseID，LED/数码管显示结果
6. **VGA 显示：** 连接 VGA 线到 EGO1 和显示器，CPU 通过 `sw` 写入帧缓冲即可输出 80×30 彩色字符画面
7. **贪吃蛇游戏：** 按键 btn[0]=上, btn[1]=下, btn[2]=左, btn[3]=右, btn[4]=重开。游戏画面通过 VGA 显示

### 4g. 关键设计决策

**单周期数据通路：**
- **IMem 组合读 (Ifetch.v)：** 改为 `assign inst = mem[imem_phys_addr]` 实现单周期取指，写仍保持同步时序
- **WD3 三选一 MUX (CPUTop.v)：** JAL/JALR→PC+4, Load→ReadData, 其余→ALUResult。优先级: JAL/JALR > Load > ALUResult
- **ALU_A 三选一 MUX：** LUI→0, AUIPC→PC, 其余→rs1_val
- **分支判断 (CPUTop.v)：** 直接在顶层用 funct3 比较 rs1/rs2，不使用 ALU Zero 标志，分支比较与 ALU 运算并行

**流水线特有设计：**
- **BRAM 寄存器读 (Ifetch_Pipe.v)：** 1 周期延迟由流水线吸收，使用块 RAM 节省 LUT
- **RegFile negedge 写 + bypass (RegFile_Pipe.v)：** 消除流水线 RAW 冒险的 NBA 竞争
- **复位预热：** 复位后 1 拍 stall 等待 BRAM 加载首条指令
- **flush 延长：** ctrl_flush 延迟 1 拍补偿 BRAM 读延迟，兜底清除已超前的 inst_reg

**跨时钟域：**
- DebugController + UART @100MHz, CPU @12.5MHz, VGA @25MHz
- 所有 debug 输入信号在 CPU 时钟域打一拍同步消除亚稳态
- VGA 帧缓冲使用真双端口 BRAM (Port A@12.5MHz, Port B@25MHz)，天然跨时钟域

---

## 5. 自测试说明

### 5.1 测试方法总览

| 方法 | 类型 | 用例描述 | 结果 | 结论 |
|------|------|---------|------|------|
| RARS 模拟 | 单元测试 | 10 个 Case 共 33 组数据逐组验证 | 33/33 PASS | 汇编逻辑正确 |
| Difftest 上板 | 集成测试 | 10 个 Case 共 33 组数据批量自动比对 | 33/33 PASS | CPU 硬件逻辑完全正确 |
| Pipeline 模拟器 | 单元测试 | 33 组数据 Python 周期精确模拟 | 33/33 PASS | 流水线转发/stall/flush 正确 |
| 传统 I/O | 集成测试 | 开关输入 CaseID, LED 显示结果 | PASS | 基本硬件链路正常 |

### 5.2 逐 Case 明细

| Case | 名称 | 测试组数 | 核心指令 | 验证要点 | 结果 |
|------|------|---------|---------|---------|------|
| 0 | AND | 2 | `and` | 按位与 + 全1掩码 | PASS |
| 1 | SLL | 2 | `sll` | 逻辑左移, 仅低5bit移位量 | PASS |
| 2 | SRA | 2 | `sra` | 算术右移, 符号扩展 | PASS |
| 3 | LUI+ADD | 2 | `lui, add` | U-type+R-type 组合 | PASS |
| 4 | JAL+AUIPC | 2 | `jal, auipc, sub` | PC 相对寻址, 返回地址验证 | PASS |
| 5 | JAL+JALR | 2 | `jal, jalr` | 函数调用-返回机制 | PASS |
| 6 | Fibonacci | 4 | `add, addi, bgtz` | n=1,2,3,4 迭代法, 循环控制 | PASS |
| 7 | Popcount | 2 | 分治法序列 | 8-bit popcount 边界值 | PASS |
| 8 | IEEE754 | 9 | 字段提取+分支 | 半精度浮点分类(0/∞/NaN/规约/非规约) | PASS |
| 9 | Q3.4 | 6 | 定点量化 | 半精度→Q3.4, 正数截断/负数补码 | PASS |

### 5.3 Difftest 完整结果

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

实现了 6 项 Bonus，合计 22 分 (封顶 10 分)：

| Bonus | 类别 | 最高分 | 状态 |
|-------|------|--------|------|
| VGA 文本显示控制器 | 复杂外设接口 | 5 | 完成 |
| 贪吃蛇游戏 | 软硬件协同应用 | 5 | 完成 |
| 五级流水线 | 架构优化 | 6 | 完成 |
| ISA 硬件加速指令 (POPCNT/CLZ/CTZ) | ISA 扩展 | 4 | 完成 |
| CPU 数据通路可视化 | 教学效率工具 | 4 | 完成 |
| 软件乘法 (移位相加) | 软硬件协同示例 | — | 溢出展示 |

### 6.2 VGA 文本显示控制器 [5分]

**新增文件：** VGA.v (~340 行 Verilog)

**改动文件：** TopDebug.v (VGA 端口 + 25MHz BUFG + 实例化), DataMemory.v (VGA 帧缓冲双端口 BRAM 2400×16-bit + MMIO 区域), CPUTop.v / CPUTopPipeline.v (clk_vga + vga_fb_* 直通端口)

**关键技术：** 640×480@60Hz 文本模式 (25MHz 像素时钟), 80×30 字符网格, 128 字符 × 8×16 像素字模 ROM (BRAM), 2 级像素流水线 (fb_addr 预取提前 5 像素), 12-bit 彩色 (I+R+G+B 每通道 4-bit 输出)

**MMIO：** 0xFFFF_0100–0xFFFF_13BF, 每字 16-bit: [7:0]=ASCII, [11:8]=前景色, [15:12]=背景色

### 6.3 贪吃蛇游戏 [5分]

**新增文件：** other/snake/snake.asm (~700 行, 417 条指令), other/snake/snake.txt

**关键技术：** 环形缓冲区 (512 元素, HEAD/TAIL, & 0x1FF 取模), 16-bit LFSR 伪随机食物 (x^16+x^15+x^14+x^13+x^4+1, 含 x^0 项), 增量渲染 (每帧仅 3 处变化), 移位替代乘法 (row×80 = row×64+row×16), 自身碰撞 O(n) 遍历, 方向反跳保护

### 6.4 五级流水线 [6分]

**新增文件：** CPUTopPipeline.v, Ifetch_Pipe.v, PipeRegs.v, HazardUnit.v, RegFile_Pipe.v

**复用模块：** Decoder, RegFile (逻辑复用), ImmGen, ALU, DataMemory

**冒险处理：** 转发 (EX/MEM & MEM/WB→EX, EX/MEM 优先), Load-Use stall (1 拍), 分支 flush (假设不跳转, 跳转时 1 拍 penalty)

**模式切换：** TopDebug.v 双 CPU 共存, SwitchIn[15] MUX 选择, Debug 写广播到两 CPU 保持同步

### 6.5 ISA 硬件加速指令 [4分]

**新增指令：** POPCNT (funct7=0000001, funct3=001), CLZ (010), CTZ (011)

**改动：** ALU.v (3 个组合逻辑 function), Decoder.v (custom_op=inst[25] 区分机制 + ALU 译码表)

**测试：** other/isa/isa_test.asm (63 指令, 18 组边界值), 软件 vs 硬件 ~100x 加速比

### 6.6 CPU 可视化工具 [4分]

纯 HTML+CSS+JS+SVG 单文件 (~900 行), 支持 12 条 RV32I 指令数据通路动画, 5 阶段着色, 7 条控制信号实时显示, 双击即用

### 6.7 软件乘法 [溢出展示]

纯 RV32I 移位相加乘法子程序 (62 指令), 有符号/无符号支持, 8 组自测试, ~200x 软硬件加速比对比

---

## 7. 问题与总结

### 7.1 Bug 记录 (共 12 个)

| # | 问题 | 修复 | 阶段 |
|---|------|------|------|
| 1 | JAL/JALR 将跳转目标而非 PC+4 写回 rd | 新增 JALWDSrc, WD3 三选一 MUX | 第 13 周 |
| 2 | `{rs1_val+Imm}[31:1], 1'b0` Vivado 语法不合法 | 拆为中间 wire jalr_sum | 第 13 周 |
| 3 | 16KB IMem/DMem 不够 | 扩容至 64KB | 第 13 周 |
| 4 | EGO1 端口宽度不匹配 | 全部端口对齐硬件位宽 | 第 13 周 |
| 5 | RegFile `integer i` 在 always 内声明 | 移到模块级 | 第 13 周 |
| 6 | difftest IMem 加载地址与 PC 复位不匹配 | PC_RESET=0x4000, hex 偏移 4096 | 第 13 周 |
| 7 | BRAM 寄存器读导致取指延迟 1 周期 | 改为组合读 | 第 14 周 |
| 8 | 25MHz 组合 BRAM 读路径时序不收敛 | 降频至 12.5MHz | 第 14 周 |
| 9 | VGA 字模路径指向错误目录 | 路径更正 | 第 15 周 |
| 10 | Snake 自身碰撞遍历错误索引 | 改为环形缓冲区遍历 | 第 15 周 |
| 11 | VGA 行末预取字符行号总加 1 | 仅在 v_cnt[3:0]==15 时递增 | 第 15 周 |
| 12 | LFSR 缺少 x^0 项导致周期非最大 | bit[0] 加入反馈 XOR | 第 15 周 |

### 7.2 关键决策与反思

1. **单周期优先，再扩展流水线。** 单周期调试简单，所有状态同一拍可见；流水线在此基础上新增 5 个模块复用全部基础模块。
2. **哈佛架构。** 与 difftest 框架天然匹配，双 BRAM 避免结构冲突。
3. **适配工具而非改造工具。** PC_RESET=0x4000、IMem 组合读——每次遇到工具限制选择在 CPU 侧适配。
4. **Vivado 2017.4 语法限制。** 表达式 part-select、always 内变量声明等特性不被完整支持，跨平台协作 (Mac 开发→Windows 综合) 的典型摩擦。
5. **IMem 缩减至 2K 字。** 组合读迫使分布式 RAM 实现，消耗大量 LUT。缩减 IMem 容量释放 ~14000 LUTs，确保 VGA + 双 CPU 同时适配 XC7A35T。
6. **双 CPU 共存架构。** 同时实例化两个 CPU 而非条件编译，由 SwitchIn[15] MUX 选择输出。Debug 写信号广播保持 IMem/DMem 同步，模式切换即时生效无需重新烧录。

### 7.3 对课程的建议

- 建议提供统一的 RARS 内存配置文件，避免每组重复踩坑
- 建议提供 Vivado 2017.4 已知不支持语法清单
- difftest 的 IMem 起始地址如可配置，可减少硬件侧适配工作

---

## 附录 A. 文件清单

### Verilog 源文件 (项目核心, 16 个)

```
cpu_project/cpu_project.srcs/sources_1/new/
├── TopDebug.v          # 顶层: 时钟分频+BUFG, 复位合并, 双CPU MUX, VGA直连
├── CPUTop.v            # 单周期CPU顶层: 6子模块连线, VGA直通
├── CPUTopPipeline.v    # 流水线CPU顶层: 5级流水, 冒险处理 (Bonus)
├── Ifetch.v            # 单周期取指: PC+IMem分布式RAM, 组合读
├── Ifetch_Pipe.v       # 流水线取指: PC+IMem BRAM, 寄存器读 (Bonus)
├── Decoder.v           # 译码: Main Decoder + ALU Decoder (含ISA扩展)
├── ImmGen.v            # 立即数: I/S/B/U/J 六种格式
├── RegFile.v           # 寄存器堆: 32×32, x0=0
├── RegFile_Pipe.v      # 流水线寄存器堆: negedge写+bypass (Bonus)
├── ALU.v               # ALU: 10种标准运算 + 3条ISA扩展
├── DataMemory.v        # 数据内存: DMem BRAM + MMIO + VGA帧缓冲
├── PipeRegs.v          # 流水线寄存器: 4组 IF/ID, ID/EX, EX/MEM, MEM/WB (Bonus)
├── HazardUnit.v        # 冒险检测: 转发+Load-Use stall+分支flush (Bonus)
├── DebugController.v   # Debug控制器: FSM(6状态), 11命令
├── UartRx.v            # UART接收: 115200/8N1
├── UartTx.v            # UART发送: 115200/8N1
└── VGA.v               # VGA控制器: 时序+字模ROM+帧缓冲+像素着色 (Bonus)
```

### 汇编与工具

```
assembly/
├── batch_test.asm              # 10 Case 汇编 (单周期版, 默认)
├── batch_test.txt              # 对应机器码
├── batch_test_pipeline.asm     # 10 Case 汇编 (流水线版, 含NOP)
└── batch_test_pipeline.txt     # 对应机器码

other/
├── cpu_viz/visualizer.html     # CPU数据通路可视化工具
├── snake/
│   ├── snake.asm               # 贪吃蛇汇编源码
│   └── snake.txt               # 编译后机器码
├── isa/
│   ├── isa_test.asm            # ISA扩展测试 (POPCNT/CLZ/CTZ)
│   └── isa_test.txt            # 对应机器码
├── mul/
│   ├── soft_mul.asm            # 软件乘法子程序
│   ├── soft_mul_isa.asm        # 软件乘法 dispatcher 版本
│   ├── soft_mul.txt            # 编译后机器码
│   └── soft_mul_test.txt       # 测试用机器码
└── vga/
    ├── gen_font.py             # 字模 ROM 生成脚本
    ├── font_rom.txt            # 128字符×8×16字模位图
    ├── tb_VGA.v                # VGA 仿真 testbench
    └── test.py                 # VGA 帧缓冲写入测试脚本
```
