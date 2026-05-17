# Report 素材与开发日志

## Report 提纲 (对应 requirement 5.1)

### 1. 开发者说明
- 成员姓名、学号、贡献百分比
- 每人负责的工作

| 姓名 | 学号 | 负责工作 | 贡献比 |
|------|------|---------|--------|
| 范晓乐 | 12412307 | Verilog 代码设计、工程搭建、项目协调 | |
| 刘一骏 | 12411922 | 汇编代码编写(batch_test.asm)、RARS 模拟验证 | |
| 陈俊希 | 12411025 | Vivado 综合实现、上板测试、差分测试 | |

### 2. 开发环境
- Vivado 版本：2017.4
- 操作系统：Windows (Vivado) + macOS (代码开发)
- 开发板型号：EGO1 (XC7A35T)
- GitHub Classroom 团队名：cpu-project-12412307-12411025-12411922
- 仓库地址：https://github.com/CS202ComputerOrganization/cpu-project-12412307-12411025-12411922

### 3. 开发计划与实施情况

详见下方"开发日志"章节。

### 4. CPU 架构设计说明

#### ISA 特性
- 指令集：RISC-V RV32I (基础整数指令集)
- 已实现指令：31 条（ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU, ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI, SLTIU, LW, SW, BEQ, BNE, BLT, BGE, BLTU, BGEU, LUI, AUIPC, JAL, JALR）
- 未实现：LH, LHU, LB, LBU, SH, SB（DataMemory 待扩展 byte/halfword 支持，基础 Case 不涉及）
- 寄存器：32 个 32-bit 通用寄存器 (x0-x31)，x0 硬连线为 0
- 异常处理：不支持 (基础版本)

#### CPU 架构
- 时钟频率：CPU 25MHz (100MHz 系统时钟 / 4)
- CPI：1 (单周期 CPU)
- 流水线：无 (基础版本)
- 哈佛架构：指令内存 64KB + 数据内存 64KB (物理分离)

#### 地址空间
- IMem: 0x0000_0000 - 0x0000_FFFF (64KB)。注：PC 复位地址为 0x4000（对齐 difftest），$readmemh 从 mem[4096] 开始加载
- DMem: 0x0000_0000 - 0x0000_FFFF (64KB)。测试数据基址 0x4000
- MMIO: 0xFFFF_0000 - 0xFFFF_0017 (开关/LED/按键/数码管)

#### 外设 IO
- 使用 MMIO 方式访问外设
- 轮询方式 (无中断)
- 外设地址映射：
  - 0xFFFF_0000: 开关输入 (16-bit, 只读)
  - 0xFFFF_0004: 按键输入 (5-bit, 只读)
  - 0xFFFF_0008: LED 输出 (16-bit, 读/写)
  - 0xFFFF_000C: 数码管位选 (8-bit, 读/写)
  - 0xFFFF_0010: 数码管段选组0 (8-bit, 读/写)
  - 0xFFFF_0014: 数码管段选组1 (8-bit, 读/写)

#### CPU 接口
- 时钟：100MHz 输入，内部通过 Clock Divider + BUFG 生成 25MHz CPU 时钟
- 复位：低有效，合并物理按钮复位和 Debug 软复位
- UART：115200 波特率，8N1
- Debug 接口：支持 halt/step/reset/寄存器读写/内存读写/PC 读取

#### 上板使用说明
- 复位：按下 EGO1 右下角按键 (P15)
- 开关输入：左 8 个 (sw_pin) + 右 8 个 (dip_pin)
- LED 输出：16 个 LED
- 数码管：8 位共阳极，位选 + 两组段选
- Debug：通过 Micro USB 串口连接 PC

### 5. 自测试说明

| 测试方法 | 测试类型 | 测试用例 | 结果 |
|---------|---------|---------|------|
| 模拟 | 单元 | Case 0-9 逐个模拟 | |
| 上板 | 集成 | 传统 I/O 测试 | |
| 差分测试 | 集成 | 33 组批量测试 | |

### 6. Bonus (如有)
- 功能点描述：
- 设计思路与模块关系：
- 核心代码说明：
- 测试说明：

### 7. 问题与总结

#### 开发过程关键决策与心路历程

**1. 架构选型：单周期 vs 流水线**
最初考虑直接上五级流水线，但评估后选择单周期先行。理由：① 单周期调试简单，所有状态在同一拍可见 ② 基础功能 80 分单周期即可覆盖 ③ 留出时间打磨代码质量和测试覆盖。流水线作为 Bonus 备选，待基础功能全 PASS 后再评估时间窗口。

**2. 哈佛 vs 冯诺依曼架构**
选择哈佛架构。Difftest 差分测试框架通过 UART 分别访问 IMem 和 DMem（WRITE_INST vs WRITE_DMEM），物理分离天然匹配。且双口 BRAM 独立读写避免结构冲突。

**3. Difftest 地址对齐问题**
Difftest 默认将 batch_test.hex 加载到 IMem 字节地址 0x4000，而 CPU 的 PC 初始设计为 0x0000。最初试图让 difftest 改配置，但它是课程提供的封闭工具。最终决定 CPU 侧适配：PC_RESET = 0x4000，$readmemh 偏移 4096。所有 PC 相对跳转指令不受影响。
心得：嵌入式工具链对接时，适配外部工具比强行改造工具更高效。

**4. Vivado 2017.4 的 Verilog 语法限制**
遇到多个 Verilog-2001 不被 Vivado 2017.4 完整支持的情况：表达式 part-select、always 块内变量声明等。每次都是 Windows 队友综合报错 → Mac 侧查语法 → 重构为兼容写法。跨平台协作的典型摩擦。

**5. 跨时钟域设计的取舍**
DebugController 和 UART 跑 100MHz，CPU 跑 25MHz。BRAM 同步读使用 negedge clk 给组合逻辑留半拍 settling time。MEM_WAIT_CYCLES = 20 保证 Debug 写信号被 25MHz 域稳定采样。无异步 FIFO，纯同步器 + 等待计数——简单但足够可靠。

**6. RARS 模拟器与硬件地址空间不一致**
RARS 默认数据段在 0x10010000，而我们硬件 DMem 仅 64KB（0x0000-0xFFFF）。汇编队友无法在 RARS 中直接访问 0x4000。解决：RARS Compact 内存模式，不改硬件。又一个"工具适配硬件"的案例。

**7. 三人异步协作模式**
Mac（代码）→ Windows（综合上板）→ Mac（修 bug）→ Windows（回归）。每轮迭代周期取决于沟通效率。Tcl 脚本和详细操作指南是减少沟通摩擦的关键——Windows 队友不需要理解代码，只需按步骤操作。

#### 对课程项目的建议
- 建议课程组提供统一的 RARS 内存配置文件，避免每个组踩同样的坑
- 建议提供 Vivado 2017.4 的语法兼容性清单（已知不支持的特性）
- difftest 的 IMem 起始地址如果可以配置，能减少硬件侧的适配工作

---

## 开发日志

### 第 12 周 (5月)
- 完成 Requirement 文档阅读理解
- 完成 DebugController/UartRx/UartTx 代码审查和中文注释
- 完成项目文件结构整理
- 完成 CPU 架构设计 (单周期、哈佛、RISC-V RV32I)
- 完成全部 11 个 Verilog 模块编写和审查
- 完成 EGO1 XDC 引脚约束
- 完成 batch_test.asm (全部 10 个 Case)

### 第 13 周 (5月)
- 修复 JAL/JALR 写回 bug（WD3 未选通 PC+4）
- 修复 JALRTarget 语法错误（表达式 part-select 不被 Vivado 2017.4 支持）
- 内存扩容 16KB→64KB（适配测试基址 0x4000）
- EGO1 端口对齐修正 (SwitchIn 32→16, ButtonIn 32→5, LEDOut 32→16, 7-seg 拆分为 seg_cs+seg_data_0+seg_data_1)
- batch_test.asm 全部 10 个 Case 完成
- batch_test.hex 编译完成（130 条指令），反汇编逐条验证通过
- Vivado TCL 一键建工程脚本
- ego1.xdc 引脚约束文件创建
- 团队协作指南 project_log/ 建立
- 进度检查表 5_progress_form 完成
- Bonus 规划（VGA + 贪吃蛇 = 10 分）
- PC_RESET 从 0x0000 改为 0x4000（对齐 difftest 差分测试框架）
- Ifetch $readmemh 加载偏移改为 mem[4096]（对应字节地址 0x4000）

### 第 14 周
- RARS 模拟验证进行中（刘一骏）
- Windows 队友 Vivado 上板待执行（陈俊希）

### 第 15 周
- (待记录)

---

## Bug 记录

### Bug 1: JAL/JALR 写回错误
- 发现日期：第 13 周
- 现象：JAL/JALR 把 ALUResult (跳转目标) 写回 rd，应写 PC+4
- 修复：添加 JALWDSrc 信号，WD3 MUX 改为三选一
- 文件：CPUTop.v:253-260

### Bug 2: JALRTarget 语法错误
- 发现日期：第 13 周
- 现象：`{rs1_val + Imm}[31:1], 1'b0` 不是合法 Verilog
- 修复：改为 `{(rs1_val + Imm)[31:1], 1'b0}`
- 文件：CPUTop.v:283

### Bug 3: 内存容量不足
- 发现日期：第 13 周
- 现象：16KB 只有 4096 条目，测试数据可能越界
- 修复：扩容至 64KB (16384 条目)，地址宽度改为 [15:2]
- 文件：Ifetch.v, DataMemory.v

### Bug 4: EGO1 端口宽度不匹配
- 发现日期：第 13 周
- 现象：TopDebug 端口使用了 32-bit 总线，EGO1 实际硬件宽度不同
- 修复：SwitchIn 32→16, ButtonIn 32→5, LEDOut 32→16, SegOut→seg_cs+seg_data_0+seg_data_1
- 文件：TopDebug.v, CPUTop.v, DataMemory.v

### Bug 5: Ifetch 中 Branch 信号未声明
- 发现日期：第 13 周
- 现象：Ifetch.v 的 Next-PC MUX 中使用了 `Branch` 信号，但该信号未在 Ifetch 端口声明
- 分析：PCSrc 已由 CPUTop 计算为 `Branch && BranchTaken`，`&& Branch` 是冗余的
- 修复：删除 `&& Branch`，直接使用 `PCSrc`
- 文件：Ifetch.v:147

### Bug 6: RegFile 中 integer i 声明位置错误
- 发现日期：第 13 周
- 现象：`integer i` 在 always 块内部声明，Verilog-2001 不支持
- 修复：将 `integer i` 移到模块级声明
- 文件：RegFile.v

### Bug 7: JALRTarget 表达式 part-select 不兼容
- 发现日期：第 13 周
- 现象：`{(rs1_val + Imm)[31:1], 1'b0}` 在 Vivado 2017.4 综合报错
- 修复：拆分为中间 wire jalr_sum，先算和再取位选
- 文件：CPUTop.v:283-284

### Bug 8: Difftest 与 CPU 起始地址不一致
- 发现日期：第 13 周
- 现象：difftest 默认从 IMem 0x4000 放指令，但 CPU PC 复位到 0x0000
- 修复：PC_RESET 改为 32'h00004000，$readmemh 加载偏移改为 mem[4096]
- 文件：Ifetch.v
